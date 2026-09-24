local Config = require "qanda.config"
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {}

M.enabled = false

-- Diagnostics file path
local function diagnostics_file()
  return Config.data_dir .. "/diagnostics.md"
end

--- Display the diagnostics in an ephemeral floating window.
function M.view()
  utils.notify("Diagnostics capture is currently " .. (M.enabled and "enabled" or "disabled"), vim.log.levels.WARN)
  State.chat_window:close()
  State.prompt_window:close()
  utils.edit_file(diagnostics_file())
end

--- Clear the diagnostics file and add timestamped heading.
local function write_title()
  utils.write_string_to_file("# Qanda Diagnostics\n\n" .. tostring(os.date(Config.TIME_STAMP_FORMAT)) .. "\n\n", diagnostics_file())
end

--- Append diagnostic text for `diagnostic` to the diagnostics file.
--- JSON diagnostics are pretty-printed with jq(1) if it is installed in the system.
--- @param diagnostic Diagnostic
--- @param title string
--- @param content string?
local function append_section(diagnostic, title, content)
  vim.schedule(function() -- Possible "fast context" deference
    local output = title .. "\n\n"

    if content then
      content = utils.trim_string(content)

      if diagnostic == "curl_command" then
        output = output .. "```\n" .. content .. "\n```\n\n"
      elseif diagnostic == "request_data" or diagnostic == "raw_data" or diagnostic == "normalised_data" then
        local formatted = content
        if vim.fn.executable "jq" == 1 then
          local result = vim.fn.system("jq '.'", content)
          if vim.v.shell_error == 0 then
            formatted = utils.trim_string(result)
          end
        end
        output = output .. "```json\n" .. formatted .. "\n```\n\n"
      else
        output = output .. content .. "\n\n"
      end
    end

    utils.append_string_to_file(output, diagnostics_file())
  end)
end

function M.write_to_file(curl_args, request_data, response_data)
  write_title()
  append_section(
    "curl_command",
    "## Curl command\n\nThe _Request data_ is piped into this `curl` command.",
    utils.curl_args_to_shell_command(curl_args)
  )
  append_section("request_data", "## Request data", request_data)
  append_section("raw_data", "## Raw response data\n\nAn array of streamed response chunks.", vim.json.encode(response_data.raw_data))
  append_section(
    "normalised_data",
    "## Normalised response data\nAn array of normalised raw response chunks.",
    vim.json.encode(response_data.normalised_data)
  )
end

return M
