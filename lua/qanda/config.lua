local M = {} -- This module

-- Constants --
M.CHAT_BUFFER_NAME = "[qanda.chat]"
M.PROMPT_BUFFER_NAME = "[qanda.prompt]"
M.TIME_STAMP_FORMAT = "%Y-%m-%d %H:%M:%S"
M.SAVED_STATE_FILE = "QANDA_SAVED_STATE.json"

local default = {

  -- User configuration --
  debug = true,

  provider = nil,
  model = nil,
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

  chat_reload = false, -- Reload the most recent chat at startup

  help_key = "<C-h>",

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
  prompt_clear_key = "<C-Space>",
  prompt_close_key = "q",
  prompt_exec_key = "<Enter>",
  prompt_exec_new_key = "<S-Enter>",
  prompt_switch_key = "<Tab>",
  prompt_inject_key = "<Leader>fi",

  -- Prompt template picker key commands --
  user_picker_open_key = "<Enter>",
  user_picker_exec_key = "<S-Enter>",
  user_picker_delete_key = "<C-d>",
  user_picker_edit_key = "<C-e>",

  -- System prompt picker key commands --
  system_picker_edit_key = "<C-e>",
  system_picker_select_key = "<Enter>",
  system_picker_disable_key = "<C-d>",

  -- Miscellaneous --
  data_dir = vim.fn.stdpath "data" .. "/qanda_nvim",
  system_prompt_name = nil, -- Default system prompt name
  user_prompt_lines = 10, -- The maximum number of user prompt lines to display in the Chat window
  system_prompt_lines = 10, -- The maximum number of system prompt lines to display in the Chat window
  user_prompt_register = "u", -- The most recent submitted user prompt
  system_prompt_register = "s", -- The most recent submitted user prompt
  response_register = "r", -- The most recent response (extracted)
  curl_command_register = "c", -- The curl model request shell command
  confirm_chat_file_deletion = true,

  -- Window layouts --
  chat_window_mode = "right",
  chat_picker_layout = { width = 0.9, height = 0.6, preview_width = 0.65 },
  turn_picker_layout = { width = 0.9, height = 0.7 },
  prompt_picker_layout = { width = 0.8, height = 0.5 },
  prompt_window_layout = { border = "rounded", height = 0.5 },
  model_picker_layout = { width = 0.3, height = 0.6 },
}

function M.setup(opts)

  opts = opts or {}
  for k, v in pairs(default) do
    M[k] = v
  end

  for k, v in pairs(opts) do
    if k == "model_options" then
      M[k] = vim.tbl_deep_extend("force", M[k] or {}, v) -- Merge setup model_options rather than replace
    else
      M[k] = v
    end
  end

  -- Expand all configuration paths
  for _, k in ipairs { "data_dir" } do
    if M[k] then
      M[k] = vim.fn.expand(M[k])
    end
  end

  local state = require "qanda.state"
  state.prompt_window.float_layout = M.prompt_window_layout
  state.chat_window.mode = M.chat_window_mode
  state.restore_state()

end

return M
