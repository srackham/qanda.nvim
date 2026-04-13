local Config = require "qanda.config"
local ui = require "qanda.ui"
local utils = require "qanda.utils"

local M = {}

function M.start()
  vim.fn.setreg(Config.diagnostics_register, "# Qanda Diagnostics\n\n" .. tostring(os.date(Config.TIME_STAMP_FORMAT)) .. "\n\n")
end

function M.open()
  local reg = vim.fn.getreg(Config.diagnostics_register)
  local lines = vim.split(reg, "\n")
  ui.open_foreground_float(lines, { width = 120, height = 999 })
end

--- Append diagnostic text for `diagnostic` to the diagnostic register.
--- @param diagnostic Diagnostic
--- @param title string
--- @param content string?
function M.append(diagnostic, title, content)

  vim.schedule(function() -- Possible "fast context" deference
    local reg = vim.fn.getreg(Config.diagnostics_register)

    reg = reg .. title .. "\n\n"

    if content then
      content = utils.trim_string(content)

      if diagnostic == "curl_command" then
        reg = reg .. "```\n" .. content .. "\n```\n\n"
      elseif diagnostic == "request" then
        local formatted = content
        if vim.fn.executable "jq" == 1 then
          local result = vim.fn.system("jq '.'", content)
          if vim.v.shell_error == 0 then
            formatted = utils.trim_string(result)
          end
        end
        reg = reg .. "```json\n" .. formatted .. "\n```\n\n"
      else
        reg = reg .. content .. "\n\n"
      end
    end

    vim.fn.setreg(Config.diagnostics_register, reg)
  end)
end

return M
