local M = {} -- This module

-- Constants
M.CHAT_BUFFER_NAME = "[qanda.chat]"
M.PROMPT_BUFFER_NAME = "[qanda.prompt]"
M.TIME_STAMP_FORMAT = "%Y-%m-%d %H:%M:%S"
M.MOST_RECENT_CHAT = "MOST_RECENT_CHAT" -- File name of file containing most recent chat file

local default = {

  -- User configuration
  debug = true,

  provider = "ollama",
  model = "mistral",
  host = "localhost",
  port = "11434",

  chat_reload = true,

  help_key = "<C-h>",

  -- Chat window key commands
  chat_abort_key = "<Esc>",
  chat_close_key = "q",
  chat_edit_key = "<C-e>",
  chat_exec_key = "<Enter>",
  chat_delete_key = "<C-d>",
  chat_next_key = "<PageDown>",
  chat_prev_key = "<PageUp>",
  chat_redo_key = "<C-r>",
  chat_switch_key = "<Tab>",

  -- Chat picker key commands
  chat_picker_delete_key = "<C-d>",
  chat_picker_rename_key = "<C-s>",
  chat_picker_edit_key = "<C-e>",
  chat_picker_exec_key = "<C-Space>",
  chat_picker_open_key = "<Enter>",

  -- Turn picker key commands
  turn_picker_open_key = "<Enter>",

  -- Prompt window key commands
  prompt_abort_key = "<Esc>",
  prompt_clear_key = "<C-Space>",
  prompt_close_key = "q",
  prompt_exec_key = "<Enter>",
  prompt_switch_key = "<Tab>",

  -- Prompt picker key commands
  user_picker_delete_key = "<C-d>",
  user_picker_edit_key = "<C-e>",
  user_picker_exec_key = "<Enter>",
  user_picker_open_key = "<C-Space>",

  -- System prompt picker key commands
  system_picker_edit_key = "<C-e>",
  system_picker_select_key = "<Enter>",
  system_picker_deselect_key = "<C-d>",

  prompts_dir = vim.fn.stdpath "data" .. "/qanda_nvim/prompts",
  chats_dir = vim.fn.stdpath "data" .. "/qanda_nvim/chats",
  -- system_prompt_name = nil, -- Default system prompt name
  system_prompt_name = "Generic", -- Default system prompt name

  response_register = "r", -- Holds the most recent response (extracted)
  prompt_register = "p", -- Holds the most recent submitted prompt (mandatory, cannot be nil)

  -- Window layouts
  chat_window_mode = "right",
  chat_picker_layout = { width = 0.5, height = 0.6 },
  turn_picker_layout = { width = 0.9, height = 0.7 },
  prompt_picker_layout = { width = 0.8, height = 0.5 },
  prompt_window_layout = { border = "rounded", height = 0.5 },

  model_options = { ollama = { think = false, stream = true } },
}

function M.setup(opts)

  opts = opts or {}
  for k, v in pairs(default) do
    M[k] = v
  end

  for k, v in pairs(opts) do
    M[k] = v
  end

  local state = require "qanda.state"
  state.prompt_window.float_layout = M.prompt_window_layout
  state.chat_window.mode = M.chat_window_mode

end

return M
