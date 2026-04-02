local Config = require "qanda.config"
local State = require "qanda.state"
local Chats = require "qanda.chats"
local Prompts = require "qanda.prompts"
local Providers = require "qanda.providers" -- LLM providers
local utils = require "qanda.utils"
local curl = require "qanda.curl"

local M = {} -- This module

-- Expose internals
M.Config = Config
M.State = State
M.Prompts = Prompts
M.Providers = Providers

---@alias Qanda.Opts table<string, any>

---Sets up the Qanda module with the given options.
---
---This function initializes various sub-modules like `Config`, `Providers`, `Prompts`, and `Chats`,
---and then creates the user command for Qanda.
---@param opts Qanda.Opts Options table to configure Qanda.
function M.setup(opts)
  Config.setup(opts)
  Providers.setup()
  Prompts.setup()
  Chats.setup()
  M.create_user_command()
end

---@private
---Presents a provider selection picker to the user.
---
---Allows the user to select an LLM provider. After selection, it calls `select_model`
---to allow the user to choose a model from the newly selected provider.
local function select_provider()
  Providers.select_provider(State.provider, function(item)
    State.provider = Providers.get_provider(item)
    Providers.select_model()
  end)
end

---Opens the main Qanda chat window.
---
---This function creates or focuses the chat buffer window.
function M.open_qanda()
  ---@todo
  utils.create_window(Config.CHAT_BUFFER_NAME, { window_mode = "right" })
end

local initialised = false

---Creates the Neovim user command `:Qanda`.
---
---This command provides various functionalities for interacting with Qanda,
---such as opening chat windows, selecting prompts, models, and providers,
---and executing prompts. It also handles one-off lazy initializations.
function M.create_user_command()
  vim.api.nvim_create_user_command("Qanda", function(arg)

    -- One-off lazy initialisations when first command is executed
    if not initialised then
      -- If the most recently used Chat window is not loaded then create a new empty chat
      if not State.chat_window.chat then
        Chats.new_chat()
      end
      initialised = true
      -- Provider restoration
      local provider_name = State.saved_state.provider or Config.provider
      local model_name = State.saved_state.model or Config.model
      if not Providers.set_provider(provider_name, model_name) then
        -- Return if the saved provider/model is invalid because the ensuing user selection is asynchronous,
        -- otherwise continue and execute the original command.
        return
      end
    end

    local args = arg.args
    if args == "" then
      args = "/prompt_picker"
    end

    if args == "/chat_window" then
      State.prompt_window:close()
      if #State.chats == 0 then
        Chats.new_chat()
      end
      Chats.open_chat()
      return
    elseif args == "/new_chat" then
      Chats.new_chat()
      Chats.open_chat()
      Prompts.open_prompt(nil)
      return
    elseif args == "/prompt_window" then
      Prompts.open_prompt(nil)
      return
    elseif args == "/chat_picker" then
      State.chats = Chats.load_chats()
      Chats.chat_picker()
      return
    elseif args == "/turn_picker" then
      Chats.turns_picker()
      return
    elseif args == "/prompt_picker" then
      Prompts.load_user_prompts()
      Prompts.user_prompt_picker()
      return
    elseif args == "/system_message_picker" then
      Prompts.load_system_messages()
      Prompts.system_message_picker()
      return
    elseif args == "/model_selector" then
      Providers.select_model()
      return
    elseif args == "/provider_selector" then
      select_provider()
      return
    elseif args == "/status" then
      local info = "\nprovider: " .. vim.inspect(State.provider.name) .. "\nmodel: " .. vim.inspect(State.provider.model) .. "\nchat: "
      local chat = State.chat_window.chat
      if chat and #chat.turns > 0 then
        info = info .. '"' .. utils.sanitize_display_entry(Chats.chat_name(chat), 60) .. '"'
      else
        info = info .. "nil"
      end
      info = info .. "\nglobal data: " .. vim.inspect(Config.get_global_data_dir())
      if Config.get_global_data_dir() ~= Config.get_data_dir() then
        info = info .. "\nlocal data: " .. vim.inspect(Config.get_data_dir())
      end
      info = info .. "\nchats: " .. vim.inspect(Config.chats_dir())
      info = info .. "\nprompts: " .. vim.inspect(Config.prompts_dir())
      utils.notify(info, vim.log.levels.INFO)
      return
    elseif args == "/dump_diagnostics" then
      utils.paste_registers()
      return
    else
      local prompt = Prompts.get_prompt(Prompts.user_prompts, args)
      if not prompt then
        utils.notify("Invalid " .. (args:sub(1, 1) == "/" and "command" or "prompt") .. "'" .. args .. "'", vim.log.levels.ERROR)
        return
      end
      M.execute_prompt(prompt)
      return
    end
  end, {
    range = true,
    nargs = "?",
    complete = function(ArgLead)
      local args = {}
      for _, p in ipairs(Prompts.user_prompts) do
        table.insert(args, p.name)
      end

      table.insert(args, "/new_chat")
      table.insert(args, "/chat_window")
      table.insert(args, "/chat_picker")
      table.insert(args, "/turn_picker")
      table.insert(args, "/prompt_window")
      table.insert(args, "/prompt_picker")
      table.insert(args, "/model_selector")
      table.insert(args, "/provider_selector")
      table.insert(args, "/system_message_picker")
      table.insert(args, "/status")
      table.insert(args, "/dump_diagnostics")

      local completion_candidates = {}
      for _, arg in ipairs(args) do
        if arg:lower():match("^" .. ArgLead:lower()) then
          table.insert(completion_candidates, arg)
        end
      end
      table.sort(completion_candidates)
      return completion_candidates
    end,
  })
end

---@alias Qanda.Prompt table<string, any>

---Executes a given prompt, sending it to the configured LLM provider.
---
---This function handles prompt expansion, constructs the API request,
---manages chat turns, and streams the LLM response back to the chat window.
---It runs in a coroutine to avoid blocking the Neovim UI.
---@param prompt Qanda.Prompt The prompt object to execute.
function M.execute_prompt(prompt)
  coroutine.wrap(function()

    local chat = State.chat_window.chat
    assert(chat)
    local turns = chat.turns

    if not prompt.content then
      return nil
    end

    -- If the prompt is a prompt template then expand it and convert it to an anonymous prompt
    if prompt.name then
      prompt = vim.tbl_deep_extend("force", {}, prompt)
      local expanded = Prompts.substitute_placeholders(prompt.content, { allow_user_inputs = true })
      if not expanded then
        return nil
      end
      prompt.name = nil -- Convert prompt template to an anonymous (expanded) prompt
      prompt.content = expanded
    end
    State.prompt_window:close()

    local turn = {
      request = prompt.content,
      provider = prompt.provider or State.provider.name,
      model = prompt.model or State.provider.model,
    }
    if prompt.model_options then
      turn.model_options = utils.shallow_clone_table(prompt.model_options)
    end
    if State.system_message and not State.system_message.consumed then
      turn.system = State.system_message.content
    end

    -- Delete the most recent chat turn if did not complete.
    if #turns > 0 and not turns[#turns].response then
      table.remove(turns)
    end

    -- Append the new turn to current chat.
    table.insert(turns, turn)

    -- Create the model Request object
    local request_data = {
      model = turn.model,
      model_options = turn.model_option,
    }

    -- Add configuration model options (lowest priority)
    local model_options = Config.model_options[turn.provider]
    if model_options then
      for k, v in pairs(model_options) do
        request_data[k] = v
      end
    end
    -- Add system message model options
    model_options = State.system_message and State.system_message.model_options
    if model_options then
      for k, v in pairs(model_options) do
        request_data[k] = v
      end
    end
    -- Add user prompt model options (highest priority)
    if turn.model_options then
      for k, v in pairs(turn.model_options) do
        request_data[k] = v
      end
    end

    -- Ensure numeric string values are converted to numbers
    utils.normalize_numerics(request_data)

    -- Add model messages
    local messages = {}
    for _, t in ipairs(turns) do
      if t.system then
        table.insert(messages, { role = "system", content = t.system })
      end
      table.insert(messages, { role = "user", content = t.request })
      if t.response then
        table.insert(messages, { role = "assistant", content = t.response })
      end
    end
    request_data.messages = messages

    -- Build the curl command
    local request = {
      host = Config.host,
      port = Config.port,
      data = request_data,
    }
    local curl_args = State.provider.module.command(request)

    if turn.system and Config.system_message_register then
      vim.fn.setreg(Config.system_message_register, turn.system)
    end

    if Config.curl_command_register then
      vim.fn.setreg(Config.curl_command_register, utils.curl_args_to_shell_command(curl_args))
    end

    -- Clear the Chat window and write the header.
    Chats.open_chat(chat, turn)

    -- Encode the request data as JSON and assign to diagnostics register
    local payload = vim.json.encode(request.data)
    if Config.request_register then
      vim.fn.setreg(Config.request_register, payload)
    end

    -- Execute the curl command streaming the output to the Chat window.
    curl.execute_command(
      curl_args,
      payload,
      State.provider.module.normaliser,
      State.chat_window.winid,
      function(response) ---@type CurlResponse
        if curl.get_job_status() ~= "stopped" then
          -- Turn did not complete
          return
        end

        if response.error then
          return
        end

        -- Update completed turn
        local data = table.concat(response.data, "\n")
        turns[#turns].response = data
        turns[#turns].timestamp = tostring(os.date(Config.TIME_STAMP_FORMAT))
        turns[#turns].duration = response.duration

        if Config.response_register then
          vim.schedule(function() -- Defer because of Neovim's "fast event" context
            vim.fn.setreg(Config.response_register, response.data)
          end)
        end

        -- Consume the system message
        if State.system_message then
          State.system_message.consumed = true
        end

        -- Save chat file
        vim.schedule(function() -- Defer because we're in a Neovim "fast event" context
          Chats.save_chat(chat)
        end)

      end
    )

  end)()
end

return M
