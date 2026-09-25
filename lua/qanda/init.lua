local Config = require "qanda.config"
local State = require "qanda.state"
local Chats = require "qanda.chats"
local Prompts = require "qanda.prompts"
local Providers = require "qanda.providers" -- LLM providers
local utils = require "qanda.utils"
local curl = require "qanda.curl"
local diagnostics = require "qanda.diagnostics"

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

local initialised = false
local last_command = nil

---Creates the Neovim user command `:Qanda`.
---
---This command provides various functionalities for interacting with Qanda,
---such as opening chat windows, selecting prompts, models, and providers,
---and executing prompts. It also handles one-off lazy initializations.
function M.create_user_command()
  vim.api.nvim_create_user_command("Qanda", function(arg)

    -- Block user commands when a turn is executing
    if curl.active_job_warning() then
      return
    end

    -- One-off lazy initialisations when first command is executed
    if not initialised then
      -- If the most recently used Chat window is not loaded then create a new empty chat
      if not State.chat_window.chat then
        Chats.new_chat()
      end
      -- Validate the provider/model and, if they`re not valid, prompt with user selection dialogs.
      local provider_name = State.saved_state.provider or Config.provider
      local model_name = State.saved_state.model or Config.model
      if
        Providers.set_provider(provider_name, model_name, function()
          vim.cmd("Qanda " .. arg.args) -- Re-execute command on successful provider/model selection
        end) == nil
      then
        -- IMPORTANT: Return if the current provider/model is invalid because `Providers.set_provider` selection is asynchronous.
        return
      end
      -- Continue executing the command
      initialised = true
    end

    local args = arg.args
    if args == "" then
      args = "/help"
    end

    if args == "/repeat" then
      if not last_command then
        utils.notify("No commands have yet been executed", vim.log.levels.WARN)
        return
      end
      args = last_command
    else
      last_command = args
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
    elseif args == "/new_prompt" then
      Prompts.open_prompt { content = "" } -- Open a blank Prompt window
      vim.cmd "startinsert" -- Go to insert mode
      return
    elseif args == "/chat_picker" then
      Chats.chat_picker()
      return
    elseif args == "/turn_picker" then
      Chats.turns_picker(State.chats)
      return
    elseif args == "/prompt_template_picker" then
      Prompts.load_user_templates()
      Prompts.prompt_template_picker()
      return
    elseif args == "/system_template_picker" then
      Prompts.load_system_templates()
      Prompts.system_template_picker()
      return
    elseif args == "/model_picker" then
      Providers.select_model()
      return
    elseif args == "/provider_picker" then
      Providers.select_provider(State.provider, function(provider_name)
        Providers.select_model(provider_name)
      end)
      return
    elseif args == "/recent_models" then
      Providers.select_recent_model()
      return
    elseif args == "/abort" then
      if curl.is_active_job() then
        State.chat_window:close() -- Closing the Chat window aborts running command
      end
      return
    elseif args:match "^/delete_old_chats$" or args:match "^/delete_old_chats%s" then
      local number_retained = Config.chats_retained
      local cmd_arg = arg.args:match "^/delete_old_chats%s+(.+)"
      if cmd_arg then
        number_retained = tonumber(cmd_arg)
      else
        number_retained =
          tonumber(vim.fn.input("Enter the number of chats to retain (older chats will be deleted): ", Config.chats_retained))
      end
      if not number_retained or number_retained < 0 then
        utils.notify("Invalid number of chats to retain", vim.log.levels.WARN)
        return
      end
      local current_count = #State.chats
      local to_delete = math.max(0, current_count - number_retained)
      if to_delete == 0 then
        utils.notify("No old chats to delete", vim.log.levels.INFO)
        return
      end
      if not utils.confirm("About to delete " .. to_delete .. " chat(s). Continue?") then
        return
      end
      Chats.delete_old_chats(number_retained)
      return
    elseif args == "/toggle_chat_location" then
      local win = State.chat_window
      win.location = win.location == Config.chat_window_location and Config.chat_window_alt_location or Config.chat_window_location
      utils.notify("Window location set to: " .. win.location, vim.log.levels.INFO)
      if win:is_open() then
        win:close()
        win:open()
      end
      return
    elseif args == "/help" then
      local help_message = [[-- Qanda Commands --

:Qanda                        -- Print this help message
:Qanda /readme                -- Open README file
:Qanda /<command>             -- Execute a builtin command e.g. :Qanda /prompt_window
:Qanda !<template>            -- Execute a prompt template e.g. :Qanda !Query
:Qanda ?<prompt>              -- Execute a user prompt     e.g. :Qanda ?Calculate forty plus two

Press <Tab> for command completion e.g. :Qanda /<Tab> to list builtin commands.
]]
      vim.notify(help_message, vim.log.levels.INFO)
      return
    elseif args == "/readme" then
      local qanda_root = utils.plugin_root()
      if not qanda_root then
        vim.notify("Could not find Qanda root directory", vim.log.levels.ERROR)
        return
      end
      local readme_path = qanda_root .. "/README.md"
      if vim.fn.filereadable(readme_path) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(readme_path))
      else
        vim.notify("Qanda README file not found: " .. readme_path, vim.log.levels.WARN)
      end
      return
    elseif args == "/status" then
      local info = "\nprovider: " .. vim.inspect(State.provider.name) .. "\nmodel: " .. vim.inspect(State.provider.model) .. "\nchat: "
      local chat = State.chat_window.chat
      if chat and #chat.turns > 0 then
        info = info .. '"' .. utils.sanitize_display_entry(Chats.chat_name(chat), 60) .. '"'
      else
        info = info .. "nil"
      end
      info = info .. "\ndata directory: " .. vim.inspect(Config.data_dir)
      info = info .. "\nchats directory: " .. vim.inspect(Config.chats_dir)
      info = info .. "\nprompts directory: " .. vim.inspect(Config.prompts_dir)
      info = info .. "\nsession file: " .. vim.inspect(Config.session_file())
      info = info .. "\ndiagnostics: " .. (diagnostics.enabled and "enabled" or "disabled")
      info = info .. "\ndiagnostics file: " .. vim.inspect(diagnostics.diagnostics_file())
      utils.notify(info, vim.log.levels.INFO)
      return
    elseif args == "/diagnostics_enable" then
      diagnostics.enabled = true
      utils.notify("Diagnostics enabled", vim.log.levels.INFO)
      return
    elseif args == "/diagnostics_disable" then
      diagnostics.enabled = false
      utils.notify("Diagnostics disabled", vim.log.levels.INFO)
      return
    elseif args == "/diagnostics_view" then
      diagnostics.view()
      return
    elseif args:sub(1, 1) == "!" then -- Template command
      local prompt_name = args:sub(2)
      if not utils.nil_or_blank(prompt_name) then
        local opts = {}
        prompt_name = Prompts.extract_new_turn_mode(prompt_name, opts)
        local prompt = Prompts.get_prompt(Prompts.user_prompts, prompt_name)
        if prompt then
          M.execute_prompt(prompt, opts)
        else
          utils.notify("Missing prompt template: " .. prompt_name, vim.log.levels.ERROR)
        end
      else
        utils.notify("Missing template name", vim.log.levels.ERROR)
      end
    elseif args:sub(1, 1) == "?" then -- Prompt command
      local prompt_text = args:sub(2)
      if not utils.nil_or_blank(prompt_text) then
        local opts = {}
        prompt_text = Prompts.extract_new_turn_mode(prompt_text, opts)
        local prompt = { model_options = {}, content = prompt_text }
        M.execute_prompt(prompt, opts)
      else
        utils.notify("Missing prompt", vim.log.levels.ERROR)
      end
    elseif args:sub(1, 1) == "/" then
      utils.notify("Invalid command: " .. args, vim.log.levels.ERROR)
    else
      vim.notify("Invalid command, run ':Quanda /help'", vim.log.levels.INFO)
    end
  end, {
    range = true,
    nargs = "?",
    complete = function(ArgLead)
      local args = {}
      for _, p in ipairs(Prompts.user_prompts) do
        table.insert(args, "!" .. p.name)
      end

      table.insert(args, "/new_chat")
      table.insert(args, "/chat_window")
      table.insert(args, "/chat_picker")
      table.insert(args, "/turn_picker")
      table.insert(args, "/prompt_window")
      table.insert(args, "/new_prompt")
      table.insert(args, "/prompt_template_picker")
      table.insert(args, "/model_picker")
      table.insert(args, "/provider_picker")
      table.insert(args, "/recent_models")
      table.insert(args, "/abort")
      table.insert(args, "/delete_old_chats")
      table.insert(args, "/toggle_chat_location")
      table.insert(args, "/system_template_picker")
      table.insert(args, "/status")
      table.insert(args, "/diagnostics_enable")
      table.insert(args, "/diagnostics_disable")
      table.insert(args, "/diagnostics_view")
      table.insert(args, "/repeat")
      table.insert(args, "/help")
      table.insert(args, "/readme")

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
--- @param opts { turn_mode?: TurnExecutionMode }? Options.
function M.execute_prompt(prompt, opts)
  coroutine.wrap(function()

    opts = opts or {}
    opts.turn_mode = opts.turn_mode or "append"

    -- If the prompt is a prompt template then expand it and convert it to an anonymous prompt
    if prompt.name then
      prompt = vim.tbl_deep_extend("force", {}, prompt)
      local expanded = Prompts.substitute_placeholders(prompt.content)
      if not expanded then
        return
      end
      prompt.name = nil
      prompt.content = expanded
      -- If the prompt contains a cursor placeholder open it in the Prompt window
      if prompt.content:find(Prompts.CURSOR_TAG) ~= nil then
        vim.schedule(function()
          Prompts.open_prompt(prompt)
        end)
        return
      end
    end

    State.prompt_window:close()

    if not prompt.content then
      return
    end

    local turn_mode = opts.turn_mode
    if prompt.content:find(Prompts.NEW_CHAT_TAG) ~= nil then
      turn_mode = "new"
    elseif prompt.content:find(Prompts.REPLACE_TURN_TAG) ~= nil then
      turn_mode = "replace"
    end
    prompt.content = prompt.content:gsub(Prompts.NEW_CHAT_TAG, "")
    prompt.content = prompt.content:gsub(Prompts.REPLACE_TURN_TAG, "")

    if turn_mode == "new" then
      Chats.new_chat()
    end

    local chat = State.chat_window.chat
    assert(chat)
    local turns = chat.turns ---@type Turn[]
    local prev_turn ---@type Turn?
    if turn_mode == "replace" then
      if #turns == 0 then
        utils.notify("Empty chat, there is no turn to replace", vim.log.levels.ERROR)
        return
      end
      prev_turn = table.remove(turns)
      State.chat_window.turn = nil
    end

    local turn = {
      request = prompt.content,
      provider = prompt.provider or State.provider.name,
      model = prompt.model or State.provider.model,
    }
    if prompt.model_options then
      turn.model_options = utils.shallow_clone_table(prompt.model_options)
    else
      turn.model_options = {}
    end

    -- Delete the most recent chat turn if did not complete.
    if #turns > 0 and not turns[#turns].response then
      table.remove(turns)
    end

    -- Set the system message if we're executing the first chat turn
    if #turns == 0 then
      local template, err = Prompts.has_system_prompt(prompt)
      if err then
        return
      end
      if template ~= nil then
        -- Use the system message template specified in the prompt `system` property
        local expanded = Prompts.substitute_placeholders(template.content)
        if not expanded then
          return
        end
        turn.system = expanded
      elseif State.system_message then
        turn.system = State.system_message.content
      end
    end

    -- Don't pass the prompt template system property to the turn because it's not a model option and its been processed
    turn.model_options.system = nil

    -- Append the new turn to current chat.
    table.insert(turns, turn)

    -- Create the model Request object
    local request_data = {
      model = turn.model,
      model_options = turn.model_option,
    }

    -- Merge configuration model options (lowest priority)
    Providers.merge_config_model_options(turn.provider, turn.model, request_data)

    -- Merge system message model options
    local model_options = State.system_message and State.system_message.model_options
    if model_options then
      for k, v in pairs(model_options) do
        request_data[k] = v
      end
    end

    -- Merge user prompt model options (highest priority)
    if turn.model_options then
      for k, v in pairs(turn.model_options) do
        request_data[k] = v
      end
    end

    -- Ensure numeric string values are converted to numbers
    utils.normalize_numerics(request_data)

    local messages = {}

    -- Add the system message
    local system_message = turns[1].system
    if system_message then
      table.insert(messages, { role = "system", content = system_message })
    end

    -- Add user and assistant messages
    for _, t in ipairs(turns) do
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

    -- Clear the Chat window and write the header.
    Chats.open_chat(chat, turn)

    -- Execute the curl command streaming the output to the Chat window.
    local curl_args = State.provider.module.command(request)
    local json_request = vim.json.encode(request.data)
    curl.execute_command(
      curl_args,
      json_request,
      State.provider.module.data_normaliser,
      State.provider.module.set_turn_stats,
      State.chat_window.winid,
      function(curl_response) ---@type CurlResponse
        if diagnostics.enabled then
          vim.schedule(function() -- Fast event context
            -- Write diagnostics file
            diagnostics.write_to_file(curl_args, json_request, curl_response)
          end)
        end

        if curl.get_job_status() ~= "stopped" then
          -- Turn did not complete (error, aborted, running)
          if turn_mode == "replace" then
            table.insert(chat.turns, prev_turn)
            State.chat_window.turn = prev_turn
          end
          return
        end

        -- Update completed turn
        turns[#turns].response = table.concat(curl_response.response_lines, "\n")
        turns[#turns].timestamp = tostring(os.date(Config.TIME_STAMP_FORMAT))
        turns[#turns].duration = curl_response.duration
        turns[#turns].request_tokens = curl_response.request_tokens
        turns[#turns].response_tokens = curl_response.response_tokens
        turns[#turns].total_tokens = curl_response.total_tokens
        if curl_response.model then
          turns[#turns].model = curl_response.model
        end

        vim.schedule(function() -- Fast event context
          Chats.save_chat(chat)
          if not vim.tbl_contains(State.chats, chat) then
            table.insert(State.chats, chat)
          end
        end)

      end
    )

  end)()
end

return M
