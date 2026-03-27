local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"
local curl = require "qanda.curl"
-- local debug = require "qanda.debug"

local M = {}

function M.setup()
  -- Close existing Chat window
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      utils.close_ephemeral_window(Config.CHAT_BUFFER_NAME)
    end,
  })

  -- Load the most recent chat
  if Config.chat_reload then
    local chat_file = M.recent_chat_file()
    if chat_file then
      local chats = M.load_chats(chat_file)
      if #chats == 1 then
        State.chats = chats
        State.chat_window.chat = chats[1]
        if M.chat_has_system_message(chats[1], State.system_message.expanded) then
          if State.system_message then
            State.system_message.consumed = true
          end
        end
      end
    end
  end
end

local function chats_dir()
  return Config.data_dir .. "/chats"
end

--- Checks if any turn in the chat has a system message matching the given string.
---@param chat Chat The chat object to search.
---@param message string The system message string to look for.
---@return boolean found Returns true if a match is found, otherwise false.
function M.chat_has_system_message(chat, message)
  for _, turn in ipairs(chat.turns) do
    -- Check if the system field exists and matches the target prompt
    if turn.system == message then
      return true
    end
  end
  return false
end

local function parse_turns(lines)
  local result = {}
  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if #line > 0 then -- Skip blank lines
      local ok, parsed_line = pcall(vim.fn.json_decode, line)
      if ok and type(parsed_line) == "table" then
        table.insert(result, parsed_line)
      else
        return nil
      end
    end
  end
  return result
end

--- Loads chats. If chat_file is provided, loads only that file.
--- Otherwise, scans chats_dir() for all .chat.jsonl files.
---@param chat_file string? Optional specific file to load
---@return Chat[] result A list of Chat objects
function M.load_chats(chat_file)
  local result = {} ---@type Chat[]
  local chat_files = {}
  local current_chat_loaded = false
  local current_chat_filename = State.chat_window.chat and State.chat_window.chat.filename

  -- Determine which files to load
  if chat_file then
    table.insert(chat_files, chat_file)
  else
    local glob_pattern = chats_dir() .. "/*.chat.jsonl"
    chat_files = vim.fn.glob(glob_pattern, false, true)
  end

  -- Process the files
  for _, file_path in ipairs(chat_files) do
    if utils.file_exists(file_path) then
      local lines = vim.fn.readfile(file_path)
      local turns = parse_turns(lines)
      if turns then
        local chat = { turns = turns, filename = file_path }
        table.insert(result, chat)
        if current_chat_filename == file_path then
          -- The chat in the Chat window is in the loaded chats.
          current_chat_loaded = true
        end
      else
        utils.notify("Failed to parse chats from '" .. file_path .. "', skipping.", vim.log.levels.ERROR)
      end
    else
      utils.notify("File not readable or does not exist '" .. file_path .. "', skipping.", vim.log.levels.ERROR)
    end
  end

  -- Create a new chat if the chat in the Chat window was not loaded
  if current_chat_filename and not current_chat_loaded then
    utils.notify("The current chat file was missing: '" .. State.chat_window.chat.filename .. "'.", vim.log.levels.WARN)
    M.new_chat()
    if State.chat_window:is_open() then
      M.open_chat()
    end
  end

  return result
end

--- Saves the chat table to a JSONL file.
---@param chat Chat
function M.save_chat(chat)
  local dir = chats_dir()

  -- 1. Determine the filename
  if not chat.filename then
    local timestamp = os.date "%Y%m%d_%H%M%S"
    -- Store the full expanded path in the chat object
    chat.filename = dir .. "/" .. timestamp .. ".chat.jsonl"
  end

  -- 2. Ensure the directory exists
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  -- 3. Prepare the JSONL content
  local lines = {}
  for _, turn in ipairs(chat.turns) do
    local ok, json = pcall(vim.json.encode, turn)
    if ok then
      table.insert(lines, json)
    end
  end

  -- 4. Write to the chat file
  local file = io.open(chat.filename, "w")
  if not file then
    -- This will now trigger if the path expansion failed or permissions are off
    vim.notify("FileSystem Error: Could not open " .. chat.filename, vim.log.levels.ERROR)
    return
  end

  file:write(table.concat(lines, "\n") .. "\n")
  file:close()

  -- 5. Record the mostly recently updated chat file name
  M.set_recent_chat_file(chat.filename)

end

function M.set_recent_chat_file(chat_file)
  State.saved_state.chat_file = chat_file
  State.save_state()
end

--- Returns the full path of the most recently updated chat file
function M.recent_chat_file()
  return State.saved_state.chat_file
end

local function get_turn_index(chat, turn)
  return utils.index_of(chat.turns, turn)
end

local function get_next_turn(chat, turn)
  local index = get_turn_index(chat, turn)
  if index and index < #chat.turns then
    return chat.turns[index + 1]
  else
    return nil
  end
end

local function get_prev_turn(chat, turn)
  local index = get_turn_index(chat, turn)
  if index and index > 1 then
    return chat.turns[index - 1]
  else
    return nil
  end
end

function M.delete_turn(chat, turn)
  if turn then
    table.remove(chat.turns, get_turn_index(chat, turn))
    if #chat.turns == 0 then
      -- Once the last turn has been deleted, delete the chat file
      if chat.filename then
        utils.delete_file(chat.filename)
        if chat == State.chat_window.chat then
          M.new_chat()
        end
      end
    else
      M.save_chat(chat)
      State.chat_window.current_turn = nil -- Force Chat window refresh when picker is closed
    end
  end
end

---Open chat window, load the chat turn at chat `current_turn`.
---If the chat window does not exist, create it and attach key-mapped commands.
---@param chat Chat?
function M.open_chat(chat, turn)
  local win = State.chat_window
  if chat then
    win.chat = chat
  end
  assert(win.chat)
  win.current_turn = turn or win.current_turn or win.chat.turns[#win.chat.turns]
  win:open()
  win:set_title("Chat [" .. Config.help_key .. " help]")

  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  M.add_chat_syntax_highlighting(win.bufnr)
  if win.current_turn then
    local lines = M.turn_to_lines(win.chat, win.current_turn)
    win:set_lines(lines)
  else
    win:set_lines { "" }
  end

  -- Attach key commands.
  vim.keymap.set("n", Config.chat_close_key, function()
    win:close()
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_abort_key, function()
    curl.kill_command()
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_switch_key, function()
    vim.cmd "Qanda /prompt"
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_prompt_key, function()
    local current_turn = win.current_turn or {}
    require("qanda.prompts").open_prompt {
      model_options = current_turn.model_options,
      extract = current_turn.extract,
      prompt = current_turn.request,
    }
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_prev_key, function()
    if win.current_turn then
      local t = get_prev_turn(win.chat, win.current_turn)
      if t then
        M.open_chat(win.chat, t)
      end
    end
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_next_key, function()
    if win.current_turn then
      local t = get_next_turn(win.chat, win.current_turn)
      if t then
        M.open_chat(win.chat, t)
      end
    end
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_delete_key, function()
    M.delete_turn(win.chat, win.current_turn)
    M.open_chat(win.chat, win.current_turn)
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_edit_key, function()
    if win.chat.filename then
      win:close()
      local timestamp = win.current_turn.timestamp
      utils.edit_file(
        win.chat.filename,
        M.add_chat_syntax_highlighting,
        '"timestamp":%s*"' .. utils.escape_pattern(timestamp) .. '"',
        function()
          State.chats = M.load_chats() -- Reload chats after edited file is saved
        end
      )
    else
      utils.notify("Chat file does not exist (the conversation has not begun)", vim.log.levels.WARN)
    end
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.chat_redo_key, function()
    if #win.chat.turns == 0 then
      utils.notify("Empty chat, there is nothing to redo", vim.log.levels.WARN)
      return
    end

    -- Delete the most recent turn and re-execute it
    local most_recent_turn = win.chat.turns[#win.chat.turns]
    table.remove(win.chat.turns)
    win.current_turn = nil
    M.open_chat()
    require("qanda.prompts").open_prompt {
      model_options = most_recent_turn.model_options,
      extract = most_recent_turn.extract,
      prompt = most_recent_turn.request,
    }
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.help_key, function()
    local help_message = ([[-- Chat Window Commands --

Normal mode commands:

- %s - Create a new prompt from the current Chat window prompt
- %s - Switch to Prompt window
- %s/%s Scroll up/down for previous/next prompt (from the current chat message)
- %s - Delete current turn, if last turn delete the chat
- %s - Open the chat file for editing at the selected turn (by searching for the timestamp)
- %s - Delete then re-execute the latest turn
- %s - Abort the current request
- %s - Close Chat window.

]]):format(
      Config.chat_prompt_key,
      Config.chat_switch_key,
      Config.chat_prev_key,
      Config.chat_next_key,
      Config.chat_delete_key,
      Config.chat_edit_key,
      Config.chat_redo_key,
      Config.chat_abort_key,
      Config.chat_close_key
    )
    vim.notify(help_message, vim.log.levels.INFO)
  end, { buffer = win.bufnr, desc = "Show Chat window help" })
end

-- Assign a new empty chat to the Chat window.
function M.new_chat()
  local new_chat = { turns = {} }

  local win = State.chat_window
  win.chat = new_chat
  win.current_turn = nil

  -- Include the system message in the first turn
  if State.system_message then
    State.system_message.consumed = false
  end

end

---@param chat Chat
---@param turn ChatTurn
---@return string[]
function M.turn_to_lines(chat, turn)
  assert(turn)

  local lines = {}
  local rule = string.rep("_", 3)

  ---Helper to limit lines, handle Markdown integrity, and add truncation marker
  ---@param content string|nil
  ---@param max_lines number
  ---@return string[]
  local function get_limited_prompt(label, content, max_lines)

    if max_lines == 0 then
      return {}
    end

    local split_lines = vim.split(utils.trim_string(content or ""), "\n")
    local processed = {}
    local in_code_block = false
    local truncated = false

    table.insert(processed, label .. ":")
    table.insert(processed, "")
    for i, line in ipairs(split_lines) do
      if i > max_lines then
        truncated = true
        break
      end

      if line:match "^```" then
        in_code_block = not in_code_block
      end
      table.insert(processed, "> " .. line)
    end

    if truncated then
      if in_code_block then
        table.insert(processed, "> ```")
      end
      table.insert(processed, "")
      table.insert(processed, "_...truncated..._")
    end

    return processed
  end

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
  table.insert(lines, string.format("turn: %d of %d", get_turn_index(chat, turn), #chat.turns))

  if turn.system then
    local system_lines = get_limited_prompt("system", turn.system, Config.system_message_lines)
    vim.list_extend(lines, system_lines)
    table.insert(lines, "")
  end

  local request_lines = get_limited_prompt("prompt", turn.request, Config.user_prompt_lines)
  vim.list_extend(lines, request_lines)
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

function M.chat_picker()
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"
  local conf = require("telescope.config").values

  local current_chat = State.chat_window.chat
  local current_chat_deleted = false

  local delete_entry = function(picker_bufnr)
    local current_picker = action_state.get_current_picker(picker_bufnr)

    current_picker:delete_selection(function(selection)
      if selection then
        local chat = selection.value
        if utils.delete_file(chat.filename, { confirm = Config.confirm_chat_file_deletion }) then
          current_chat_deleted = (chat.filename == current_chat.filename)
          return true
        end
      end
      return false
    end)
  end

  local mappings = function(picker_bufnr, map)

    -- Execute the callback when the picker is closed
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = picker_bufnr,
      once = true,
      callback = function()
        -- If necessary, clear the Chat window
        if current_chat_deleted then
          M.new_chat()
          if State.chat_window:is_open() then
            M.open_chat()
          end
        end
      end,
    })

    -- Key commands
    map({ "n", "i" }, Config.chat_picker_open_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(picker_bufnr)
      if selection then
        local chat = selection.value
        assert(chat)
        M.open_chat(chat, chat.turns[#chat.turns]) -- Open at most recent turn
        M.set_recent_chat_file(chat.filename)
      else
        utils.notify("User cancelled", vim.log.levels.INFO)
      end
    end, { desc = "Close the picker and open the chat in the chat window" })

    map({ "n", "i" }, Config.chat_picker_delete_key, function()
      delete_entry(picker_bufnr)
    end, { desc = "Close the picker and delete the selected chat file" })

    map({ "n", "i" }, Config.chat_picker_rename_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local chat = selection.value
        actions.close(picker_bufnr)
        local new_name = vim.fn.input("Enter chat name: ", M.chat_name(chat))
        if new_name == "" then
          return -- User cancelled
        end
        chat.turns[1].chat = new_name
        M.save_chat(chat)
      end
    end, { desc = "Rename the selected chat" })

    map({ "n", "i" }, Config.chat_picker_edit_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local chat = selection.value
        assert(chat)
        assert(chat.filename)
        actions.close(picker_bufnr)
        utils.edit_file(chat.filename, M.add_chat_syntax_highlighting, nil, function()
          State.chats = M.load_chats() -- Reload chats after edited file is saved
        end)
      end
    end, { desc = "Close the picker and edit chats file containing the selected chat" })

    map({ "n", "i" }, Config.help_key, function()
      local help_message = ([[-- Chat Picker Commands --

- %s - Open chat in Chat window
- %s - Delete selected chat
- %s - Rename selected chat
- %s - Edit the chat file

]]):format(Config.chat_picker_open_key, Config.chat_picker_delete_key, Config.chat_picker_rename_key, Config.chat_picker_edit_key)
      vim.notify(help_message, vim.log.levels.INFO)
    end, { buffer = picker_bufnr, desc = "Show Chat picker help" })

    return true
  end

  -- Display entry function
  local display_entry = function(chat)
    local display_entry = M.chat_name(chat)
    if chat.filename == State.chat_window.chat.filename then
      return "* " .. display_entry
    else
      return "  " .. display_entry
    end
  end

  -- Prepare chat data for telescope
  local chats = State.chats

  local picker_entries = {}
  for _, chat in ipairs(chats) do
    table.insert(picker_entries, chat)
  end
  table.sort(picker_entries, function(a, b)
    return a.filename > b.filename
  end)

  -- Previewer that list the chat turns
  local turns_list_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local chat = entry.value
      assert(chat)

      local preview_lines = {}
      for _, turn in ipairs(chat.turns) do
        local line = utils.sanitize_display_entry(turn.request, 80)
        table.insert(preview_lines, line)
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)

    end,
  }

  -- Create and run the telescope picker
  pickers
    .new({}, {
      results_title = "Chats",
      preview_title = "Turns",
      prompt_title = "[" .. Config.help_key .. " help]",
      finder = finders.new_table {
        results = picker_entries,
        entry_maker = function(chat)
          local displayed_name = display_entry(chat)
          return {
            value = chat,
            display = displayed_name,
            ordinal = displayed_name,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = turns_list_previewer,
      attach_mappings = mappings,
      layout_config = Config.chat_picker_layout,
    })
    :find()

  -- chat_picker(State.chats, function(chat_bufnr, map)

end

function M.chat_name(chat)
  return chat.turns[1].chat or utils.sanitize_display_entry(chat.turns[1].request, 60)
end

function M.turns_picker()
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"
  local conf = require("telescope.config").values

  local current_chat = State.chat_window.chat
  local current_turn = State.chat_window.current_turn

  local delete_entry = function(picker_bufnr)
    local current_picker = action_state.get_current_picker(picker_bufnr)

    current_picker:delete_selection(function(selection)
      if selection then
        M.delete_turn(current_chat, selection.value)
        return true
      end
      return false
    end)
  end

  local mappings = function(picker_bufnr, map)

    -- Execute the callback when the picker is closed
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = picker_bufnr,
      once = true,
      callback = function()
        -- Reload the chat window if it is open and a deletion occurred
        if not State.chat_window.current_turn and State.chat_window:is_open() then
          M.open_chat(State.chat_window.chat)
        end
      end,
    })

    -- Key commands
    map({ "n", "i" }, Config.turn_picker_open_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(picker_bufnr)
      if selection then
        M.open_chat(current_chat, selection.value)
      end
    end, { desc = "Close the picker and open the selected turn in the chat window" })

    map({ "n", "i" }, Config.turn_picker_delete_key, function()
      delete_entry(picker_bufnr)
    end, { desc = "Close the picker and delete the selected chat file" })

    map({ "n", "i" }, Config.help_key, function()
      local help_message = ([[-- Turn Picker Commands --

- %s - Open turn in Chat window
- %s - Delete selected turn

]]):format(Config.chat_picker_open_key, Config.turn_picker_delete_key)
      vim.notify(help_message, vim.log.levels.INFO)
    end, { buffer = picker_bufnr, desc = "Show Turn picker help" })

    return true
  end

  -- Display entry function
  local display_entry = function(turn)
    local display = utils.sanitize_display_entry(turn.request, 60)
    if current_turn and turn == current_turn then
      return "* " .. display
    else
      return "  " .. display
    end
  end

  -- Prepare data for telescope
  local picker_entries = {}
  for _, turn in ipairs(current_chat.turns) do
    table.insert(picker_entries, turn)
  end

  -- The original order is the chronological turn order which makes the most sense.
  -- This sort puts the oldest turn at the top of the displayed list; the latest is at the bottom.
  table.sort(picker_entries, function(a, b)
    return get_turn_index(current_chat, a) > get_turn_index(current_chat, b)
  end)

  -- Create previewer that shows the chat value
  local turn_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local lines = M.turn_to_lines(current_chat, entry.value)

      if #lines == 0 then
        table.insert(lines, "**[No content available for this turn]**")
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_chat_syntax_highlighting(self.state.bufnr)
    end,
  }

  -- Create and run the telescope picker
  pickers
    .new({}, {
      results_title = "Turns",
      preview_title = "Turn",
      prompt_title = "[" .. Config.help_key .. " help]",
      finder = finders.new_table {
        results = picker_entries,
        entry_maker = function(entry)
          local displayed_name = display_entry(entry)
          return {
            value = entry,
            display = displayed_name,
            ordinal = displayed_name,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = turn_previewer,
      attach_mappings = mappings,
      layout_config = Config.turn_picker_layout,
    })
    :find()
end

return M
