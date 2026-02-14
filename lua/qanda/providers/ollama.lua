-- See https://github.com/wsdjeg/chat.nvim/tree/master?tab=readme-ov-file#custom-providers
-- Replace job.nvim with vim.fn.jobstart with Neovim's vim.system.
--  See: https://gemini.google.com/share/02fe3ad7f355, https://chatgpt.com/share/69800de8-72d0-8003-b893-e68905c55f51

local M = {}

---Local model provider initialisation.
function M.setup()
  pcall(io.popen, "ollama serve > /dev/null 2>&1 &")
end

---Returns a list of the names of available models.
---@param opts table
---@return string[]
function M.models(opts)
  local response = vim.fn.systemlist("curl -q --silent --no-buffer http://" .. opts.host .. ":" .. opts.port .. "/api/tags")
  local list = vim.fn.json_decode(response)
  local models = {}
  for key, _ in ipairs(list.models) do
    table.insert(models, list.models[key].name)
  end
  table.sort(models)
  return models
end

---Returns a list containing the model request shell command and its arguments.
---@param request Request
---@return string[]
function M.command(request)
  return {
    "curl",
    "-q",
    "--silent",
    "--no-buffer",
    "-X",
    "POST",
    "http://" .. request.host .. ":" .. request.port .. "/api/chat",
    "-d",
    vim.json.encode(request.data),
  }
end

return M
