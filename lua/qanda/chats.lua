local Config = require "qanda.config"
local State = require "qanda.state"
local utils = require "qanda.utils"
local curl = require "qanda.curl"
-- local debug = require "qanda.debug"

local M = {
  turn_truncation = true, -- Chat window truncation state
}

--- Initialize the chats module.
function M.setup()
  -- Close existing Chat window
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      -- vim.schedule waits until the current main loop finishes
      -- This ensures the session is 100% loaded before we touch windows
      vim.schedule(function()
        pcall(utils.close_ephemeral_window, Config.CHAT_BUFFER_NAME)
      end)
    end,
  })

  -- Load all chats and set the most recent one as the current chat
  State.chats = M.load_chats()
  if #State.chats > 0 then
    State.chat_window.chat = State.chats[#State.chats] -- Most recent chat
  else
    State.chat_window.chat = nil
  end
end

--- Parse JSONL lines into chat turns.
---@param lines string[] Array of JSON strings.
---@return Turn[]|nil result Array of parsed turns, or nil on parse error.
local function parse_turns(lines)
  local result = {}
  for i, line in ipairs(lines) do
    line = vim.trim(line)
    if #line > 0 then -- Skip blank lines
      local ok, parsed_line = pcall(vim.json.decode, line)
      if ok and type(parsed_line) == "table" then
        table.insert(result, parsed_line)
      else
        utils.notify("JSON parse error at line " .. i .. ": " .. tostring(parsed_line), vim.log.levels.ERROR)
        return nil
      end
    end
  end
  return result
end

--- Loads a single chat from a JSONL file.
---@param file_path string Path to the chat file.
---@return Chat|nil chat The loaded Chat object, or nil if the file could not be read or parsed.
local function load_chat(file_path)
  local result = nil
  if utils.file_exists(file_path) then
    local lines = vim.fn.readfile(file_path)
    local turns = parse_turns(lines)
    if turns then
      result = { turns = turns, filename = file_path }
    else
      utils.notify("Failed to parse turns from '" .. file_path .. "'", vim.log.levels.ERROR)
    end
  else
    utils.notify("File not readable or does not exist '" .. file_path .. "'", vim.log.levels.ERROR)
  end
  return result
end

-- Update `chat` from its chat file.
---@param chat Chat
local function refresh_chat(chat)
  local new_chat = load_chat(chat.filename)
  utils.notify("Loaded file '" .. chat.filename .. "'", vim.log.levels.INFO)
  if new_chat then
    chat.turns = new_chat.turns
  end
end

--- Loads chats from the chats directory.
---
---@return Chat[] result A list of Chat objects sorted by filename (oldest first).
function M.load_chats()
  local result = {} ---@type Chat[]

  -- Load all chat files
  local glob_pattern = Config.chats_dir .. "/*.chat.jsonl"
  local chat_files = vim.fn.glob(glob_pattern, false, true)
  for _, file_path in ipairs(chat_files) do
    local chat = load_chat(file_path)
    if chat then
      table.insert(result, chat)
    end
  end

  -- Sort by filename (oldest first since timestamp format is YYYYMMDD_HHMMSS)
  table.sort(result, function(a, b)
    return a.filename < b.filename
  end)

  return result
end

local function get_chat_index(chat)
  return utils.index_of(State.chats, chat)
end

--- Delete a chat from State.chats and delete the chat file.
---@param chat Chat The chat to delete.
local function delete_chat(chat)
  local i = get_chat_index(chat)
  assert(i ~= nil, "chat not found in State.chats")
  if chat.filename then
    utils.delete_file(chat.filename)
  end
  table.remove(State.chats, i)
end

--- Saves the chat table to a JSONL file.
---@param chat Chat
function M.save_chat(chat)
  local dir = Config.chats_dir

  -- Determine the filename
  if not chat.filename then
    local timestamp = os.date "%Y%m%d_%H%M%S"
    -- Store the full expanded path in the chat object
    chat.filename = dir .. "/" .. timestamp .. ".chat.jsonl"
  end

  -- Ensure the directory exists
  if vim.fn.isdirectory(dir) == 0 then
    utils.notify("Creating chats directory: " .. dir, vim.log.levels.INFO)
    vim.fn.mkdir(dir, "p")
  end

  -- Prepare the JSONL content
  local lines = {}
  for _, turn in ipairs(chat.turns) do
    local ok, json = pcall(vim.json.encode, turn)
    if ok then
      json:gsub("[\r\n]", " ") -- Ensure single line JSONL format
      table.insert(lines, json)
    end
  end

  -- Write to the chat file
  local file = io.open(chat.filename, "w")
  if not file then
    -- This will now trigger if the path expansion failed or permissions are off
    utils.notify("Failed to open file '" .. chat.filename .. "'", vim.log.levels.ERROR)
    return
  end

  file:write(table.concat(lines, "\n") .. "\n")
  file:close()

  utils.notify("Saved file '" .. chat.filename .. "'", vim.log.levels.INFO)

  -- Record the mostly recently updated chat file name
  M.set_recent_chat_file(chat.filename)

end

--- Set the most recently updated chat file in saved state.
---@param chat_file string Path to the chat file.
function M.set_recent_chat_file(chat_file)
  State.saved_state.chat_file = chat_file
  State.save_state()
end

--- Returns the full path of the most recently updated chat file
---@return string|nil The most recently updated chat file path, or nil if not set.
function M.recent_chat_file()
  return State.saved_state.chat_file
end

---@param chat Chat
---@param turn Turn
---@return number|nil index The 1-based index of the turn, or nil if not found.
local function get_turn_index(chat, turn)
  return utils.index_of(chat.turns, turn)
end

---@param chat Chat
---@param turn Turn
---@return Turn|nil next_turn The next turn, or nil if at end.
local function get_next_turn(chat, turn)
  local index = get_turn_index(chat, turn)
  if index and index < #chat.turns then
    return chat.turns[index + 1]
  else
    return nil
  end
end

---@param chat Chat
---@param turn Turn
---@return Turn|nil prev_turn The previous turn, or nil if at start.
local function get_prev_turn(chat, turn)
  local index = get_turn_index(chat, turn)
  if index and index > 1 then
    return chat.turns[index - 1]
  else
    return nil
  end
end

--- Return the next chat or `nil` if at there are no chats or at last chat.
---@param chat Chat The current chat
---@return Chat|nil next_chat
local function get_next_chat(chat)
  local i = get_chat_index(chat)
  assert(i ~= nil)
  if i == #State.chats then
    return nil
  end
  return State.chats[i + 1]
end

--- Return the previous chat or `nil` if at there are no chats or at first chat.
---@param chat Chat The current chat
---@return Chat|nil prev_chat
local function get_prev_chat(chat)
  local i = get_chat_index(chat)
  assert(i ~= nil)
  if i == 1 then
    return nil
  end
  return State.chats[i - 1]
end

-- If `turn` is the current Chat window turn unbind it and bind the last turn.
local function unbind_turn(turn)
  if turn == State.chat_window.turn then
    State.chat_window.turn = nil
    if State.chat_window:is_open() then
      M.open_chat()
    end
  end
end

--- Delete a turn from a chat. Invalidate chat window turn.
---@param chat Chat The chat to modify.
---@param turn Turn The turn to delete.
local function delete_turn(chat, turn)
  assert(chat)
  assert(turn)
  table.remove(chat.turns, get_turn_index(chat, turn))
  unbind_turn(turn)
  if #chat.turns == 0 then
    -- Once the last turn has been deleted, delete the chat file
    delete_chat(chat)
  else
    M.save_chat(chat)
  end
end

--- Delete old chats, retaining the most recent ones.
---
--- State.chats is assumed to be sorted by filename (oldest first).
---
---@param number_retained number Number of most recent chats to retain.
function M.delete_old_chats(number_retained)
  -- Delete the oldest chats (first ones in sorted array), keeping the most recent
  local deleted_count = 0
  local delete_up_to = #State.chats - number_retained
  for _ = 1, delete_up_to do
    local chat = State.chats[1]
    if chat and chat.filename then
      if utils.delete_file(chat.filename) then
        table.remove(State.chats, 1)
        deleted_count = deleted_count + 1
      end
    end
  end

  -- If the chat in the Chat window chat was deleted then attach a new blank chat
  if not get_chat_index(State.chat_window.chat) then
    M.new_chat()
    if State.chat_window:is_open() then
      M.open_chat()
    end
  end

  if deleted_count > 0 then
    utils.notify("Deleted " .. deleted_count .. " old chat(s)", vim.log.levels.INFO)
  else
    utils.notify("No old chats deleted", vim.log.levels.INFO)
  end
end

---Open chat window at the `chat` `turn`.
---If the chat window does not exist, create it and attach key-mapped commands.
---@param chat Chat?
---@param turn Turn?
function M.open_chat(chat, turn)
  local win = State.chat_window
  if chat then
    win.chat = chat
  end
  assert(win.chat)
  win.turn = turn or win.turn or win.chat.turns[#win.chat.turns]
  win:open()
  win:set_title("Chat [" .. Config.help_key .. " help]")

  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  M.add_chat_syntax_highlighting(win.bufnr)
  if win.turn then
    local lines = M.turn_to_lines(win.chat, win.turn)
    win:set_lines(lines)
  else
    win:set_lines { "" }
  end

  -- Auto-command to abort the current request if the Chat window is closed
  local group = vim.api.nvim_create_augroup("_qanda_WinClosed_", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win.winid),
    callback = function()
      if curl.is_active_job() then
        curl.kill_command()
        utils.notify("Request aborted because Chat window closed", vim.log.levels.INFO)
      end
    end,
  })

  -- Attach key commands.
  vim.keymap.set({ "n", "v" }, Config.chat_close_key, function()
    if curl.active_job_warning() then
      return
    end
    win:close()
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_abort_key, function()
    curl.kill_command()
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_switch_key, function()
    if curl.active_job_warning() then
      return
    end
    vim.cmd "Qanda /prompt_window"
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_prompt_key, function()
    if curl.active_job_warning() then
      return
    end
    require("qanda.prompts").open_prompt {
      name = nil,
      content = (win.turn or {}).request,
      model_options = (win.turn or {}).model_options,
    }
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_new_prompt_key, function()
    if curl.active_job_warning() then
      return
    end
    -- Open a blank Prompt window
    require("qanda.prompts").open_prompt { content = "" }
    -- Go to insert mode
    vim.cmd "startinsert"
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_prev_turn_key, function()
    if curl.active_job_warning() then
      return
    end
    if win.turn then
      local t = get_prev_turn(win.chat, win.turn)
      if t then
        M.open_chat(win.chat, t)
      end
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_next_turn_key, function()
    if curl.active_job_warning() then
      return
    end
    if win.turn then
      local t = get_next_turn(win.chat, win.turn)
      if t then
        M.open_chat(win.chat, t)
      end
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_prev_chat_key, function()
    if curl.active_job_warning() then
      return
    end
    local c = get_prev_chat(win.chat)
    if c then
      M.open_chat(c, c.turns[#c.turns]) -- Open chat at last turn
    else
      utils.notify("No previous chat", vim.log.levels.WARN)
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_next_chat_key, function()
    if curl.active_job_warning() then
      return
    end
    local c = get_next_chat(win.chat)
    if c then
      M.open_chat(c, c.turns[#c.turns]) -- Open chat at last turn
    else
      utils.notify("No next chat", vim.log.levels.WARN)
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_delete_key, function()
    if curl.active_job_warning() then
      return
    end
    delete_turn(win.chat, win.turn)
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_edit_key, function()
    if curl.active_job_warning() then
      return
    end
    if win.chat.filename then
      local timestamp = win.turn.timestamp
      win:close() -- So we don't open the chat file in the Chat window
      utils.edit_file(
        win.chat.filename,
        M.add_chat_syntax_highlighting,
        '"timestamp":%s*"' .. utils.escape_pattern(timestamp) .. '"',
        function()
          -- Update chat after edited file is saved
          refresh_chat(win.chat) -- Update chat after edited file is saved
          win.turn = nil -- Invalidate the Chat window turn after editing it
        end
      )
    else
      utils.notify("Chat file does not exist (the conversation has not begun)", vim.log.levels.WARN)
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.chat_redo_key, function()
    if curl.active_job_warning() then
      return
    end
    if #win.chat.turns == 0 then
      utils.notify("Empty chat, there is nothing to redo", vim.log.levels.WARN)
      return
    end

    -- Delete the most recent turn and re-execute it
    local most_recent_turn = table.remove(win.chat.turns)
    win.turn = nil
    M.open_chat()
    require("qanda.prompts").open_prompt {
      content = most_recent_turn.request,
      model_options = most_recent_turn.model_options,
    }
  end, { buffer = win.bufnr })

  -- Toggle chat display fields
  vim.keymap.set({ "n", "v" }, Config.chat_truncate_key, function()
    if curl.active_job_warning() then
      return
    end
    M.turn_truncation = not M.turn_truncation
    local lines = M.turn_to_lines(win.chat, win.turn)
    win:set_lines(lines)
  end, { buffer = win.bufnr })

  -- Copy chat window response to system clipboard
  vim.keymap.set({ "n", "v" }, Config.chat_copy_key, function()
    if curl.active_job_warning() then
      return
    end
    if win.turn then
      local response = win.turn.response
      if response and response ~= "" then
        vim.fn.setreg("+", response)
        utils.notify("Model response copied to clipboard", vim.log.levels.INFO)
      end
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v" }, Config.help_key, function()
    if curl.active_job_warning() then
      return
    end
    local help_message = ([[-- Chat Window Commands --

Normal mode commands:

- %s - Open the turn's prompt in the Prompt window
- %s - Switch to the Prompt window
- %s - Open a blank Prompt window in insert mode
- %s - Copy the turn response to clipboard
- %s - Close the Chat window
- %s - Abort the current request
- %s - Delete the current turn, if it is the last turn delete the chat
- %s - Open the chat file in the editor at the current turn
- %s/%s - Go to next/previous turn
- %s/%s - Go to next/previous chat
- %s - Delete the latest turn from the chat and open its prompt in the Prompt window
- %s - Toggle truncated prompt and system message fields

]]):format(
      Config.chat_prompt_key,
      Config.chat_switch_key,
      Config.chat_new_prompt_key,
      Config.chat_copy_key,
      Config.chat_close_key,
      Config.chat_abort_key,
      Config.chat_delete_key,
      Config.chat_edit_key,
      Config.chat_next_turn_key,
      Config.chat_prev_turn_key,
      Config.chat_next_chat_key,
      Config.chat_prev_chat_key,
      Config.chat_redo_key,
      Config.chat_truncate_key
    )
    utils.notify(help_message, vim.log.levels.INFO)
  end, { buffer = win.bufnr, desc = "Show Chat window help" })
end

-- Assign a new empty chat to the Chat window.
function M.new_chat()
  local new_chat = { turns = {} }
  local win = State.chat_window
  win.chat = new_chat
  win.turn = nil
end

---@param chat Chat
---@param turn Turn
---@return string[]
function M.turn_to_lines(chat, turn)
  assert(chat)
  assert(turn)

  local lines = {}
  local rule = string.rep("_", 3)

  ---Helper to limit lines, handle Markdown integrity, and add truncation marker
  ---@param label string
  ---@param content string|nil
  ---@param max_lines number
  ---@return string[]
  local get_limited_lines = function(label, content, max_lines)

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
      table.insert(processed, line)
    end

    utils.trim_table(processed)

    if truncated then
      if in_code_block then
        table.insert(processed, "```")
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
  if turn.duration then
    table.insert(lines, "duration: " .. string.format("%.2fs", turn.duration))
  end
  if turn.total_tokens then
    table.insert(lines, string.format("tokens: %d", turn.total_tokens))
  end
  if turn.model_options then
    for k, v in pairs(turn.model_options) do
      table.insert(lines, k .. ": " .. v)
    end
  end
  table.insert(lines, string.format("turn: %d of %d", get_turn_index(chat, turn), #chat.turns))

  local max_lines
  if turn.system then
    max_lines = not M.turn_truncation and 999 or Config.system_message_lines
    local system_lines = get_limited_lines("system", turn.system, max_lines)
    vim.list_extend(lines, system_lines)
    table.insert(lines, "")
  end

  max_lines = not M.turn_truncation and 999 or Config.user_prompt_lines
  local request_lines = get_limited_lines("prompt", turn.request, max_lines)
  vim.list_extend(lines, request_lines)
  table.insert(lines, "")

  table.insert(lines, rule)
  for _, v in ipairs(vim.split(utils.trim_string(turn.response or ""), "\n")) do
    table.insert(lines, v)
  end
  return lines
end

local chat_syntax_rules = {
  QandaChatProperty = [[\v^(provider|timestamp|duration|tokens|prompt|system|model|provider|turn|temperature|top_p|max_tokens|stream):]],
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

--- Open a Telescope picker to select and manage chats.
function M.chat_picker()
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"
  local conf = require("telescope.config").values

  local current_chat = State.chat_window.chat
  assert(current_chat)
  local mutated = false

  -- Display entry function
  local display_entry = function(chat)
    local chat_name = M.chat_name(chat)
    if chat.filename == State.chat_window.chat.filename then
      return "* " .. chat_name
    else
      return "  " .. chat_name
    end
  end

  local get_picker_entries = function()
    local picker_entries = {}
    -- Iterate in reverse order since State.chats is sorted oldest-first
    for i = #State.chats, 1, -1 do
      table.insert(picker_entries, State.chats[i])
    end
    return picker_entries
  end

  local entry_maker = function(chat)
    local displayed_name = display_entry(chat)
    return {
      value = chat,
      display = displayed_name,
      ordinal = displayed_name,
    }
  end

  local delete_entry = function(picker_bufnr)
    local current_picker = action_state.get_current_picker(picker_bufnr)

    current_picker:delete_selection(function(selection)
      if selection then
        local chat = selection.value
        delete_chat(chat)
        mutated = true
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
        if mutated then
          -- One or more chats have been deleted
          if State.chat_window.chat == current_chat and not get_chat_index(current_chat) then
            -- The Chat window chat has been deleted so switch to the most recent chat
            State.chat_window.chat = State.chats[#State.chats]
            State.chat_window.turn = nil
          end
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
      end
    end, { desc = "Close the picker and open the chat in the Chat window" })

    map({ "n", "i" }, Config.chat_picker_turns_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local chat = selection.value
        M.turns_picker(chat)
      end
    end, { desc = "Open the chat in the Turn picker" })

    map({ "n", "i" }, Config.chat_picker_delete_key, function()
      delete_entry(picker_bufnr)
    end, { desc = "Delete the selected chat file" })

    map({ "n", "i" }, Config.chat_picker_rename_key, function()
      local selection = action_state.get_selected_entry()
      if not selection then
        return
      end

      local chat = selection.value
      local new_name = vim.fn.input("Enter chat name: ", M.chat_name(chat))
      if new_name == "" then
        return -- User cancelled
      end

      -- Update and persist
      chat.turns[1].chat = new_name
      M.save_chat(chat)

      -- Refresh picker
      local picker = action_state.get_current_picker(picker_bufnr)
      picker:refresh(
        finders.new_table {
          results = get_picker_entries(),
          entry_maker = entry_maker,
        },
        { reset_prompt = false }
      )
    end, { desc = "Rename the selected chat" })

    map({ "n", "i" }, Config.chat_picker_edit_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local chat = selection.value
        assert(chat)
        assert(chat.filename)
        actions.close(picker_bufnr)
        State.chat_window:close() -- So we don't open the chat file in the Chat window
        utils.edit_file(chat.filename, M.add_chat_syntax_highlighting, nil, function()
          -- Update chat after edited file is saved
          refresh_chat(chat)
          if State.chat_window.chat == chat then
            State.chat_window.turn = nil -- Invalidate the Chat window turn after editing it
          end
        end)
      end
    end, { desc = "Close the picker and edit chats file containing the selected chat" })

    map({ "n", "i" }, Config.help_key, function()
      local help_message = ([[-- Chat Picker Commands --

- %s - Open the selected chat in Chat window
- %s - Open the selected chat in the Turn picker
- %s - Delete the selected chat
- %s - Rename the selected chat
- %s - Edit the chat file

]]):format(
        Config.chat_picker_open_key,
        Config.chat_picker_turns_key,
        Config.chat_picker_delete_key,
        Config.chat_picker_rename_key,
        Config.chat_picker_edit_key
      )
      vim.notify(help_message, vim.log.levels.INFO)
    end, { buffer = picker_bufnr, desc = "Show Chat picker help" })

    return true
  end

  -- Previewer that lists the chat turns
  local turns_list_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local chat = entry.value
      assert(chat)

      local preview_lines = {}

      if #chat.turns == 1 then
        preview_lines = M.turn_to_lines(chat, chat.turns[1])
        vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
        M.add_chat_syntax_highlighting(self.state.bufnr)
      else
        for _, turn in ipairs(chat.turns) do
          local line = utils.sanitize_display_entry(turn.request, 80)
          table.insert(preview_lines, line)
        end
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)

    end,
  }

  -- Find the default selection index (entries are in reverse order: most recent first)
  local default_selection_index = 1
  local picker_entries = get_picker_entries()
  for i, chat in ipairs(picker_entries) do
    if chat == current_chat then
      default_selection_index = i
      break
    end
  end

  -- Create and run the telescope picker
  pickers
    .new({}, {
      results_title = "Chats",
      preview_title = "Turns",
      prompt_title = "[" .. Config.help_key .. " help]",
      default_selection_index = default_selection_index,
      finder = finders.new_table {
        results = picker_entries,
        entry_maker = entry_maker,
      },
      sorter = conf.generic_sorter {},
      previewer = turns_list_previewer,
      attach_mappings = mappings,
      layout_config = Config.chat_picker_layout,
    })
    :find()

end

--- Generate a display name for a chat.
---@param chat Chat The chat to name.
---@return string name The chat name.
function M.chat_name(chat)
  return chat.turns[1].chat or utils.sanitize_display_entry(chat.turns[1].request, 60)
end

--- Open a Telescope picker to select and manage turns.
---@param chats? Chat | Chats Chats containing the picker turns
function M.turns_picker(chats)
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"
  local conf = require("telescope.config").values

  -- Handle both single Chat and Chats array
  local chats_list ---@type Chat[]
  if chats and chats[1] then
    -- It's a Chats array
    chats_list = chats
  elseif chats and chats.turns then
    -- It's a single Chat
    chats_list = { chats }
  else
    -- Default to current chat
    chats_list = { State.chat_window.chat }
  end

  local mutated = false
  local current_turn = State.chat_window.turn

  local delete_entry = function(picker_bufnr)
    local current_picker = action_state.get_current_picker(picker_bufnr)

    current_picker:delete_selection(function(selection)
      if selection then
        local turn = selection.value
        local parent_chat = selection.chat
        table.remove(parent_chat.turns, get_turn_index(parent_chat, turn))
        mutated = true
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
        if mutated then
          for _, chat in ipairs(chats_list) do
            if #chat.turns == 0 then
              -- All turns have been deleted so delete the parent chat
              delete_chat(chat)
              if State.chat_window.chat == chat then
                State.chat_window.chat = State.chats[#State.chats]
                State.chat_window.turn = nil
              end
            else
              M.save_chat(chat)
            end
          end
          -- Handle case where current turn was deleted
          local current_chat = State.chat_window.chat
          local current_turn_ref = State.chat_window.turn
          if current_turn and current_chat and current_turn_ref then
            if not get_turn_index(current_chat, current_turn_ref) then
              -- The Chat window turn has been deleted so switch to the most recent turn
              local last_turn = current_chat.turns[#current_chat.turns]
              if last_turn then
                State.chat_window.turn = last_turn
              end
            end
          end
          if State.chat_window:is_open() then
            M.open_chat()
          end
        end
      end,
    })

    -- Key commands
    map({ "n", "i" }, Config.turn_picker_open_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(picker_bufnr)
      if selection then
        M.open_chat(selection.chat, selection.value)
      end
    end, { desc = "Close the picker and open the selected turn in the chat window" })

    map({ "n", "i" }, Config.turn_picker_prompt_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(picker_bufnr)
      if selection then
        local selected_turn = selection.value
        require("qanda.prompts").open_prompt {
          name = nil,
          content = selected_turn.request,
          model_options = selected_turn.model_options,
        }
      end
    end, { desc = "Close the picker and open the selected turn's prompt in the prompt window" })

    map({ "n", "i" }, Config.turn_picker_delete_key, function()
      delete_entry(picker_bufnr)
    end, { desc = "Delete the selected turn" })

    map({ "n", "i" }, Config.turn_picker_truncate_key, function()
      -- Toggle the shared truncation flag
      M.turn_truncation = not M.turn_truncation

      -- Get current picker + selection
      local picker = action_state.get_current_picker(picker_bufnr)
      local selection = action_state.get_selected_entry()
      if not selection then
        return
      end

      -- Re-render preview
      local previewer = picker.previewer
      if previewer and previewer.state and previewer.state.bufnr then
        local lines = M.turn_to_lines(selection.chat, selection.value)

        if #lines == 0 then
          lines = { "**[No content available for this turn]**" }
        end

        vim.api.nvim_buf_set_lines(previewer.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "markdown", { buf = previewer.state.bufnr })
        M.add_chat_syntax_highlighting(previewer.state.bufnr)
      end

    end, { desc = "Toggle truncated fields in preview" })

    map({ "n", "i" }, Config.help_key, function()
      local help_message = ([[-- Turn Picker Commands --

- %s - Open the selected turn in the Chat window
- %s - Open the selected turn in the Prompt window
- %s - Delete the selected turn
- %s - Toggle truncated fields in the Preview

]]):format(Config.turn_picker_open_key, Config.turn_picker_prompt_key, Config.turn_picker_delete_key, Config.turn_picker_truncate_key)
      vim.notify(help_message, vim.log.levels.INFO)
    end, { buffer = picker_bufnr, desc = "Show Turn picker help" })

    return true
  end

  -- Build picker entries by concatenating turns from all chats (chronological order)
  -- Then reverse so oldest is at top and latest is at bottom
  local picker_entries = {} ---@type { value: Turn, chat: Chat }[]
  for _, chat in ipairs(chats_list) do
    for _, turn in ipairs(chat.turns) do
      table.insert(picker_entries, { value = turn, chat = chat })
    end
  end
  -- Reverse to show oldest first at top
  for i = 1, math.floor(#picker_entries / 2) do
    picker_entries[i], picker_entries[#picker_entries - i + 1] = picker_entries[#picker_entries - i + 1], picker_entries[i]
  end

  -- Display entry function
  local display_entry = function(entry)
    local turn = entry.value
    local display = utils.sanitize_display_entry(turn.request, 60)
    local prefix = "  "
    if current_turn and turn == current_turn then
      prefix = "* "
    end
    return prefix .. display
  end

  -- Create previewer that shows the turn value
  local turn_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local lines = M.turn_to_lines(entry.chat, entry.value)

      if #lines == 0 then
        table.insert(lines, "**[No content available for this turn]**")
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_chat_syntax_highlighting(self.state.bufnr)
    end,
  }

  -- Find the default selection index
  local default_selection_index = 1
  if current_turn then
    for i, entry in ipairs(picker_entries) do
      if entry.value == current_turn then
        default_selection_index = i
        break
      end
    end
  end

  -- Create and run the telescope picker
  pickers
    .new({}, {
      results_title = "Turns",
      preview_title = "Preview",
      prompt_title = "[" .. Config.help_key .. " help]",
      default_selection_index = default_selection_index,
      finder = finders.new_table {
        results = picker_entries,
        entry_maker = function(entry)
          local displayed_name = display_entry(entry)
          return {
            value = entry.value,
            chat = entry.chat,
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
