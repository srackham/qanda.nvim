local Config = require "qanda.config" -- User configuration options
local Providers = require "qanda.providers" -- LLM providers
local utils = require "qanda.utils"
local ui = require "qanda.ui"

---@class State
---@field provider Provider
---@field chats Chats
---@field chat_window UIWindow
---@field prompt_window UIWindow

local M = {
  chats = {},
  chat_window = ui.UIWindow.new {
    buf_name = Config.CHAT_BUFFER_NAME,
    modifiable = false,
    mode = "right",
  },
  prompt_window = ui.UIWindow.new {
    buf_name = Config.PROMPT_BUFFER_NAME,
    modifiable = true,
    mode = "float",
    float_layout = {
      border = "rounded",
      height = 0.5,
    },
  },
}

---Initialise state from configuration.
function M.setup()

  -- Set model provider
  local provider = Providers.get_provider(Config.provider)
  if not provider then
    return
  end

  local models = provider.module.models(Config)
  if not utils.table_contains(models, Config.model) then
    utils.notify("Unable to  find model '" .. Config.model .. "' for provider '" .. Config.provider.name .. "'.", vim.log.levels.ERROR)
    return
  end
  provider.model = Config.model

  M.provider = provider

end

return M
