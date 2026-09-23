local Config = require "qanda.config"
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {}
-- Diagnostics file path
local function diagnostics_file()
  return Config.data_dir .. "/diagnostics.md"
end

--- Clear the diagnostics and add timestamped heading.
function M.start()
  utils.write_string_to_file("# Qanda Diagnostics\n\n" .. tostring(os.date(Config.TIME_STAMP_FORMAT)) .. "\n\n", diagnostics_file())
end

--- Display the diagnostics in an ephemeral floating window.
function M.open()
  State.chat_window:close()
  State.prompt_window:close()
  utils.edit_file(diagnostics_file())
end

--- Append diagnostic text for `diagnostic` to the diagnostics file.
--- JSON diagnostics are pretty-printed with jq(1) if it is installed in the system.
--- @param diagnostic Diagnostic
--- @param title string
--- @param content string?
function M.append(diagnostic, title, content)
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

return M
