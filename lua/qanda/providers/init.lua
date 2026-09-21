local Config = require "qanda.config"
local State = require "qanda.state"
local utils = require "qanda.utils"
local ui = require "qanda.ui"

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
---@param name string? The name of the provider.
---@return Provider|nil The provider. Return `nil` if provider not found.
function M.get_provider(name)
  if not name then
    return nil
  end
  for _, provider in ipairs(M.providers) do
    if provider.name == name then
      return provider
    end
  end
  utils.notify("No provider named '" .. name .. "'", vim.log.levels.ERROR)
  return nil
end

---Checks provider name and model name are valid.
---@param provider_name string The name of the provider.
---@param model_name string The name of the model.
---@return boolean Return `true` if the model exists
function M.is_valid_model(provider_name, model_name)
  local provider = M.get_provider(provider_name)
  assert(provider, "No provider named '" .. provider_name .. "'") -- Provider names should always be valid
  local models = provider.module.models(Config)
  assert(models and #models > 0, "Provider '" .. provider_name .. "' has no models") -- Providers should always have one or more models
  if not model_name or not vim.list_contains(models, model_name) then
    return false
  end
  return true
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
--- @param provider_name? string The name of the provider.
--- @param model_name? string The name of the model.
--- @param on_selection fun(selected_model: Model)? The function to call on successful selection.
--- @return Provider|nil The restored provider if successful, otherwise `nil` (if a selection was scheduled).
function M.set_provider(provider_name, model_name, on_selection)
  local provider = M.get_provider(provider_name)
  if not provider then
    M.select_provider(State.provider, function(p_name)
      M.select_model(p_name, on_selection)
    end)
  else
    if not model_name or not M.is_valid_model(provider.name, model_name) then
      M.select_model(provider_name, on_selection)
    else
      -- Arrive here when called with a valid provider and model
      State.provider = provider
      State.provider.model = model_name
      State.saved_state.model = model_name
      State.saved_state.provider = provider.name
      M.update_recent_models(provider_name, model_name)
      State.save_state()
      return provider
    end
  end
  return nil -- Exit having initiated asynchronous provider/model selection
end

--- Prompts the user to select a provider.
--- @param current_provider Provider? The currently active provider, if any, to highlight.
--- @param on_selection fun(selected_provider_name: string)? The function to call on successful selection.
function M.select_provider(current_provider, on_selection)
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
  vim.ui.select(items, { prompt = "Providers" }, function(provider_name)
    if provider_name then
      provider_name = string.sub(provider_name, 3)
      -- Perform provider health check before calling callback
      local provider = M.get_provider(provider_name)
      assert(provider)
      local diagnostic_message = provider.module.health_check(Config)
      if diagnostic_message then
        local lines = vim.split(utils.trim_string(diagnostic_message), "\n")
        ui.open_foreground_float(lines, { width = 120, height = 999 })
      else
        if on_selection then
          on_selection(provider_name)
        end
      end
    end
  end)
end

---Presents a model selection picker to the user.
---
---Allows the user to select a model from the currently active provider.
---The selected model is then saved in the application state.
---@param provider_name string? The name of the provider to select models from. If nil, uses the current State.provider.
--- @param on_completion fun(selected_model: Model)? The function to call on successful selection.
function M.select_model(provider_name, on_completion)
  local provider
  if provider_name then
    provider = M.get_provider(provider_name)
  else
    provider = State.provider
    assert(provider)
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
      if on_completion then
        on_completion { provider_name = provider_name, model_name = model_name }
      end
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
    if M.is_valid_model(provider_name, model_name) then
      M.set_provider(provider_name, model_name)
    else
      M.drop_recent_model(provider_name, model_name)
      State.save_state()
      utils.notify("Invalid model `" .. provider_name .. "/" .. model_name .. "' removed from recent models list", vim.log.levels.INFO)
    end

  end)
end

---Merge model options from `provider` configuration `model_options` and `provider_options` into `request_data.model_options`
---@param provider string
---@param model string
---@param request_data RequestData
function M.merge_config_model_options(provider, model, request_data)
  -- Merge configuration provider_options (lowest priority)
  local model_options = Config.provider_options[provider]
  if model_options then
    for k, v in pairs(model_options) do
      if k ~= "api_key" then -- Don't pass the `api_key` option through to the model.
        request_data[k] = v
      end
    end
  end

  -- Merge configuration model_options
  model_options = Config.model_options[provider .. "/" .. model]
  if model_options then
    for k, v in pairs(model_options) do
      request_data[k] = v
    end
  end
end

return M
