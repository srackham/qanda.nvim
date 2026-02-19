local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {
  chats = {}, ---@type Chats
}

function M.setup()
  -- Currently no setup required
end

---Open chat window, load the chat.
---If the chat window does not exist, create it and attach key-mapped commands.
---If the `chat` is `nil` then don't load the chat text into the window.
---@param chat Chat?
function M.open_chat(chat)
  local win = State.chat_window
  win:open()
  if chat then
    local lines = M.chat_lines(chat)
    win:set_lines(lines)
  end
end

return M
