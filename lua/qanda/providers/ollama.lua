-- Ollama provider --

local utils = require "qanda.utils"

local M = {} -- This module

---Local model provider initialisation.
function M.setup()
  pcall(io.popen, "ollama serve > /dev/null 2>&1 &")
end

--- Returns a list of the names of available models or `nil` if an error occurred.
---@param opts table User configuration options
---@return string[]|nil
function M.models(opts)
  vim.keymap.set("n", "<S-CR>", ":echo 'Shift+Enter pressed'<CR>")
  local _ = opts -- Suppress unused variable warning

  local data
  local response

  local ok, err = pcall(function()
    response = vim.fn.systemlist("curl -q --silent --no-buffer http://" .. opts.host .. ":" .. opts.port .. "/api/tags")
    data = vim.fn.json_decode(response)
  end)
  if not ok then
    utils.notify("Error retrieving model names from provider: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end

  local models = {}
  for key, _ in ipairs(data.models) do
    table.insert(models, data.models[key].name)
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
