local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state" -- Application state
local Chats = require "qanda.chats"
local Prompts = require "qanda.prompts"
local Providers = require "qanda.providers" -- LLM providers
local utils = require "qanda.utils"

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
      Chats.open_chat()
      return
    elseif args == "/new" then
      M.new_chat()
      return
    elseif args == "/prompt" then
      Prompts.open_prompt()
      return
    elseif args == "/chats" then
      ---@todo
      return
    elseif args == "/prompts" then
      Prompts.user_prompts = Prompts.load_prompts "user"
      Prompts.user_prompt_picker(function(prompt)
        M.execute_prompt_string(prompt.prompt)
      end)
      return
    elseif args == "/system" then
      coroutine.wrap(function()
        Prompts.system_prompts = Prompts.load_prompts "system"
        Prompts.system_prompt_picker(function(prompt)
          prompt = vim.tbl_deep_extend("force", {}, prompt)
          prompt.prompt = Prompts.substitute_placeholders(prompt.prompt)
          prompt.consumed = false
          State.system_prompt = prompt
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
      -- TODO: Synthesise a Prompt and execute it
      M.execute_prompt_string(prompt.prompt)
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

-- TODO: We need to execute a Prompt not a string.
function M.execute_prompt_string(prompt_string)
  coroutine.wrap(function()
    prompt_string = Prompts.substitute_placeholders(prompt_string)
    if not prompt_string then
      return
    end
    State.prompt_window:close()
    Chats.open_chat()
    local lines = vim.split(prompt_string, "\n")
    State.chat_window:set_lines(lines)
  end)()
end

return M
