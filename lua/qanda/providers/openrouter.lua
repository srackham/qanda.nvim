-- OpenRouter provider --

local utils = require "qanda.utils"
local Config = require "qanda.config"

local M = {}

local api_key = nil

---Local model provider initialisation.
function M.setup()

  -- Use $OPENROUTER_API_KEY environment variable if `api_key` is not defined in the OpenRouter configuration options
  api_key = Config.provider_options
    and Config.provider_options.openrouter
    and Config.provider_options.openrouter.api_key
    and "$OPENROUTER_API_KEY"

  -- Look up environment variable
  if api_key:gmatch "$[%a_][%w_]*" then
    local env_variable_name = api_key:sub(2)
    api_key = os.getenv(env_variable_name)
    if not api_key then
      utils.notify(env_variable_name .. " environment variable not set", vim.log.levels.ERROR)
    end
  end

end

---Returns a list of the names of available models.
---@param opts table User configuration options
---@return string[]
function M.models(opts)
  local _ = opts -- Suppress unused variable warning
  local response = vim.fn.systemlist(
    "curl -q --silent --no-buffer " .. "-H 'Authorization: Bearer " .. api_key .. "' " .. "'https://openrouter.ai/api/v1/models'"
  )
  local data = vim.json.decode(table.concat(response, ""))
  local models = {}
  for _, model in ipairs(data.data) do
    table.insert(models, model.id)
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
    "https://openrouter.ai/api/v1/chat/completions",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-H",
    "Content-Type: application/json",
    "-d",
    vim.json.encode(request.data),
  }
end

---@param raw_json string
---@return table|nil
function M.normaliser(raw_json)
  -- Strip "data:" prefix, if present
  local trimmed = vim.trim(raw_json)
  if trimmed:sub(1, 5) == "data:" then
    trimmed = vim.trim(trimmed:sub(6))
  end
  if trimmed == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, trimmed)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  local resp = {}

  -- Map delta content into Ollama‑style message.content
  local choices = decoded.choices
  if type(choices) == "table" and #choices > 0 and type(choices[1].delta) == "table" then
    local content = choices[1].delta.content
    if type(content) == "string" then
      resp.message = {
        content = content,
      }
    end
  end

  -- Map finish_reason to Ollama‑style done flag
  if type(choices) == "table" and #choices > 0 and type(choices[1].finish_reason) == "string" then
    resp.done = true
  end

  return resp
end

return M
