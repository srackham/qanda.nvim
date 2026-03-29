-- Google Gemini provider --

local utils = require "qanda.utils"
local Config = require "qanda.config"

local M = {}

local api_key = nil

---Local model provider initialisation.
function M.setup()

  -- Use $GEMINI_API_KEY environment variable if `api_key` is not defined in the Gemini configuration options
  api_key = Config.provider_options and Config.provider_options.gemini and Config.provider_options.gemini.api_key and "$GEMINI_API_KEY"

  -- Look up environment variable
  if api_key:gmatch "$[%a_][%w_]*" then
    local env_variable_name = api_key:sub(2)
    api_key = os.getenv(env_variable_name)
    if not api_key then
      utils.notify(env_variable_name .. " environment variable not set", vim.log.levels.ERROR)
    end
  end

end

--- Returns a list of the names of available models or `nil` if an error occurred.
function M.models(opts)
  local _ = opts -- Suppress unused variable warning
  local url = "https://generativelanguage.googleapis.com/v1beta/models"
  local curl_cmd = {
    "curl",
    "-q",
    "--silent",
    "--no-buffer",
    "-H",
    "'Content-Type: application/json'",
    string.format("'%s?key=%s'", url, api_key),
  }

  local data
  local response

  local ok, err = pcall(function()
    response = vim.fn.systemlist(table.concat(curl_cmd, " "))
    data = vim.json.decode(table.concat(response, ""))
  end)
  if not ok then
    utils.notify("Error retrieving model names from provider: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end

  local models = {}
  if data and data.models then
    for _, model in ipairs(data.models) do
      if model.name then
        -- Strip any leading "models/" prefix if you prefer bare names.
        local name = model.name:gsub("^models/", "")
        table.insert(models, name)
      end
    end
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
    "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-H",
    "Content-Type: application/json",
    "-d",
    vim.json.encode(request.data),
  }
end

---Parse and reshape model response to conform to Ollama api/chat API
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

  -- Reshape error response
  if decoded.error then
    return {
      error = decoded.error.message or decoded.error.code or "Gemini API error",
    }
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
