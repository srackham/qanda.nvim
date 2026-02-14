---@class State
---@field provider Provider|nil
---@field dot_prompt Prompt|nil
local M = {}

local utils = require "qanda.utils"

---Initialise state from configuration.
function M.setup(config, providers)

  -- Set model provider
  local provider = providers.get_provider(config.provider)
  if not provider then
    return
  end

  local models = provider.module.models(config)
  if not utils.table_contains(models, config.model) then
    utils.notify("Unable to  find model '" .. config.model .. "' for provider '" .. config.provider.name .. "'.", vim.log.levels.ERROR)
    return
  end
  provider.model = config.model

  M.provider = provider

end

function M.set_dot_prompt(prompt)
    local dot_prompt = vim.tbl_deep_extend("force", {}, options)
end

return M
