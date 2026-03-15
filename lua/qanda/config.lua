local M = {} -- This module

-- Constants
M.CHAT_BUFFER_NAME = "[qanda.chat]"
M.PROMPT_BUFFER_NAME = "[qanda.prompt]"
M.TIME_STAMP_FORMAT = "%Y-%m-%d %H:%M:%S"

local default = {

  -- User configuration
  debug = true,

  provider = "ollama",
  model = "mistral",
  host = "localhost",
  port = "11434",

  help_key = "<C-h>",

  -- Chat window key commands
  chat_abort_key = "<Esc>",
  chat_close_key = "q",
  chat_edit_key = "<C-e>",
  chat_exec_key = "<Enter>",
  chat_next_key = "<Down>",
  chat_prev_key = "<Up>",
  chat_redo_key = "<C-r>",
  chat_switch_key = "<Tab>",

  -- Chat picker key commands
  chat_picker_delete_key = "<C-d>",
  chat_picker_edit_key = "<C-e>",
  chat_picker_exec_key = "<C-Space>",
  chat_picker_open_key = "<Enter>",

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

  ---@type UIMode
  ui_mode = "separate",

  prompts_dir = vim.fn.stdpath "data" .. "/qanda_nvim/prompts",
  chats_dir = vim.fn.stdpath "data" .. "/qanda_nvim/chats",
  system_prompt_name = nil, -- Default system prompt name

  response_register = "r", -- Holds the most recent response (extracted)
  prompt_register = "p", -- Holds the most recent submitted prompt (mandatory, cannot be nil)

  separate_prompt_window_layout = { width = 0.8, height = 0.5, border = "single" },
  linked_window_layout = { width = 0.8, height = 0.7, prompt_height = 0.3, border = "single" },
  prompt_picker_layout = { width = 0.8, height = 0.5 },
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
end

return M
