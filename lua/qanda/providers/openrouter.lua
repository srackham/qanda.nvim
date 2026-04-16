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

--- Returns a list of the names of available models or `nil` if an error occurred.
---@param opts table User configuration options
---@return string[]|nil
function M.models(opts)
  local _ = opts -- Suppress unused variable warning

  local data
  local response

  local ok, err = pcall(function()
    response = vim.fn.systemlist(
      "curl -q --silent --no-buffer " .. "-H 'Authorization: Bearer " .. api_key .. "' " .. "'https://openrouter.ai/api/v1/models'"
    )
    data = vim.json.decode(table.concat(response, ""))
  end)
  if not ok then
    utils.notify("Error retrieving model names from provider: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end

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
  local _ = request -- Suppress unused variable warning
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
      error = decoded.error.message or decoded.error.code or "OpenRouter API error",
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

--- Checks that the OpenRouter API is reachable and the API key is valid.
--- @return string|nil # `nil` if all checks pass, or a Markdown string describing the problem and how to fix it.
function M.health_check()
  if not api_key or api_key == "" then
    return [[
## OpenRouter API key not set

No API key was found. The key is required to authenticate with the OpenRouter API.

### How to fix

- Set the `OPENROUTER_API_KEY` environment variable to your OpenRouter API key
- Alternatively, set `api_key` in your qanda.nvim `provider_options.openrouter` configuration
- You can obtain an API key at <https://openrouter.ai/keys>]]
  end

  -- First check: connectivity (this endpoint does not require auth)
  local ok, response
  ok = pcall(function()
    response = vim.fn.systemlist "curl -q --silent --max-time 10 'https://openrouter.ai/api/v1/models'"
  end)

  if not ok or vim.v.shell_error ~= 0 then
    return [[
## OpenRouter API unreachable

Could not connect to `https://openrouter.ai/api/v1/models`.

### How to fix

- Check your internet connection
- Verify that `https://openrouter.ai` is not blocked by a firewall or proxy
- Try running the following in a terminal to confirm connectivity:
  ```
  curl -s https://openrouter.ai/api/v1/models
  ```]]
  end

  local raw = table.concat(response, "")
  local decoded_ok, data = pcall(vim.json.decode, raw)

  if not decoded_ok or type(data) ~= "table" then
    return [[
## OpenRouter returned an invalid response

The server responded, but the reply was not valid JSON.

### Raw response

```
]] .. raw .. [[

```

### How to fix

- This may indicate a temporary server issue; try again later
- Ensure no proxy is intercepting or modifying the response]]
  end

  -- Second check: API key validity (this endpoint requires auth)
  local auth_ok, auth_response
  auth_ok = pcall(function()
    auth_response = vim.fn.systemlist(
      "curl -q --silent --max-time 10 " .. "-H 'Authorization: Bearer " .. api_key .. "' " .. "'https://openrouter.ai/api/v1/auth/key'"
    )
  end)

  if not auth_ok or vim.v.shell_error ~= 0 then
    return [[
## OpenRouter API key check failed

Connected to OpenRouter successfully, but the authentication check request failed.

### How to fix

- This may indicate a temporary server issue; try again later
- Check your internet connection is stable]]
  end

  local auth_raw = table.concat(auth_response, "")
  local auth_decoded_ok, auth_data = pcall(vim.json.decode, auth_raw)

  if not auth_decoded_ok or type(auth_data) ~= "table" then
    return [[
## OpenRouter returned an invalid authentication response

The auth endpoint responded, but the reply was not valid JSON.

### Raw response

```
]] .. auth_raw .. [[

```

### How to fix

- This may indicate a temporary server issue; try again later
- Ensure no proxy is intercepting or modifying the response]]
  end

  if auth_data.error then
    local message = (type(auth_data.error) == "table" and auth_data.error.message)
      or (type(auth_data.error) == "string" and auth_data.error)
      or "unknown error"

    return [[
## OpenRouter authentication failed

The API returned an error: _]] .. tostring(message) .. [[_

### How to fix

- Verify your API key is correct and has not been revoked
- Check your account status and usage limits at <https://openrouter.ai/settings>
- Regenerate your key at <https://openrouter.ai/keys> if necessary
- Ensure the key is set via the `OPENROUTER_API_KEY` environment variable or in your qanda.nvim configuration]]
  end

  return nil
end

return M
