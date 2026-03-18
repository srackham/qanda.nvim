local Config = require "qanda.config" -- User configuration options
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
    mode = nil,
    chat = nil,
    turn_index = nil, -- 1-based index of the turn in the chat window
  },

  prompt_window = ui.UIWindow.new {
    buf_name = Config.PROMPT_BUFFER_NAME,
    modifiable = true,
    mode = "float",
    float_layout = nil,
  },
}

return M
