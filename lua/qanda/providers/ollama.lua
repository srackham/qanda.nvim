-- Ollama provider --

local M = {} -- This module

---Local model provider initialisation.
function M.setup()
  pcall(io.popen, "ollama serve > /dev/null 2>&1 &")
end

---Returns a list of the names of available models.
---@param opts table User configuration options
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

---@param raw_json string
---@return table|nil
function M.normaliser(raw_json)
  local ok, decoded = pcall(vim.json.decode, raw_json)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

return M
