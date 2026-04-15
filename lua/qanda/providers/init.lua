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

-- If the model is in the list then delete it.
function M.drop_recent_model(provider_name, model_name)
  -- If it is in the list then delete it
  for i, v in ipairs(State.recent_models) do
    if v.provider_name == provider_name and v.model_name == model_name then
      table.remove(State.recent_models, i)
      break
    end
  end
end

-- If the model is in the list then delete it, then append it to the list.
function M.update_recent_models(provider_name, model_name)
  M.drop_recent_model(provider_name, model_name)
  table.insert(State.recent_models, { provider_name = provider_name, model_name = model_name })
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
      M.update_recent_models(provider_name, model_name)
      State.save_state()
      utils.notify("Model set to " .. provider_name .. "/" .. model_name, vim.log.levels.INFO)
      return provider
    end
  end
  return nil
end

--- Prompts the user to select a provider.
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
---@param provider_name string? The name of the provider to select models from. If nil, uses the current State.provider.
function M.select_model(provider_name)
  local provider
  if provider_name then
    provider = M.get_provider(provider_name)
  else
    provider = State.provider
    provider_name = provider.name
  end
  assert(provider)
  local models = provider.module.models(Config)
  if not models then
    return
  end
  for i, v in ipairs(models) do
    if v == provider.model then -- Highlight current model
      models[i] = "* " .. v
    else
      models[i] = "  " .. v
    end
  end
  utils.select(models, {
    results_title = provider.name .. " Models",
    prompt = "",
    layout_config = Config.model_picker_layout,
  }, function(model_name)
    if model_name then
      model_name = string.sub(model_name, 3)
      M.set_provider(provider_name, model_name)
    end
  end)
end

--- Prompts the user to select a recent model
function M.select_recent_model()
  local recent_models = State.recent_models

  if not recent_models or #recent_models == 0 then
    utils.notify("No recent models found", vim.log.levels.INFO)
    return
  end

  local current_provider_name = State.provider and State.provider.name or nil
  local current_model_name = State.provider and State.provider.model or nil

  local display_items = {}
  for _, recent_model in ipairs(State.recent_models) do
    local display_string = recent_model.provider_name .. "/" .. recent_model.model_name
    if recent_model.provider_name == current_provider_name and recent_model.model_name == current_model_name then
      display_string = "* " .. display_string
    else
      display_string = "  " .. display_string
    end
    table.insert(display_items, display_string)
  end
  display_items = utils.reverse_table(display_items)

  utils.select(display_items, {
    results_title = "Recent Models",
    prompt = "",
    layout_config = Config.recent_models_layout,
  }, function(selection)
    if not selection then
      return -- User cancelled
    end

    selection = string.sub(selection, 3)
    local provider_name, model_name = string.match(selection, "([^/]+)/(.+)")
    if M.is_valid_provider_model(provider_name, model_name) then
      M.set_provider(provider_name, model_name)
    else
      M.drop_recent_model(provider_name, model_name)
      State.save_state()
      utils.notify("Invalid model `" .. provider_name .. "/" .. model_name .. "' removed from recent models list", vim.log.levels.INFO)
    end

  end)
end

return M
