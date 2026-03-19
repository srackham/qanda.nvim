local Config = require "qanda.config" -- User configuration options
local ui = require "qanda.ui"
local utils = require "qanda.utils"

local M = {
  system_prompt = nil, ---@type Prompt System prompt with placeholders expanded
  chats = {}, ---@type Chats
  saved_state = {},

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

---Saves the state to STATE.json in the specified directory
function M.save_state()
  local dir = Config.data_dir
  vim.fn.mkdir(dir, "p") -- ensure directory exists
  local path = dir .. "/" .. Config.SAVED_STATE_FILE
  local ok, encoded = pcall(vim.fn.json_encode, M.saved_state)

  if not ok then
    utils.notify("Failed to encode state to JSON: " .. tostring(encoded), vim.log.levels.ERROR)
    return
  end

  local f = io.open(path, "w")
  if not f then
    utils.notify("Failed to open state file for writing: " .. path, vim.log.levels.ERROR)
    return
  end

  f:write(encoded)
  f:close()
end

---Restores the state from STATE.json in the specified directory
---@return SaveState|nil
function M.restore_state()
  local path = Config.data_dir .. "/" .. Config.SAVED_STATE_FILE

  -- If file doesn't exist, it's not an error; just return nil
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local f = io.open(path, "r")
  if not f then
    -- If readable check passed but open failed, something went wrong
    utils.notify("Failed to read state file: " .. path, vim.log.levels.ERROR)
    return nil
  end

  local content = f:read "*a"
  f:close()

  local ok, decoded = pcall(vim.fn.json_decode, content)
  if not ok then
    utils.notify("Failed to decode STATE.json: " .. tostring(decoded), vim.log.levels.ERROR)
    return nil
  end

  M.saved_state = decoded

end

return M
