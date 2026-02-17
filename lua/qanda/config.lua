local M = {} -- This module

-- Constants
M.CHAT_BUFFER_NAME = "[qanda.chat]"
M.PROMPT_BUFFER_NAME = "[qanda.prompt]"

local default = {

  -- User configuration
  provider = "ollama",
  model = "mistral",
  host = "localhost",
  port = "11434",

  quit_key = "q",
  cancel_key = "<C-c>",
  edit_key = "<C-e>",
  exec_key = "<C-Space>",
  save_key = "<C-s>",
  switch_key = "<Tab>",

  ---@type UIMode
  ui_mode = "separate",

  prompts_dir = vim.fn.stdpath "data" .. "/qanda_nvim/prompts",

  response_register = nil, -- Holds the most recent response
  prompt_register = "p", -- Holds the most recent submitted prompt (mandatory, cannot be nil)

  separate_prompt_window_layout = { width = 0.8, height = 0.5, border = "single" },
  linked_window_layout = { width = 0.8, height = 0.7, prompt_height = 0.3, border = "single" },
  prompt_picker_layout = { width = 0.8, height = 0.5 },
  model_options = { ollama = { think = false } },
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
