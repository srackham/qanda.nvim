local Config = require "qanda.config" -- User configuration options
local ui = require "qanda.ui"
local utils = require "qanda.utils"

local M = {

  provider = nil, ---@type Provider
  system_message = nil, ---@type Prompt System message with placeholders expanded
  chats = {}, ---@type Chats
  saved_state = {},

  chat_window = ui.UIWindow.new {
    buf_name = Config.CHAT_BUFFER_NAME,
    modifiable = false,
    mode = nil,
    chat = nil,
    current_turn = nil,
  },

  prompt_window = ui.UIWindow.new {
    buf_name = Config.PROMPT_BUFFER_NAME,
    modifiable = true,
    mode = "float",
    float_layout = nil,
  },
}

---Saves the saved state JSON file.
function M.save_state()
  local dir = Config.get_data_dir()
  vim.fn.mkdir(dir, "p") -- ensure directory exists
  local path = dir .. "/" .. Config.SESSION_FILE
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

---Restores the saved state JSON file.
---@return SaveState|nil
function M.restore_state()
  local path = Config.get_data_dir() .. "/" .. Config.SESSION_FILE

  -- If file doesn't exist, it's not an error; just return nil
  if not utils.file_exists(path) then
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
    utils.notify("Failed to decode state file: " .. path, vim.log.levels.ERROR)
    return nil
  end

  if decoded.chat_file and not utils.file_exists(decoded.chat_file) then
    decoded.chat_file = nil
  end

  M.saved_state = decoded

end

return M
