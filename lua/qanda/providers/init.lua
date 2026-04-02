local Config = require "qanda.config"
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {
  providers = {}, ---@type Provider[]
}

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
---@return Provider|nil The provider. Return `nil` if provider not found.
function M.get_provider(name)
  for _, provider in ipairs(M.providers) do
    if provider.name == name then
      return provider
    end
  end
  utils.notify("No provider named '" .. name .. "'", vim.log.levels.ERROR)
  return nil
end

---Checks provider and model names are valid.
---@param provider_name string The name of the provider.
---@param model_name string The name of the model.
---@return Provider|nil Returns the provider if the provider and model names are valid, else returns `nil`.
function M.is_valid_provider_model(provider_name, model_name)
  local provider = M.get_provider(provider_name)
  if not provider then
    utils.notify("No provider named '" .. provider_name .. "'", vim.log.levels.ERROR)
    return nil
  end
  local models = provider.module.models(Config)
  if not models then
    return nil
  end
  if not utils.table_contains(models, model_name) then
    utils.notify("No model named '" .. model_name .. "'", vim.log.levels.ERROR)
    return nil
  end
  return provider
end

--- Restores the provider and model.
--- If the provider or model names are invalid, it prompts the user for selection.
---@param provider_name? string The name of the provider.
---@param model_name? string The name of the model.
--- @return Provider|nil The restored provider if successful, otherwise `nil` (if a selection was scheduled).
function M.set_provider(provider_name, model_name)
  if not provider_name then
    vim.cmd "Qanda /provider_selector"
  else
    local provider = M.get_provider(provider_name)
    if not provider then
      return nil
    end
    State.provider = provider
    if not model_name or not M.is_valid_provider_model(provider.name, model_name) then
      vim.cmd "Qanda /model_selector"
    else
      State.provider.model = model_name
      State.saved_state.model = model_name
      State.saved_state.provider = provider.name
      return provider
    end
  end
  return nil
end

--- Prompts the user to select a provider using `vim.ui.select`.
--- @param current_provider Provider? The currently active provider, if any, to highlight.
--- @param callback fun(selected_provider_name: string) The function to call with the name of the selected provider.
function M.select_provider(current_provider, callback)
  local items = {}
  for _, v in ipairs(M.providers) do
    table.insert(items, v.name)
  end
  for i, v in ipairs(items) do
    if current_provider and v == current_provider.name then -- Highlight current provider
      items[i] = "* " .. v
    else
      items[i] = "  " .. v
    end
  end
  vim.ui.select(items, { prompt = "Providers" }, function(item)
    if item then
      item = string.sub(item, 3)
      callback(item)
    end
  end)
end

---Presents a model selection picker to the user.
---
---Allows the user to select a model from the currently active provider.
---The selected model is then saved in the application state.
function M.select_model()
  local items = State.provider.module.models(Config)
  if not items then
    return
  end
  for i, v in ipairs(items) do
    if v == State.provider.model then -- Highlight current model
      items[i] = "* " .. v
    else
      items[i] = "  " .. v
    end
  end
  utils.select(items, {
    results_title = State.provider.name .. " models",
    prompt = "",
    layout_config = Config.model_picker_layout,
  }, function(item)
    if item then
      item = string.sub(item, 3)
      utils.notify("Model set to '" .. item .. "'", vim.log.levels.INFO)
      State.provider.model = item
      State.saved_state.model = item
      State.saved_state.provider = State.provider.name
      State.save_state()
    end
  end)
end

return M
