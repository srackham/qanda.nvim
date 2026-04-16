-- Ollama provider --

local utils = require "qanda.utils"

local M = {} -- This module

--- Initializes the Ollama provider, attempting to start the Ollama server.
function M.setup()
  pcall(io.popen, "ollama serve > /dev/null 2>&1 &")
end

--- Returns a list of the names of available models or `nil` if an error occurred.
---@param opts table User configuration options
---@return string[]|nil
function M.models(opts)
  local data
  local response

  local ok, err = pcall(function()
    response = vim.fn.systemlist("curl -q --silent --no-buffer http://" .. opts.host .. ":" .. opts.port .. "/api/tags")
    data = vim.json.decode(table.concat(response, ""))
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
  local _ = request -- Suppress unused variable warning
  return {
    "curl",
    "-q",
    "--silent",
    "--no-buffer",
    "-X",
    "POST",
    "http://" .. request.host .. ":" .. request.port .. "/api/chat",
    "--data-binary",
    "@-",
  }
end

---Parse and reshape model response to conform to Ollama api/chat API
---@param raw_json string
---@return table|nil
function M.normaliser(raw_json)
  -- No reshaping necessary (this is an Ollama response)
  local ok, decoded = pcall(vim.json.decode, raw_json)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

--- Checks that the Ollama server is reachable and responding.
--- @param opts table User configuration options with `host` and `port` fields.
--- @return string|nil # `nil` if all checks pass, or a Markdown string describing the problem and how to fix it.
function M.health_check(opts)
  local ok, response
  ok = pcall(function()
    response = vim.fn.systemlist(
      "curl -q --silent --max-time 5 http://" .. opts.host .. ":" .. opts.port .. "/api/tags"
    )
  end)

  if not ok or vim.v.shell_error ~= 0 then
    return [[
## Ollama server unreachable

Could not connect to `http://]] .. opts.host .. ":" .. opts.port .. [[`.

### How to fix

- Make sure Ollama is installed: <https://ollama.com/download>
- Start the server with `ollama serve`
- Verify the `host` and `port` values in your qanda.nvim configuration match the running server
- Check that no firewall or proxy is blocking the connection]]
  end

  local raw = table.concat(response, "")
  local decoded_ok, data = pcall(vim.json.decode, raw)

  if not decoded_ok or type(data) ~= "table" then
    return [[
## Ollama server returned an invalid response

The server at `http://]] .. opts.host .. ":" .. opts.port .. [[` responded, but the reply was not valid JSON.

### Raw response

```
]] .. raw .. [[

```

### How to fix

- Ensure nothing else (e.g. a reverse proxy) is listening on that port
- Restart Ollama with `ollama serve` and try again]]
  end

  if data.error then
    return [[
## Ollama authentication error

The server returned an error: **]] .. tostring(data.error) .. [[**

### How to fix

- If you are using an Ollama proxy that requires an API key, make sure the key is set correctly
- Check the `OLLAMA_API_KEY` environment variable or any relevant auth configuration
- Verify your Ollama server logs for more details]]
  end

  return nil
end

return M
