local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {
  chats = {}, ---@type Chats
}

function M.setup()
  -- Currently no setup required
end

---Open chat window, load the chat.
---If the chat window does not exist, create it and attach key-mapped commands.
---If the `chat` is `nil` then don't load the chat text into the window.
---@param chat Chat?
function M.open_chat(chat)
  local win = State.chat_window
  win:open()
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  if chat then
    local lines = M.chat_lines(chat)
    win:set_lines(lines)
  end
  -- Attach key commands.
  vim.keymap.set("n", Config.quit_key, function()
    win:close()
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.switch_key, function()
    vim.cmd "Qanda /chat"
  end, { buffer = win.bufnr })
end

function M.new_chat()
  ---@todo  should init to default system chat if defined.
  State.system_chat=nil
end

---@param turn ChatTurn
---@return string[]
local function turn_to_lines(turn)
  local lines = {}
  local rule = string.rep("─", 40)

  table.insert(lines, rule)
  if turn.model then
    table.insert(lines, "model: " .. turn.model)
  end
  if turn.extract then
    table.insert(lines, "extract: " .. utils.escape_string(turn.extract))
  end
  if turn.model_options then
    for k, v in pairs(turn.model_options) do
      table.insert(lines, k .. ": " .. v)
    end
  end
  table.insert(lines, "prompt:")
  table.insert(lines, "")
  for _, v in ipairs(vim.split(utils.trim_string(turn.request or ""), "\n")) do
    table.insert(lines, "> " .. v)
  end
  table.insert(lines, rule)
  for _, v in ipairs(vim.split(utils.trim_string(turn.response or ""), "\n")) do
    table.insert(lines, v)
  end
  return lines
end

---Displays a telescope picker for selecting chats
---@param mappings function Telescope attach_mappings callback
local function chat_picker(chats, mappings, display_entry)
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"
  local conf = require("telescope.config").values

  -- Prepare chat data for telescope
  local picker_entries = {}
  for _, chat in ipairs(chats) do
    table.insert(picker_entries, chat)
  end
  table.sort(picker_entries, function(a, b)
    return a.name < b.name
  end)

  -- Create previewer that shows the chat value
  local chat_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local chat = entry.value

      assert(chat)

      local lines = turn_to_lines(chat)

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      -- vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_chat_syntax_highlighting_rules(self.state.bufnr)
    end,
  }

  -- Create and run the telescope picker
  pickers
    .new({}, {
      finder = finders.new_table {
        results = picker_entries,
        entry_maker = function(chat)
          return {
            value = chat,
            display = display_entry and display_entry(chat) or chat.name,
            ordinal = chat.name,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = chat_previewer,
      attach_mappings = mappings,
      layout_config = Config.chat_picker_layout,
    })
    :find()
end

function M.chat_picker(callback)
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  chat_picker(M.user_chats, function(chat_bufnr)

    -- <Enter> - Close the picker and open the chat in the chat window
    actions.select_default:replace(function()
      local selection = action_state.get_selected_entry()
      actions.close(chat_bufnr)
      if selection then
        local chat = selection.value
        assert(chat)
        M.open_chat(chat)
      else
        utils.notify("User cancelled", vim.log.levels.INFO)
      end
    end)

    -- Close the picker and execute the selected chat template
    vim.keymap.set({ "n", "i" }, Config.exec_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(chat_bufnr)
      if selection then
        callback(selection.value)
      else
        utils.notify("User cancelled", vim.log.levels.INFO)
      end
    end, { buffer = chat_bufnr })

    -- Close the picker and edit chats file containing the selected chat
    vim.keymap.set({ "n", "i" }, Config.edit_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local chat = selection.value
        assert(chat)
        actions.close(chat_bufnr)
        if chat.filename then
          utils.edit_chat(chat.filename, "^name:%s*" .. chat.name)
        else
          utils.notify("No file associated with built-in chat '" .. chat.name .. "'", vim.log.levels.WARN)
        end
      end
    end, { buffer = chat_bufnr })

    return true
  end)
end

return M
