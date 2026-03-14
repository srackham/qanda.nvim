local Config = require "qanda.config" -- User configuration options
local utils = require "qanda.utils"
local ui = require "qanda.ui"

---@class State
---@field provider Provider
---@field chats Chats
---@field chat_window UIWindow
---@field prompt_window UIWindow
---@field system_prompt Prompt The current system prompt object

local M = {
  system_prompt = nil, ---@type Prompt System prompt with placeholders expanded
  chats = {}, ---@type Chats

  chat_window = ui.UIWindow.new {
    buf_name = Config.CHAT_BUFFER_NAME,
    modifiable = false,
    mode = "right",
    chat = { turns = {} },
    turn_index = nil, -- 1-based index of the turn in the chat window
  },

  prompt_window = ui.UIWindow.new {
    buf_name = Config.PROMPT_BUFFER_NAME,
    modifiable = true,
    mode = "float",
    float_layout = {
      border = "rounded",
      height = 0.5,
    },
  },
}

---Initialise state from configuration.
function M.setup()

  -- Set model provider
  local provider = require("qanda.providers").get_provider(Config.provider)
  if provider then
    local models = provider.module.models(Config)
    if utils.table_contains(models, Config.model) then
      provider.model = Config.model
      M.provider = provider
    else
      utils.notify("Unable to  find model '" .. Config.model .. "' for provider '" .. Config.provider.name .. "'.", vim.log.levels.ERROR)
    end
  end

  M.system_prompt = nil

end

return M
