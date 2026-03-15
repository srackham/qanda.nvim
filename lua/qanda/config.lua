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

  cancel_key = "<C-c>",
  delete_key = "<C-d>",
  edit_key = "<C-e>", -- Chat picker, Prompt picker TODO: finish these comments
  exec_key = "<C-Space>",
  help_key = "<C-h>",
  next_key = "<Down>",
  prev_key = "<Up>",
  quit_key = "q",
  redo_key = "<C-r>",
  save_key = "<C-s>",
  switch_key = "<Tab>",

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
