local Config = require "qanda.config"
local ui = require "qanda.ui"

local M = {}

function M.start()
  vim.fn.setreg(Config.diagnostics_register, "# Qanda Diagnostics\n")
end

function M.open()
  local reg = vim.fn.getreg(Config.diagnostics_register)
  local lines = vim.split(reg, "\n")
  ui.open_foreground_float(lines, { width = 120, height = 999 })
end

--- Append diagnostic text for `diagnostic` to the diagnostic register.
--- @param diagnostic Diagnostic
--- @param title string
--- @param content string
function M.append(diagnostic, title, content)

  vim.schedule(function() -- Possible "fast context" deference
    local reg = vim.fn.getreg(Config.diagnostics_register)

    reg = reg .. "\n\n" .. title .. "\n"

    if content then
      if diagnostic == "curl_command" then
        reg = reg .. "\n```" .. content .. "\n```"
      elseif diagnostic == "request" then
        local formatted = content
        if vim.fn.executable "jq" == 1 then
          local result = vim.fn.system("jq '.'", content)
          if vim.v.shell_error == 0 then
            formatted = result
          end
        end
        reg = reg .. "\n```json" .. formatted .. "\n```"
      else
        reg = reg .. "\n" .. content
      end
    end

    vim.fn.setreg(Config.diagnostics_register, reg)
  end)
end

return M
