local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state" -- Application state
local Chats = require "qanda.chats"
local Prompts = require "qanda.prompts"
local Providers = require "qanda.providers" -- LLM providers
local utils = require "qanda.utils"
local debug = require "qanda.debug"
local curl = require "qanda.curl"

local M = {} -- This module

-- Expose internals
M.Config = Config
M.State = State
M.Prompts = Prompts
M.Providers = Providers

function M.setup(opts)
  Config.setup(opts)
  Providers.setup()
  Chats.setup()
  Prompts.setup()
  State.setup()
  M.create_user_command()
end

local function select_model()
  local items = State.provider.module.models(Config)
  for i, v in ipairs(items) do
    if v == State.provider.model then -- Highlight current model
      items[i] = "* " .. v
    else
      items[i] = "  " .. v
    end
  end
  vim.ui.select(items, { prompt = State.provider.name .. " models" }, function(item)
    if item then
      item = string.sub(item, 3)
      utils.notify("Model set to '" .. item .. "'.", vim.log.levels.INFO)
      State.provider.model = item
    end
  end)
end

local function select_provider()
  Providers.select_provider(State.provider, function(item)
    State.provider = Providers.get_provider(item)
    select_model()
  end)
end

function M.open_qanda()
  ---@todo
  utils.create_window(Config.CHAT_BUFFER_NAME, { window_mode = "right" })
end

function M.new_qanda()
  ---@todo
end

function M.create_user_command()
  vim.api.nvim_create_user_command("Qanda", function(arg)
    local args = arg.args
    if args == "" then
      args = "/prompts"
    end

    if args == "/chat" then
      State.prompt_window:close()
      if #State.chats == 0 then
        Chats.new_chat()
      else
        Chats.open_chat()
      end
      return
    elseif args == "/new" then
      Chats.new_chat()
      return
    elseif args == "/prompt" then
      Prompts.open_prompt(nil)
      return
    elseif args == "/chats" then
      State.chats = Chats.load_chats()
      Chats.chat_picker()
      return
    elseif args == "/prompts" then
      Prompts.load_user_prompts()
      Prompts.user_prompt_picker(function(prompt)
        M.execute_prompt(prompt)
      end)
      return
    elseif args == "/system" then
      coroutine.wrap(function()
        Prompts.load_system_prompts()
        Prompts.system_prompt_picker(function(prompt)
          prompt.expanded = Prompts.substitute_placeholders(prompt.prompt)
          prompt.consumed = false
          State.system_prompt = prompt
          debug.print(State.system_prompt)
        end)
      end)()
    elseif args == "/models" then
      select_model()
      return
    elseif args == "/providers" then
      select_provider()
      return
    elseif args == "/info" then
      utils.notify(
        "provider: "
          .. vim.inspect(State.provider.name)
          .. ", model: "
          .. vim.inspect(State.provider.model)
          .. ", system: "
          .. vim.inspect((State.system_prompt or {}).name),
        vim.log.levels.INFO
      )
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

      table.insert(args, "/new")
      table.insert(args, "/chat")
      table.insert(args, "/chats")
      table.insert(args, "/prompt")
      table.insert(args, "/prompts")
      table.insert(args, "/models")
      table.insert(args, "/providers")
      table.insert(args, "/system")
      table.insert(args, "/info")

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

function M.execute_prompt(prompt)
  coroutine.wrap(function()

    local chat = State.chat_window.chat
    local turns = chat.turns

    prompt.expanded = Prompts.substitute_placeholders(prompt.prompt)
    if prompt.expanded == nil then
      return
    end
    State.prompt_window:close()

    local turn = {
      request = prompt.expanded,
      provider = prompt.provider or State.provider.name,
      model = prompt.model or State.provider.model,
    }
    if prompt.model_options then
      turn.model_options = utils.shallow_clone_table(prompt.model_options)
    end

    -- Delete the most recent chat turn if did not complete.
    if #turns > 0 and not turns[#turns].response then
      table.remove(turns)
    end

    -- Append the new turn to current chat.
    table.insert(turns, turn)

    -- Create the model Request object
    local request_data = {
      provider = turn.provider,
      model = turn.model,
      model_options = turn.model_option,
    }
    -- Add configuration model options
    local model_options = Config.model_options[turn.provider]
    if model_options then
      for k, v in pairs(model_options) do
        request_data[k] = v
      end
    end
    -- Add prompt model options
    if turn.model_options then
      for k, v in pairs(turn.model_options) do
        request_data[k] = v
      end
    end
    -- Add model messages
    local messages = {}
    for _, t in ipairs(turns) do
      table.insert(messages, { role = "user", content = t.request })
      if t.response then
        table.insert(messages, { role = "assistant", content = t.response })
      end
    end
    request_data.messages = messages

    -- If the provider and/or the model is not the current default they need to be validated
    if not Providers.set_provider_and_model(request_data.provider, request_data.model) then
      return
    end

    -- Build the curl command
    local request = {
      host = Config.host,
      port = Config.port,
      data = request_data,
    }
    local curl_args = State.provider.module.command(request)

    -- debug.print(curl_args)
    debug.exec(function()
      vim.fn.setreg("+", utils.args_to_shell_command(curl_args)) -- Copy executable shell command to clipboard
    end)

    -- TODO: Clear the Chat window and write the header.
    Chats.open_chat(chat, #turns)

    -- Execute the curl command streaming the output to the Chat window.
    curl.execute_command(curl_args, State.chat_window.winid, function(model_response)
      if curl.job_status() ~= "stopped" then
        -- Turn did not complete
        debug.print(curl.job_status())
        return
      end

      -- Update completed turn
      turns[#turns].response = table.concat(model_response, "\n")
      turns[#turns].timestamp = os.date(Config.TIME_STAMP_FORMAT)

      -- Save chat file

      -- Clear Prompt window

    end)

  end)()
end

return M
