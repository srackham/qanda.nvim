local M = {} -- This module

-- Constants --
M.CHAT_BUFFER_NAME = "[qanda.chat]"
M.PROMPT_BUFFER_NAME = "[qanda.prompt]"
M.TIME_STAMP_FORMAT = "%Y-%m-%d %H:%M:%S"
M.SESSION_FILE = "session.json"

-- Default configuration options --
local default = {

  debug = true,

  -- Default onboarding provider and model names (if `nil` you will be prompted)
  provider = nil,
  model = nil,

  -- Ollama server
  host = "localhost",
  port = "11434",

  -- Options included in every model request
  model_options = {
    ollama = { think = false, stream = true },
    openrouter = { stream = true },
    gemini = { stream = true },
  },

  -- Provider specific options
  provider_options = {
    openrouter = { api_key = "$OPENROUTER_API_KEY" },
    gemini = { api_key = "$GEMINI_API_KEY" },
  },

  -- Global configuration data files root directory
  data_dir = vim.fn.stdpath "data" .. "/qanda_nvim",

  -- Miscellaneous --
  system_message_name = nil, -- Default system message template name
  user_prompt_lines = 10, -- The maximum number of user prompt lines to display in the Chat window
  system_message_lines = 5, -- The maximum number of system message lines to display in the Chat window
  system_message_register = "s", -- The most recent submitted system message
  request_register = "t", -- The most recent model request (JSON data)
  response_register = "r", -- The most recent response (extracted)
  curl_command_register = "c", -- The curl model request shell command
  confirm_chat_file_deletion = true,

  -- Pickers, Chat and Prompt windows help key --
  help_key = "<C-h>", -- Display a list of picker commands

  -- Chat window key commands --
  chat_abort_key = "<Esc>",
  chat_close_key = "q",
  chat_edit_key = "<C-e>",
  chat_prompt_key = "<Enter>",
  chat_delete_key = "<C-d>",
  chat_next_key = "<C-n>",
  chat_prev_key = "<C-p>",
  chat_redo_key = "<C-r>",
  chat_switch_key = "<Tab>",
  chat_truncate_key = "<C-z>",

  -- Chat picker key commands --
  chat_picker_delete_key = "<C-d>",
  chat_picker_rename_key = "<C-s>",
  chat_picker_edit_key = "<C-e>",
  chat_picker_open_key = "<Enter>",

  -- Turn picker key commands --
  turn_picker_open_key = "<Enter>",
  turn_picker_delete_key = "<C-d>",

  -- Prompt window key commands --
  prompt_abort_key = "<Esc>",
  prompt_close_key = "q",
  prompt_submit_key = "<S-Enter>",
  prompt_new_chat_key = "<C-s>",
  prompt_redo_key = "<C-r>",
  prompt_clear_key = "<C-Space>",
  prompt_switch_key = "<Tab>",
  prompt_inject_key = "<Leader>fi",

  -- Prompt template picker key commands --
  user_picker_open_key = "<Enter>",
  user_picker_exec_key = "<S-Enter>",
  user_picker_delete_key = "<C-d>",
  user_picker_edit_key = "<C-e>",

  -- System message picker key commands --
  system_picker_edit_key = "<C-e>",
  system_picker_select_key = "<Enter>",
  system_picker_disable_key = "<C-d>",

  -- Window layouts --
  -- chat_window_mode = "right",
  chat_window_mode = "float",
  chat_picker_layout = { width = 0.9, height = 0.6, preview_width = 0.65 },
  turn_picker_layout = { width = 0.9, height = 0.7 },
  prompt_picker_layout = { width = 0.8, height = 0.5 },
  prompt_window_layout = { border = "rounded", height = 0.5 },
  model_picker_layout = { width = 0.3, height = 0.6 },
  recent_models_layout = { width = 0.3, height = 0.6 },
}

function M.setup(opts)

  for k, v in pairs(default) do
    M[k] = v
  end

  opts = opts or {}
  for k, v in pairs(opts) do
    if k == "model_options" then
      M[k] = vim.tbl_deep_extend("force", M[k] or {}, v) -- Merge setup model_options rather than replace
    else
      M[k] = v
    end
  end

  -- Set configuration file locations
  local global_data_dir = vim.fn.expand(M.data_dir) -- Global data directory
  local local_data_dir = vim.fn.getcwd() .. "/.qanda_nvim" -- Local project directory

  if vim.fn.isdirectory(local_data_dir) == 1 then
    M.data_dir = local_data_dir
  else
    M.data_dir = global_data_dir
  end

  local dir = local_data_dir .. "/prompts"
  if vim.fn.isdirectory(dir) == 1 then
    M.prompts_dir = dir
  else
    M.prompts_dir = global_data_dir .. "/prompts"
  end

  dir = local_data_dir .. "/chats"
  if vim.fn.isdirectory(dir) == 1 then
    M.chats_dir = dir
  else
    M.chats_dir = global_data_dir .. "/chats"
  end

  -- Restore state
  local state = require "qanda.state"
  state.prompt_window.float_layout = M.prompt_window_layout
  state.chat_window.mode = M.chat_window_mode
  state.restore_state()

end

--- Return the session file path.
---@return string The absolute path to the session file
function M.session_file()
  return M.data_dir .. "/" .. M.SESSION_FILE
end

return M
