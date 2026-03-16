local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"
local ui = require "qanda.ui"
local curl = require "qanda.curl"

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
    local chat_file = M.recent_chat_file(Config.chats_dir)
    if chat_file then
      local chats = M.load_chats(chat_file)
      if #chats == 1 then
        State.chats = chats
        State.chat_window.chat = chats[1]
        if M.chat_has_system_prompt(chats[1], State.system_prompt.expanded) then
          State.system_prompt.consumed = true
        end
      end
    end
  end
end

--- Checks if any turn in the chat has a system prompt matching the given string.
---@param chat Chat The chat object to search.
---@param prompt string The system prompt string to look for.
---@return boolean found Returns true if a match is found, otherwise false.
function M.chat_has_system_prompt(chat, prompt)
  for _, turn in ipairs(chat.turns) do
    -- Check if the system field exists and matches the target prompt
    if turn.system == prompt then
      return true
    end
  end
  return false
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

--- Loads chats. If chat_file is provided, loads only that file.
--- Otherwise, scans Config.chats_dir for all .chat.jsonl files.
---@param chat_file string? Optional specific file to load
---@return Chat[] result A list of Chat objects
function M.load_chats(chat_file)
  local result = {} ---@type Chat[]
  local chat_files = {}

  -- 1. Determine which files to load
  if chat_file then
    table.insert(chat_files, vim.fn.expand(chat_file))
  else
    local chats_dir = vim.fn.expand(Config.chats_dir)
    local glob_pattern = chats_dir .. "/*.chat.jsonl"
    chat_files = vim.fn.glob(glob_pattern, false, true)
  end

  -- 2. Process the files
  local chat_window_updated = false
  for _, file_path in ipairs(chat_files) do
    if vim.fn.filereadable(file_path) == 1 then
      local lines = vim.fn.readfile(file_path)
      if lines and #lines > 0 then
        local turns = parse_turns(lines)
        if turns and #turns > 0 then
          local chat = { turns = turns, filename = file_path }
          table.insert(result, chat)

          -- Update active state if this file matches the current window's chat
          if State.chat_window.chat and State.chat_window.chat.filename == file_path then
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

  -- 3. Invalidate chat window if no match was found during a full load
  -- (We usually only want to invalidate if we're doing a fresh directory scan)
  if not chat_file and not chat_window_updated then
    State.chat_window.chat = { turns = {} }
    State.chat_window.turn_index = nil
  end

  return result
end

--- Saves the chat table to a JSONL file.
---@param chat Chat
---@param dir string
function M.save_chat(chat, dir)
  -- Expand the directory path (handles ~, $HOME, etc.)
  local expanded_dir = vim.fn.expand(dir)

  -- 1. Determine the filename
  if not chat.filename then
    local timestamp = os.date "%Y%m%d_%H%M%S"
    -- Store the full expanded path in the chat object
    chat.filename = expanded_dir .. "/" .. timestamp .. ".chat.jsonl"
  else
    -- Ensure an existing filename is also expanded if it contains ~
    chat.filename = vim.fn.expand(chat.filename)
  end

  -- 2. Ensure the directory exists
  if vim.fn.isdirectory(expanded_dir) == 0 then
    vim.fn.mkdir(expanded_dir, "p")
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

  -- 5. Update the MOST_RECENT_CHAT file
  local recent_file_path = expanded_dir .. "/MOST_RECENT_CHAT"
  local recent_file = io.open(recent_file_path, "w")
  if recent_file then
    -- We only want the base name (e.g., '20260316_170707.chat.jsonl') in this file
    local base_name = vim.fn.fnamemodify(chat.filename, ":t")
    recent_file:write(base_name .. "\n")
    recent_file:close()
  end

end

--- Returns the full path of the most recent chat file recorded in MOST_RECENT_CHAT.
---@param dir string The directory to look in.
---@return string? path The absolute path to the chat file, or nil if not found/invalid.
function M.recent_chat_file(dir)
  -- 1. Expand the directory to ensure we have a valid system path
  local expanded_dir = vim.fn.expand(dir)
  local recent_chat_pointer = expanded_dir .. "/MOST_RECENT_CHAT"

  -- 2. Attempt to open and read the pointer file
  local file = io.open(recent_chat_pointer, "r")
  if not file then
    return nil
  end

  -- Read the first line and trim whitespace/newlines
  local filename = file:read "*l"
  file:close()

  if not filename or filename == "" then
    return nil
  end

  filename = vim.trim(filename)

  -- 3. Synthesize the full path
  local full_path = expanded_dir .. "/" .. filename

  -- 4. Verify the recorded chat file actually exists on disk
  if vim.fn.filereadable(full_path) == 0 then
    return nil
  end

  return full_path
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
  win.turn_index = turn_index or win.turn_index or #win.chat.turns
  win:open()
  win:set_title("Chat [" .. Config.help_key .. " help]")

  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  M.add_chat_syntax_highlighting(win.bufnr)
  if win.turn_index and win.turn_index > 0 then
    assert(win.turn_index <= #win.chat.turns)
    local lines = M.turn_to_lines(win.chat, win.turn_index)
    win:set_lines(lines)
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
  vim.keymap.set("n", Config.chat_exec_key, function()
    local turn = win.chat.turns[win.turn_index or #win.chat.turns]
    require("qanda.prompts").open_prompt {
      model_options = turn.model_options,
      extract = turn.extract,
      prompt = turn.request,
    }
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.chat_prev_key, function()
    if win.turn_index and win.turn_index > 1 then
      M.open_chat(win.chat, win.turn_index - 1)
    end
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.chat_next_key, function()
    if win.turn_index and win.turn_index < #win.chat.turns then
      M.open_chat(win.chat, win.turn_index + 1)
    end
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.chat_edit_key, function()
    if win.chat.filename then
      win:close()
      local timestamp = win.chat.turns[win.turn_index].timestamp
      utils.edit_file(
        win.chat.filename,
        M.add_chat_syntax_highlighting,
        '"timestamp":%s*"' .. utils.escape_pattern(timestamp) .. '"',
        function()
          State.chats = M.load_chats() -- Reload chats after edited file is saved
        end
      )
    else
      utils.notify("Chat file does not exist (the conversation has not begun)", vim.log.levels.INFO)
    end
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.chat_redo_key, function()
    ---@todo TODO: Do we need redo ???
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.help_key, function()
    local content = ([[## Chat Window Cheatsheet

- `%s` - Create a new prompt from the current Chat window prompt
- `%s` - Switch to Prompt window
- `%s`/`%s` Scroll up/down for previous/next prompt (from the current chat message)
- `%s` - Open the chat file for editing at the selected turn (by searching for the timestamp)
- `%s` - Re-execute and replace the latest turn.
- `%s` - Abort the current request
- `%s` - Close Chat window.
]]):format(
      Config.chat_exec_key,
      Config.chat_switch_key,
      Config.chat_prev_key,
      Config.chat_next_key,
      Config.chat_edit_key,
      Config.chat_redo_key,
      Config.chat_abort_key,
      Config.chat_close_key
    )
    ui.open_foreground_float(vim.split(content, "\n"), { width = 100 })
  end, { buffer = win.bufnr, desc = "Show prompt window help" })
end

function M.new_chat()
  local turn = {
    request = "",
    provider = State.provider.name,
    model = State.provider.model,
  }
  local new_chat = { turns = { turn } }

  -- Bind the chat to the Chat window
  M.open_chat(new_chat, 1)

  -- Include the system prompt in the first turn
  if State.system_prompt then
    State.system_prompt.consumed = false
  end

end

---@param chat Chat
---@param turn_index number
---@return string[]
function M.turn_to_lines(chat, turn_index)
  local turn = chat.turns[turn_index]
  local lines = {}
  local rule = string.rep("_", 40)

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
  table.insert(lines, string.format("turn: %d of %d", turn_index, #chat.turns))
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

      local lines = M.turn_to_lines(chat, #chat.turns)

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_chat_syntax_highlighting(self.state.bufnr)
    end,
  }

  -- Create and run the telescope picker
  pickers
    .new({}, {
      results_title = "Chats",
      prompt_title = "[<Enter> open, " .. Config.chat_picker_edit_key .. " edit, " .. Config.chat_picker_delete_key .. " delete]",
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

    map({ "n", "i" }, Config.chat_picker_open_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(chat_bufnr)
      if selection then
        local chat = selection.value
        assert(chat)
        M.open_chat(chat)
      else
        utils.notify("User cancelled", vim.log.levels.INFO)
      end
    end, { desc = "Close the picker and open the chat in the chat window" })

    map({ "n", "i" }, Config.chat_picker_delete_key, function()
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
    end, { desc = "Close the picker and delete the selected chat file" })

    map({ "n", "i" }, Config.chat_picker_edit_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local chat = selection.value
        assert(chat)
        assert(chat.filename)
        actions.close(chat_bufnr)
        utils.edit_file(chat.filename, M.add_chat_syntax_highlighting, nil, function()
          State.chats = M.load_chats() -- Reload chats after edited file is saved
        end)
      end
    end, { desc = "Close the picker and edit chats file containing the selected chat" })

    return true
  end, function(chat)
    local display_entry = utils.truncate_string(chat.turns[1].request, 20)
    if chat.filename == State.chat_window.chat.filename then
      return "* " .. display_entry
    else
      return "  " .. display_entry
    end
  end)
end

return M
