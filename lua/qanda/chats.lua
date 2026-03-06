local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {
  chats = {}, ---@type Chats
}

function M.setup()
  -- Currently no setup required
end

local function parse_turns(lines)
  local turns = {}
  for _, line in ipairs(lines) do
    local ok, parsed_line = pcall(vim.fn.json_decode, line)
    if ok and type(parsed_line) == "table" then
      table.insert(turns, parsed_line)
    else
      return nil
    end
  end
  return turns
end

function M.load_chats()
  local result = {} ---@type Chats

  -- Read and merge chats from all .chat.jsonl files
  local chats_dir = Config.chats_dir
  local glob_pattern = chats_dir .. "/*.chat.jsonl"
  local chat_files = vim.fn.glob(glob_pattern, false, true)

  -- Load the chats files
  for _, file_path in ipairs(chat_files) do
    if vim.fn.filereadable(file_path) == 1 then
      local lines = vim.fn.readfile(file_path)
      if lines then
        local turns = parse_turns(lines)
        if turns then
          assert(#turns > 0)
          local chat = { dialog = turns }
          table.insert(result, chat)
        else
          utils.notify("Failed to parse chats from '" .. file_path .. "', skipping.", vim.log.levels.ERROR)
        end
      end
    end
  end
  return result
end

---Open chat window, load the chat turn at chat index `idx`.
---If the chat window does not exist, create it and attach key-mapped commands.
---@param chat Chat?
function M.open_chat(chat, turn_index)
  assert(chat)
  local win = State.chat_window
  win:open()
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  win.turn_index = turn_index or #chat
  win.chat = chat
  local lines = M.turn_to_lines(chat.dialog[win.turn_index])
  win:set_lines(lines)
  -- Attach key commands.
  vim.keymap.set("n", Config.quit_key, function()
    win:close()
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.switch_key, function()
    vim.cmd "Qanda /prompt"
  end, { buffer = win.bufnr })
end

function M.new_chat()
  State.system_chat = nil ---@todo  should init to default system chat if defined.
end

---@param turn ChatTurn
---@return string[]
function M.turn_to_lines(turn)
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

      local lines = M.turn_to_lines(chat)

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

function M.chat_picker()
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  chat_picker(State.chats, function(chat_bufnr)

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

    -- Close the picker and delete the selected chat file
    vim.keymap.set({ "n", "i" }, Config.delete_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(chat_bufnr)
      if selection then
        ---@todo Delete selected chat file
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
        assert(chat.filename)
        actions.close(chat_bufnr)
        utils.edit_file(chat.filename)
      end
    end, { buffer = chat_bufnr })

    return true
  end)
end

return M
