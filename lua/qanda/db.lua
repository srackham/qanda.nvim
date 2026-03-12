---Debug functions used during development.

local Config = require "qanda.config"

local M = {} -- This module

function M.print(v)
  if Config.debug then
    print(vim.inspect(v))
  end
end

function M.printif(b, v)
  if b then
    M.print(v)
  end
end

return M
