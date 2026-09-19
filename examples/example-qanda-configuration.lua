return {
  "srackham/qanda.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  enabled = true,
  config = function()

    local qanda = require "qanda"

    -- Override default options here --
    qanda.setup {
      user_prompt_lines = 5,
      system_message_lines = 5,
      provider_options = {
        ollama = { temperature = 0.4 },
      },
    }

    -- Key mappings for builtin commands --
    vim.keymap.set({ "n", "v" }, "<S-Tab>", "<Cmd>Qanda /chat_window<CR>", { desc = "Qanda.nvim user Chat window" })
    vim.keymap.set({ "n", "v", "i" }, "<C-Del>", "<Cmd>Qanda /new_prompt<CR>", { desc = "Qanda.nvim new prompt" })
    vim.keymap.set({ "n", "v" }, "<Leader>at", "<Cmd>Qanda /turn_picker<CR>", { desc = "Qanda.nvim turn picker" })
    vim.keymap.set({ "n", "v" }, "<Leader>apt", "<Cmd>Qanda /prompt_template_picker<CR>", { desc = "Qanda.nvim prompts template picker" })
    vim.keymap.set({ "n", "v" }, "<Leader>acp", "<Cmd>Qanda /chat_picker<CR>", { desc = "Qanda.nvim Chat picker" })
    vim.keymap.set({ "n", "v" }, "<Leader>apw", "<Cmd>Qanda /prompt_window<CR>", { desc = "Qanda.nvim Prompt window" })
    vim.keymap.set({ "n", "v" }, "<Leader>anc", "<Cmd>Qanda /new_chat<CR>", { desc = "Qanda.nvim new chat" })
    vim.keymap.set({ "n", "v" }, "<leader>ams", "<Cmd>Qanda /model_picker<CR>", { desc = "Qanda.nvim model selection" })
    vim.keymap.set({ "n", "v" }, "<leader>amp", "<Cmd>Qanda /provider_picker<CR>", { desc = "Qanda.nvim provider selection" })
    vim.keymap.set({ "n", "v" }, "<leader>amr", "<Cmd>Qanda /recent_models<CR>", { desc = "Qanda.nvim recent model selection" })
    vim.keymap.set({ "n", "v" }, "<leader>ai", "<Cmd>Qanda /status<CR>", { desc = "Qanda.nvim status information" })
    vim.keymap.set({ "n", "v" }, "<leader>ak", "<Cmd>Qanda /abort<CR>", { desc = "Qanda.nvim abort the current request" })

    -- Key mappings for the default prompt templates --
    vim.keymap.set({ "n", "v" }, "<Leader>aq", ":Qanda !Query<CR>", { desc = "Qanda.nvim ask a question" })
    vim.keymap.set({ "n", "v" }, "<Leader>add", ":Qanda !Dictionary definition<CR>", { desc = "Qanda.nvim dictionary definition" })
    vim.keymap.set({ "n", "v" }, "<Leader>ads", ":Qanda !Synonyms<CR>", { desc = "Qanda.nvim synonyms for word" })
    vim.keymap.set({ "n", "v" }, "<Leader>ada", ":Qanda !Antonyms<CR>", { desc = "Qanda.nvim antonyms for word" })

  end,
}
