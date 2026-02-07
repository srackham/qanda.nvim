local utils = require "qanda.utils"

local M = {
  providers = {}, ---@type Provider[]
}

-- function M.get_names()
--   local names = {}
--   for _, provider in ipairs(M.providers) do
--     table.insert(names, provider.name)
--   end
--   return names
-- end

---Load and initialise provider modules.
function M.setup()
  M.providers = {}

  -- Find the absolute path to your plugin's provider directory
  local files = vim.api.nvim_get_runtime_file("lua/qanda/providers/*.lua", true)

  for _, file in ipairs(files) do
    -- Extract the filename without the path and extension
    local name = vim.fn.fnamemodify(file, ":t:r")

    if name ~= "init" then
      local module_path = "qanda.providers." .. name
      local ok, module = pcall(require, module_path)
      if ok then
        table.insert(M.providers, {
          name = name,
          module = module,
        })
      else
        utils.notify("Failed to load provider '" .. module_path .. "'", vim.log.levels.ERROR)
      end
    end
  end

  -- Execute optional provider initialisation.
  for _, provider in ipairs(M.providers) do
    if type(provider.module) == "table" and type(provider.module.setup) == "function" then
      provider.module.setup()
    end
  end
end

---Retrieve provider by name.
---@param name string The name of the provider.
---@return Provider|nil The provider.
function M.get_provider(name)
  for _, provider in ipairs(M.providers) do
    if provider.name == name then
      return provider
    end
  end
  utils.notify("No provider named '" .. name .. "'", vim.log.levels.ERROR)
  return nil
end

function M.select_provider(current_provider, callback)
  local items = {}
  for _, v in pairs(M.providers) do
    table.insert(items, v.name)
  end
  for i, v in pairs(items) do
    if v == current_provider.name then -- Highlight current provider
      items[i] = "* " .. v
    else
      items[i] = "  " .. v
    end
  end
  vim.ui.select(items, { prompt = "Providers" }, function(item)
    if item then
      item = string.sub(item, 3)
      utils.notify("Provider set to '" .. item .. "'", vim.log.levels.INFO)
      callback(item)
    end
  end)
end

return M
