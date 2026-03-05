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
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  if chat then
    local lines = M.chat_lines(chat)
    win:set_lines(lines)
  end
  -- Attach key commands.
  vim.keymap.set("n", Config.quit_key, function()
    win:close()
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.switch_key, function()
    vim.cmd "Qanda /prompt"
  end, { buffer = win.bufnr })
end

function M.new_chat()
  -- TODO: should init to default system prompt if defined.
  State.system_prompt=nil
end

return M
