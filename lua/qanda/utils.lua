local M = {} -- This module

--- Strip leading and trailing whitespace from a string
--- @param s string The input string to trim
--- @return string The trimmed string
function M.trim_string(s)
  return s:match "^%s*(.-)%s*$"
end

--- Escapes special characters in a string
--- @param s string The string to escape
--- @return string The escaped string
function M.escape_string(s)
  local map = {
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\\"] = "\\\\",
    ['"'] = '\\"',
    ["'"] = "\\'",
  }
  return (s:gsub("[\n\r\t\\\"']", function(char)
    return map[char] or char
  end))
end

--- Unescapes escape sequences in a string
--- @param s string The string to unescape
--- @return string The unescaped string
function M.unescape_string(s)
  local map = {
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t",
    ["\\"] = "\\",
    ['"'] = '"',
    ["'"] = "'",
  }
  return (s:gsub("\\(.)", function(char)
    return map[char] or char
  end))
end

-- Escape special characters in Lua regular expressions
function M.escape_pattern(text)
  -- Matches any of: ^ $ ( ) % . [ ] * + - ?
  -- And prefixes them with a %
  return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Clear a Lua array table (sequence)
function M.clear_sequence(s)
  for i = #s, 1, -1 do
    s[i] = nil
  end
end

--- Returns the number of elements in a table
-- @param tbl table: The table to count elements in
-- @return number: The count of elements in the table
function M.table_size(tbl)
  local count = 0
  for _ in ipairs(tbl) do
    count = count + 1
  end
  return count
end

--- Check if a table contains a specific string value.
--- @param arr table The array-like table to search through.
--- @param str string The string value to look for.
--- @return boolean # Returns true if found, false otherwise.
function M.table_contains(arr, str)
  for _, v in ipairs(arr) do
    if v == str then
      return true
    end
  end
  return false
end

---Search an array for the first element where the `match` function returns `true`, then replace the element with the `item` element.
---@param array table<number, table> Array of tables to search
---@param item any The item table to insert or use for replacement
---@param match fun(element: any, item: any): boolean Function returning true if element should be replaced by item
function M.insert_replace(array, item, match)
  for i, element in ipairs(array) do
    if match(element, item) then
      array[i] = item
      return
    end
  end
  table.insert(array, item)
end

--- Set multiple keymaps at once from a list of mode/lhs pairs.
--- @param mode_lhs_list table[] A list of tables, where each sub-table is {mode, lhs}.
--- @param rhs string|function The command or function to execute.
--- @param opts? table Optional mapping options (e.g., { silent = true }).
function M.map_many(mode_lhs_list, rhs, opts)
  for _, v in ipairs(mode_lhs_list) do
    vim.keymap.set(v[1], v[2], rhs, opts)
  end
end

--- Wrapped `vim.notify`.
function M.notify(msg, ...)
  vim.schedule_wrap(vim.notify)("qanda.nvim: " .. msg, ...)
end

--- Reads the entire content of a file into a string.
---
--- @param filepath string The path to the file to be read.
--- @return string|nil content The file contents if successful, or nil if an error occurred.
--- @return string|nil error_message An error message if the file could not be opened, otherwise nil.
function M.read_file_to_string(filepath)
  filepath = vim.fn.expand(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: '" .. filepath .. "'"
  end
  local content = file:read "*all"
  file:close()
  return content
end

function M.write_string_to_file(str, fname, mode)
  mode = mode or "w" -- Replace file contents by default
  fname = vim.fn.expand(fname)
  local f, err = io.open(fname, mode)
  if f then
    f:write(str)
    f:close()
    return true
  else
    M.notify("Error opening '" .. fname .. "': " .. (err or "unknown error"), vim.log.levels.ERROR)
    return false
  end
end

function M.append_string_to_file(str, fname)
  return M.write_string_to_file(str, fname, "a+")
end

--- Display a message using vim's echo interface
--- Shows a message in the command line area with optional highlighting.
--- This function wraps vim.api.nvim_echo with simplified parameter handling.
--- @param msg string The message text to display
--- @param opts table|nil Optional configuration table forwarded to vim.api.nvim_echo
--- @param opts.hl_group string Highlight group name for the message (default: "Normal")
--- @param opts.history boolean Whether to save the message to command history (default: false)
--- @param opts.* any Additional options passed directly to vim.api.nvim_echo
--- @usage
--- M.message("Hello World")  -- displays with Normal highlight
--- M.message("Error occurred", {hl_group = "ErrorMsg"})  -- displays with ErrorMsg highlight
--- M.message("Command output", {history = true})  -- saves to command history
function M.message(msg, opts)
  opts = opts or {}
  -- Copy `opts` to `echo_opts` and delete non vim.api.nvim_echo options
  local echo_opts = vim.tbl_deep_extend("force", {}, opts)
  echo_opts.hl_group = nil
  echo_opts.history = nil
  vim.schedule(function() -- Defer because of Neovim's "fast event" context
    vim.api.nvim_echo({ { msg, opts.hl_group or "Normal" } }, opts.history or false, echo_opts)
  end)
end

vim.cmd [[
    highlight default QandaSpinner  gui=NONE  cterm=NONE  guifg=#a6e3a1 ctermfg=157
]]

--- Display a notification message with an animated spinner
--- Creates a visual spinner animation that runs while processing occurs,
--- and returns a function to stop the animation and display a completion message.
--- The spinner uses Unicode braille characters for smooth animation.
--- @param message string The message to display alongside the spinner
--- @param opts table|nil Optional configuration table forwarded to M.message
--- @param opts.interval number Animation frame interval in milliseconds (default: 100)
--- @return function A stop function that halts the spinner and shows completion message
--- @usage
--- local stop_spinner = notify_with_spinner("Loading...", {interval = 50})
--- -- ... some async work ...
--- stop_spinner("Load complete!")
function M.notify_with_spinner(message, opts)
  opts = opts or {}
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local kill = false
  local interval = opts.interval or 100
  opts.interval = nil -- delete from opts because it is passed to M.message

  -- 1. Create the coroutine logic
  local co = coroutine.create(function()
    local i = 1
    while not kill do
      local frame = spinner_frames[i]
      M.message(frame .. " " .. message, opts)
      i = i % #spinner_frames + 1
      coroutine.yield()
    end
  end)

  -- 2. Define the animation loop
  local function run_animation()
    if coroutine.status(co) ~= "dead" then
      coroutine.resume(co)
      -- Adjust the 100ms for faster/slower rotation
      vim.defer_fn(run_animation, interval)
    end
  end

  -- Start the animation
  run_animation()

  -- 3. Return a "stop" function to kill the loop
  return function(done_message, done_opts)
    kill = true
    M.message(done_message or "Done!", vim.tbl_deep_extend("force", opts, done_opts or {}))
  end
end

--- Remove empty/whitespace-only elements from the beginning and end of a table
-- This function modifies the table in-place by removing empty strings or
-- strings containing only whitespace from the start and end of the table.
-- @param tbl table The table to trim (modified in-place)
-- @return table The same table reference after trimming
function M.trim_table(tbl)
  local function is_whitespace(str)
    return str:match "^%s*$" ~= nil
  end

  while #tbl > 0 and (tbl[1] == "" or is_whitespace(tbl[1])) do
    table.remove(tbl, 1)
  end

  while #tbl > 0 and (tbl[#tbl] == "" or is_whitespace(tbl[#tbl])) do
    table.remove(tbl, #tbl)
  end

  return tbl
end

function M.shallow_clone_table(t)
  assert(type(t) == "table")
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

function M.reverse_table(t)
  local reversed = {}
  for i = #t, 1, -1 do
    table.insert(reversed, t[i])
  end
  return reversed
end

--- Checks if the current Vim mode is Visual ('v' or 'V').
--- @return boolean true if in visual mode, false otherwise.
function M.is_visual_mode()
  return vim.fn.mode() == "v" or vim.fn.mode() == "V"
end

---@param prompt string
---@param items string[]
---@return number|nil
function M.inputlist(prompt, items)
  local menu = { prompt }
  vim.list_extend(menu, items)

  local idx = vim.fn.inputlist(menu)
  if idx < 1 or idx > #items then
    return nil
  end
  return idx
end

--- Synchronously select an item from a list using vim.ui.select
-- This function wraps the asynchronous vim.ui.select API to provide
-- a synchronous interface using coroutines.
-- @param items table: List of items to choose from
-- @param opts table|nil: Optional configuration options for the selector
-- @return any|nil: The selected item, or nil if selection was cancelled
-- @return number|nil: The index of the selected item, or nil if cancelled
-- @throws error if not called from within a coroutine
function M.ui_select_sync(items, opts)
  local co = coroutine.running()
  if not co then
    error "ui_select_sync must be called from a coroutine"
  end

  vim.ui.select(items, opts, function(choice, idx)
    coroutine.resume(co, choice, idx)
  end)

  return coroutine.yield()
end

function M.edit_file(filename, add_syntax_highlighting, pattern, postwrite)
  vim.cmd("edit " .. vim.fn.fnameescape(filename))
  local bufnr = vim.api.nvim_get_current_buf()
  add_syntax_highlighting(bufnr)

  -- Run callback after the buffer is written
  if postwrite then
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = bufnr,
      -- once = true,
      callback = function()
        postwrite(bufnr)
      end,
    })
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if pattern then
    -- Position cursor at the first line containing the pattern
    for i, line in ipairs(lines) do
      if line:match(pattern) then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        break
      end
    end
  end
end

---Truncates a string to a maximum length, appending "..." if truncated.
---@param s string The string to truncate.
---@param max_len number The maximum desired length of the string, including ellipsis.
---@return string The truncated or original string.
function M.truncate_string(s, max_len)
  local s_len = #s -- Get string length

  if s_len <= max_len then
    return s
  else
    if max_len < 3 then
      -- If max_len is too small to fit "...", just truncate without it.
      -- Handles cases where max_len is 0, 1, or 2.
      return s:sub(1, max_len)
    else
      -- Truncate to make space for "..."
      return s:sub(1, max_len - 3) .. "..."
    end
  end
end

--- Converts an array of shell arguments into an executable, correctly escaped, shell command string.
---
--- This function takes a table of strings, where each string is an argument for a shell command.
--- It escapes each argument to handle special characters and spaces, then joins them into a single string
--- suitable for execution in a shell.
---
--- @param args_table string[] An array of strings, where each string is a shell argument.
--- @return string The escaped and concatenated shell command string.
function M.args_to_shell_command(args_table)
  -- ...existing code...
  local escaped_args = {}
  for _, arg in ipairs(args_table) do
    -- Escape single quotes within the argument and wrap the whole argument in single quotes.
    -- This ensures that the shell interprets the string literally, handling spaces and special characters.
    local escaped_arg = "'" .. string.gsub(arg, "'", "'\\''") .. "'"
    table.insert(escaped_args, escaped_arg)
  end
  return table.concat(escaped_args, " ")
end

function M.close_ephemeral_window(buffer_name)
  -- 1. Get the buffer number by name
  local bufnr = vim.fn.bufnr(buffer_name)

  -- If bufnr is -1, the buffer doesn't exist
  if bufnr == -1 then
    return
  end

  -- 2. Find all windows displaying this buffer
  -- Note: win_findbuf returns a list of window IDs
  local windows = vim.fn.win_findbuf(bufnr)

  for _, winid in ipairs(windows) do
    -- Check if the window is valid before trying to close it
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  -- 3. Delete the buffer if it still exists
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end
--- Helper to check if a file is binary by scanning the first kilobyte for null bytes.
--- @param path string
--- @return boolean
function M.is_binary(path)
  local f = io.open(path, "rb")
  if not f then
    return false
  end
  local bytes = f:read(1024)
  f:close()

  -- If file is empty (bytes is nil) or no null byte found, it's considered text
  if not bytes then
    return false
  end
  return bytes:find "\0" ~= nil
end

--- Prompts user via Telescope to select a text file and injects its
--- content into the current buffer as a Markdown block.
function M.inject_file()
  local builtin = require "telescope.builtin"
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  builtin.find_files {
    prompt_title = "Inject Text File",
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection == nil then
          return
        end

        local file_path = selection.value

        -- Guard clause using the hoisted helper
        if M.is_binary(file_path) then
          actions.close(prompt_bufnr)
          M.notify("Selection is a binary file; skipping injection.", vim.log.levels.WARN)
          return
        end

        actions.close(prompt_bufnr)

        local file_ext = vim.fn.fnamemodify(file_path, ":e")
        local lines = vim.fn.readfile(file_path)

        -- Build the Markdown injection block
        local injection = {
          "",
          "`" .. file_path .. "`",
          "",
          "```" .. file_ext,
        }

        for _, line in ipairs(lines) do
          table.insert(injection, line)
        end

        table.insert(injection, "```")
        table.insert(injection, "") -- The blank line the cursor will land on

        local row, _ = unpack(vim.api.nvim_win_get_cursor(0))

        -- row is used as the starting point for insertion
        vim.api.nvim_buf_set_lines(0, row, row, false, injection)

        -- Move cursor to the final blank line
        local new_row = row + #injection
        vim.api.nvim_win_set_cursor(0, { new_row, 0 })
      end)
      return true
    end,
  }
end

--- Sanitizes strings for Telescope picker display by removing newlines and truncating.
---@param str string|nil The input text to sanitize.
---@param max_len number? Optional maximum length (defaults to 80).
---@return string
function M.sanitize_display_entry(str, max_len)
  if not str or type(str) ~= "string" then
    return ""
  end

  local limit = max_len or 80

  -- 1. Replace newlines, tabs, and carriage returns with a single space
  local s = str:gsub("[\n\r\t]", " ")

  -- 2. Collapse multiple consecutive spaces into one
  s = s:gsub("%s+", " ")

  -- 3. Remove leading and trailing whitespace
  s = vim.trim(s)

  -- 4. Truncate to the limit and add ellipsis if necessary
  if #s > limit then
    s = s:sub(1, limit - 3) .. "..."
  end

  return s
end

---Generic Telescope-based drop-in replacement for vim.ui.select
---Supports Telescope specific keys like layout_config, layout_strategy, etc.
---@param items table Arbitrary items to select from
---@param opts table Options including `prompt`, `format_item`, and Telescope layout options
---@param on_choice function Callback called with (item, index)
function M.select(items, opts, on_choice)

  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  opts = opts or {}
  local prompt = opts.prompt or "Select"
  local format_item = opts.format_item or tostring

  -- Prepare the picker configuration by merging opts
  local picker_opts = vim.tbl_deep_extend("force", opts, {
    prompt_title = prompt,
    finder = finders.new_table {
      results = items,
      entry_maker = function(item)
        local display = format_item(item)
        return {
          value = item,
          display = display,
          ordinal = display,
        }
      end,
    },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      -- Handle selection
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if not selection then
          on_choice(nil, nil)
          return
        end

        -- Find original index to match vim.ui.select behavior
        local index = nil
        for i, item in ipairs(items) do
          if item == selection.value then
            index = i
            break
          end
        end

        on_choice(selection.value, index)
      end)

      -- Handle explicit cancellation
      local cancel = function()
        actions.close(prompt_bufnr)
        on_choice(nil, nil)
      end

      map("i", "<C-c>", cancel)
      map("n", "<Esc>", cancel)

      return true
    end,
  })

  pickers.new(opts, picker_opts):find()
end

function M.get_time_ms()
  local seconds, microseconds = vim.uv.gettimeofday()
  return (seconds * 1000) + math.floor(microseconds / 1000)
end

function M.delete_file(filename, opts)
  opts = opts or {}
  if opts.confirm then
    local confirm_result = vim.fn.confirm("Delete '" .. filename .. "'?", "&Yes\n&No", 2)
    if confirm_result ~= 1 then -- User did not select 'Yes'
      M.notify("User aborted", vim.log.levels.INFO)
      return false
    end
  end
  -- Synchronously delete selected chat file
  local ok, err = os.remove(filename)
  if ok then
    M.notify("Deleted '" .. filename .. "'", vim.log.levels.INFO)
    return true
  else
    M.notify("Failed to delete file '" .. filename .. "': " .. (err or "unknown error"), vim.log.levels.ERROR)
    return false
  end
end

--- Check if a file exists and is readable
-- @param path string: File path to check
-- @return boolean: true if readable file exists
function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

return M
