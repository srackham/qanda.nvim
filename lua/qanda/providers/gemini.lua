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
  local _ = request -- Suppress unused variable warning
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
    "--data-binary",
    "@-",
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

--- Checks that the Gemini API is reachable and the API key is valid.
--- @return string|nil # `nil` if all checks pass, or a Markdown string describing the problem and how to fix it.
function M.health_check()
  if not api_key or api_key == "" then
    return [[
## Gemini API key not set

No API key was found. The key is required to authenticate with the Google Gemini API.

### How to fix

- Set the `GEMINI_API_KEY` environment variable to your Gemini API key
- Alternatively, set `api_key` in your qanda.nvim `provider_options.gemini` configuration
- You can obtain an API key at <https://aistudio.google.com/apikey>]]
  end

  -- The models endpoint requires a valid API key, so this single request tests both connectivity and auth.
  local ok, response
  ok = pcall(function()
    response = vim.fn.systemlist(
      "curl -q --silent --max-time 10 "
        .. "-H 'Content-Type: application/json' "
        .. string.format("'https://generativelanguage.googleapis.com/v1beta/models?key=%s'", api_key)
    )
  end)

  if not ok or vim.v.shell_error ~= 0 then
    return [[
## Gemini API unreachable

Could not connect to `https://generativelanguage.googleapis.com`.

### How to fix

- Check your internet connection
- Verify that `https://generativelanguage.googleapis.com` is not blocked by a firewall or proxy
- Try running the following in a terminal to confirm connectivity:
  ```
  curl -s 'https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_KEY'
  ```]]
  end

  local raw = table.concat(response, "")
  local decoded_ok, data = pcall(vim.json.decode, raw)

  if not decoded_ok or type(data) ~= "table" then
    return [[
## Gemini returned an invalid response

The server responded, but the reply was not valid JSON.

### Raw response

```
]] .. raw .. [[

```

### How to fix

- This may indicate a temporary server issue; try again later
- Ensure no proxy is intercepting or modifying the response]]
  end

  if data.error then
    local message = (type(data.error) == "table" and data.error.message) or (type(data.error) == "string" and data.error) or "unknown error"

    return [[
## Gemini authentication failed

The API returned an error: _]] .. tostring(message) .. [[_

### How to fix

- Verify your API key is correct and has not been revoked
- Generate a new key at <https://aistudio.google.com/apikey> if necessary
- Ensure the key is set via the `GEMINI_API_KEY` environment variable or in your qanda.nvim configuration
- Check that the Gemini API is enabled for your Google Cloud project]]
  end

  return nil
end

return M
