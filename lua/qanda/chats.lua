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
  local result = {}
  for _, line in ipairs(lines) do
    local ok, parsed_line = pcall(vim.fn.json_decode, line)
    if ok and type(parsed_line) == "table" then
      table.insert(result, parsed_line)
    else
      return nil
    end
  end
  return result
end

function M.load_chats()
  local result = {} ---@type Chats

  -- Read and merge chats from all .chat.jsonl files
  local chats_dir = Config.chats_dir
  local glob_pattern = chats_dir .. "/*.chat.jsonl"
  local chat_files = vim.fn.glob(glob_pattern, false, true)

  -- Load the chats files
  local chat_window_updated = false
  for _, file_path in ipairs(chat_files) do
    if vim.fn.filereadable(file_path) == 1 then
      local lines = vim.fn.readfile(file_path)
      if lines then
        local turns = parse_turns(lines)
        if turns then
          assert(#turns > 0)
          local chat = { dialog = turns, filename = file_path }
          table.insert(result, chat)
          if State.chat_window.chat.filename == file_path then
            State.chat_window.chat = chat
            State.chat_window.turn_index = nil
            chat_window_updated = true
          end
        else
          utils.notify("Failed to parse chats from '" .. file_path .. "', skipping.", vim.log.levels.ERROR)
        end
      end
    end
  end
  if not chat_window_updated then -- invalidate chat window
    State.chat_window.chat = { dialog = {} }
    State.chat_window.turn_index = nil
  end
  return result
end

---Open chat window, load the chat turn at chat index `idx`.
---If the chat window does not exist, create it and attach key-mapped commands.
---@param chat Chat?
function M.open_chat(chat, turn_index)
  local win = State.chat_window
  if chat then
    win.chat = chat
  end
  assert(win.chat)
  win.turn_index = turn_index or win.turn_index or #win.chat.dialog
  win:open()
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  M.add_chat_syntax_highlighting(win.bufnr)
  if win.turn_index and win.turn_index > 0 then
    assert(win.turn_index <= #win.chat.dialog)
    local lines = M.turn_to_lines(win.chat, win.turn_index)
    win:set_lines(lines)
  end
  -- Attach key commands.
  vim.keymap.set("n", Config.quit_key, function()
    win:close()
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.switch_key, function()
    vim.cmd "Qanda /prompt"
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.prev_key, function()
    if win.turn_index and win.turn_index > 1 then
      M.open_chat(win.chat, win.turn_index - 1)
    end
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.next_key, function()
    if win.turn_index and win.turn_index < #win.chat.dialog then
      M.open_chat(win.chat, win.turn_index + 1)
    end
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.edit_key, function()
    if win.chat.filename then
      win:close()
      local timestamp = win.chat.dialog[win.turn_index].timestamp
      utils.edit_file(
        win.chat.filename,
        M.add_chat_syntax_highlighting,
        '"timestamp":%s*"' .. utils.escape_pattern(timestamp) .. '"',
        function()
          M.load_chats() -- Reload chats after edited file is saved
        end
      )
    else
      utils.notify("Chat file does not exist (the conversation has not begun)", vim.log.levels.INFO)
    end
  end, { buffer = win.bufnr })
end

function M.new_chat()
  State.system_chat = nil ---@todo  should init to default system chat if defined.
end

---@param chat Chat
---@param turn_index number
---@return string[]
function M.turn_to_lines(chat, turn_index)
  local turn = chat.dialog[turn_index]
  local lines = {}
  local rule = string.rep("─", 40)

  table.insert(lines, rule)
  if turn.model then
    table.insert(lines, "model: " .. turn.model)
  end
  if turn.provider then
    table.insert(lines, "provider: " .. turn.provider)
  end
  if turn.timestamp then
    table.insert(lines, "timestamp: " .. turn.timestamp)
  end
  if turn.extract then
    table.insert(lines, "extract: " .. utils.escape_string(turn.extract))
  end
  if turn.model_options then
    for k, v in pairs(turn.model_options) do
      table.insert(lines, k .. ": " .. v)
    end
  end
  table.insert(lines, string.format("turn: %d of %d", turn_index, #chat.dialog))
  if turn.system then
    table.insert(lines, "system:")
    table.insert(lines, "")
    for _, v in ipairs(vim.split(utils.trim_string(turn.system or ""), "\n")) do
      table.insert(lines, "> " .. v)
    end
    table.insert(lines, "")
  end
  table.insert(lines, "prompt:")
  table.insert(lines, "")
  for _, v in ipairs(vim.split(utils.trim_string(turn.request or ""), "\n")) do
    table.insert(lines, "> " .. v)
  end
  table.insert(lines, "")
  table.insert(lines, rule)
  for _, v in ipairs(vim.split(utils.trim_string(turn.response or ""), "\n")) do
    table.insert(lines, v)
  end
  return lines
end

local chat_syntax_rules = {
  QandaChatProperty = [[\v^(provider|timestamp|prompt|system|model|provider|extract|turn|temperature|top_p|max_tokens|stream):]],
}

-- Define highlight groups once (link to existing groups)
vim.api.nvim_set_hl(0, "QandaChatProperty", { link = "Keyword" })

--- Add extra syntax prompt file highlighting rules to a buffer
--- NOTE: Treesitter highlighting may override these.
---@param bufnr integer
function M.add_chat_syntax_highlighting(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    for group, pattern in pairs(chat_syntax_rules) do
      vim.cmd(("syntax match %s /%s/"):format(group, pattern))
    end
  end)
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
    return a.filename > b.filename
  end)

  -- Create previewer that shows the chat value
  local chat_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local chat = entry.value

      assert(chat)

      local lines = M.turn_to_lines(chat, #chat.dialog)

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_chat_syntax_highlighting(self.state.bufnr)
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
            display = display_entry and display_entry(chat) or chat.filename,
            ordinal = chat.filename, -- File name ensures chronological chat sorting
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

  chat_picker(State.chats, function(chat_bufnr, map)

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
    map({ "n", "i" }, Config.delete_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(chat_bufnr)
      if selection then
        vim.schedule(function()
          local chat = selection.value
          local confirm_result = vim.fn.confirm("Delete '" .. chat.filename .. "'?", "&Yes\n&No", 2)
          if confirm_result == 1 then -- User selected 'Yes'
            -- Synchronously delete selected chat file
            local ok, err = os.remove(chat.filename)
            if ok then
              utils.notify("Deleted '" .. chat.filename .. "'", vim.log.levels.INFO)
            else
              utils.notify("Failed to delete file '" .. chat.filename .. "': " .. (err or "unknown error"), vim.log.levels.ERROR)
            end
          else
            utils.notify("User aborted", vim.log.levels.INFO)
          end
        end)
      end
    end)

    -- Close the picker and edit chats file containing the selected chat
    map({ "n", "i" }, Config.edit_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local chat = selection.value
        assert(chat)
        assert(chat.filename)
        actions.close(chat_bufnr)
        utils.edit_file(chat.filename, M.add_chat_syntax_highlighting, nil, function()
          M.load_chats() -- Reload chats after edited file is saved
        end)
      end
    end)

    return true
  end, function(chat)
    local display_entry = utils.truncate_string(chat.dialog[1].request, 20)
    if chat.filename == State.chat_window.chat.filename then
      return "* " .. display_entry
    else
      return "  " .. display_entry
    end
  end)
end

return M
