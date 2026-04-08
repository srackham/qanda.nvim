local Config = require "qanda.config"
local ui = require "qanda.ui"
local utils = require "qanda.utils"

local M = {

  provider = nil, ---@type Provider
  system_message = nil, ---@type Prompt System message with placeholders expanded
  chats = {}, ---@type Chats
  saved_state = nil, ---@type SavedState
  recent_models = nil, ---@type Model[]

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
  -- Assemble the saved state object
  -- TODO: do we need the M.saved_state global?
  if M.provider then
    M.saved_state.model = M.provider.model
    M.saved_state.provider = M.provider.name
  end
  if M.recent_models then
    M.saved_state.recent_models = M.recent_models
  end

  local dir = Config.data_dir
  vim.fn.mkdir(dir, "p") -- ensure directory exists
  local ok, encoded = pcall(vim.fn.json_encode, M.saved_state)

  if not ok then
    utils.notify("Failed to encode state to JSON: " .. tostring(encoded), vim.log.levels.ERROR)
    return
  end

  local path = Config.session_file()
  local f = io.open(path, "w")
  if not f then
    utils.notify("Failed to open state file for writing: " .. path, vim.log.levels.ERROR)
    return
  end

  f:write(encoded)
  f:close()
end

---Restores the saved state JSON file.
---If an error occurs an error message is printed and a blank saved state is restored.
function M.restore_state()
  local path = Config.session_file()

  -- Blank saved state
  M.saved_state = { recent_models = {} }
  M.recent_models = {}

  -- If file doesn't exist, it's not an error (the user may be onboarding)
  if not utils.file_exists(path) then
    return
  end

  local f = io.open(path, "r")
  if not f then
    -- If readable check passed but open failed, something went wrong
    utils.notify("Failed to read state file: " .. path, vim.log.levels.ERROR)
    return
  end

  local content = f:read "*a"
  f:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    utils.notify("Failed to decode state file: " .. path, vim.log.levels.ERROR)
    return
  end

  if decoded.chat_file and not utils.file_exists(decoded.chat_file) then
    decoded.chat_file = nil
  end

  M.saved_state = decoded
  if decoded.recent_models then
    M.recent_models = decoded.recent_models
  else
    M.recent_models = {}
  end

end

return M
