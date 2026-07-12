local M = {} -- This module

-- Constants --
M.CHAT_BUFFER_NAME = "[qanda.chat]"
M.PROMPT_BUFFER_NAME = "[qanda.prompt]"
M.TIME_STAMP_FORMAT = "%Y-%m-%d %H:%M:%S"
M.SESSION_FILE = "session.json"
M.ROOT_DIR = vim.fn.getcwd() -- Lock the root directory to the Neovim's startup working directory.

-- Default configuration options --
local default = {

  debug = false,

  -- Default onboarding provider and model names (if `nil` you will be prompted)
  provider = nil,
  model = nil,

  -- Ollama server
  host = "localhost",
  port = "11434",

  -- Model specific options
  -- Model names are formatted like `<provider>/<model>`.
  model_options = {
    -- ["ollama/minimax-m2.5:cloud"] = { think = true, temperature = 0.7 },
  },

  -- Provider specific options
  -- All options except `api_key` are passed through as AI model request options.
  provider_options = {
    ollama = { think = false, stream = true },
    openrouter = { api_key = "$OPENROUTER_API_KEY", stream = true, stream_options = { include_usage = true } },
    gemini = { api_key = "$GEMINI_API_KEY", stream = true, stream_options = { include_usage = true } },
  },

  -- Global configuration data files root directory
  data_dir = vim.fn.stdpath "data" .. "/qanda_nvim",

  -- Miscellaneous --
  user_prompt_lines = 10, -- The maximum number of user prompt lines to display in the Chat window
  system_message_lines = 5, -- The maximum number of system message lines to display in the Chat window

  diagnostics_register = "u", -- Diagnostics written to this register

  confirm_chat_file_deletion = true,

  -- Pickers, Chat and Prompt windows help key --
  help_key = "<C-h>", -- Display a list of picker commands

  -- Chat window key commands --
  chat_abort_key = "<C-k>",
  chat_close_key = "<Esc>",
  chat_copy_key = "<C-c>",
  chat_edit_key = "<C-e>",
  chat_prompt_key = "<C-x>",
  chat_switch_key = "<S-Tab>",
  chat_new_prompt_key = "<C-Del>",
  chat_delete_key = "<C-d>",
  chat_next_key = "<C-n>",
  chat_prev_key = "<C-p>",
  chat_redo_key = "<C-r>",
  chat_truncate_key = "<C-z>",

  -- Chat picker key commands --
  chat_picker_delete_key = "<C-d>",
  chat_picker_rename_key = "<C-l>",
  chat_picker_edit_key = "<C-e>",
  chat_picker_open_key = "<Enter>",

  -- Turn picker key commands --
  turn_picker_open_key = "<Enter>",
  turn_picker_delete_key = "<C-d>",
  turn_truncate_key = "<C-z>",
  turn_prompt_key = "<C-x>",

  -- Prompt window key commands --
  prompt_abort_key = "<C-k>",
  prompt_close_key = "<Esc>",
  prompt_submit_key = "<C-s>",
  prompt_new_chat_key = "<C-n>",
  prompt_redo_key = "<C-r>",
  prompt_new_key = "<C-Del>",
  prompt_switch_key = "<S-Tab>",
  prompt_inject_key = "<Leader>fi",

  -- Prompt template picker key commands --
  prompt_picker_open_key = "<Enter>",
  prompt_picker_exec_key = "<C-x>",
  prompt_picker_delete_key = "<C-d>",
  prompt_picker_edit_key = "<C-e>",

  -- System template picker key commands --
  system_picker_edit_key = "<C-e>",
  system_picker_select_key = "<Enter>",
  system_picker_disable_key = "<C-d>",

  -- Window layouts --
  chat_window_mode = "float", ---@type WindowMode
  chat_picker_layout = { width = 0.9, height = 0.6, preview_width = 0.65 },
  turn_picker_layout = { width = 0.9, height = 0.7 },
  template_picker_layout = { width = 0.8, height = 0.5 }, -- Prompt and System template pickers layout
  prompt_window_layout = { border = "rounded", height = 0.5 },
  model_picker_layout = { width = 0.4, height = 0.6 },
  recent_models_layout = { width = 0.5, height = 0.6 },
}

function M.setup(opts)

  for k, v in pairs(default) do
    M[k] = v
  end

  opts = opts or {}
  for k, v in pairs(opts) do
    if k == "provider_options" then
      M[k] = vim.tbl_deep_extend("force", M[k] or {}, v) -- Merge setup model_options rather than replace
    else
      M[k] = v
    end
  end

  -- Set configuration file locations
  M.data_dir = vim.fn.expand(M.data_dir)
  M.prompts_dir = M.data_dir .. "/templates"
  M.chats_dir = M.data_dir .. "/chats"

  local project_data_dir = M.ROOT_DIR .. "/.qanda_nvim"
  local dir = project_data_dir .. "/chats"
  if vim.fn.isdirectory(dir) == 1 then
    M.chats_dir = dir
  else
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
