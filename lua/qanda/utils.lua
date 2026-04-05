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

--- Escapes special characters in a string for use in Lua regular expressions.
--- @param text string The string to escape.
--- @return string The escaped string.
function M.escape_pattern(text)
  -- Matches any of: ^ $ ( ) % . [ ] * + - ?
  -- And prefixes them with a %
  return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

--- Clears a Lua array table (sequence) in-place.
--- @param s table The table to clear (modified in-place).
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

--- Writes a string to a file.
--- @param str string The string content to write.
--- @param fname string The path to the file.
--- @param mode string? The file open mode (e.g., "w", "a+"). Defaults to "w".
--- @return boolean `true` if successful, `false` otherwise.
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

--- Appends a string to a file.
--- @param str string The string content to append.
--- @param fname string The path to the file.
--- @return boolean `true` if successful, `false` otherwise.
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

--- Creates a shallow clone of a table.
--- @param t table The table to clone.
--- @return table A new table containing the same key-value pairs as the original.
function M.shallow_clone_table(t)
  assert(type(t) == "table")
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

--- Creates a new table with elements of the input array table in reverse order.
--- @param t table The array-like table to reverse.
--- @return table A new table with elements in reverse order.
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

-- Returns `true` if Neovim is in insert mode.
function M.is_insert_mode()
  return vim.api.nvim_get_mode().mode == 'i'
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

--- Opens a file for editing, applies syntax highlighting, positions the cursor, and sets up a post-write callback.
--- @param filename string The path to the file to edit.
--- @param add_syntax_highlighting fun(bufnr: number) A function to apply syntax highlighting to the buffer.
--- @param pattern string? An optional Lua pattern to search for and position the cursor.
--- @param postwrite fun(bufnr: number)? An optional callback function to run after the buffer is written.
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

--- Closes any windows displaying a buffer with the given name and deletes the buffer.
--- @param buffer_name string The name of the buffer to close/delete.
function M.close_ephemeral_window(buffer_name)
  -- Get the buffer number by name
  local bufnr = vim.fn.bufnr(buffer_name)

  -- If bufnr is -1, the buffer doesn't exist
  if bufnr == -1 then
    return
  end

  -- Find all windows displaying this buffer
  -- Note: win_findbuf returns a list of window IDs
  local windows = vim.fn.win_findbuf(bufnr)

  for _, winid in ipairs(windows) do
    -- Check if the window is valid before trying to close it
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  -- Delete the buffer if it still exists
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

--- Prompts user via Telescope to select text files and injects their
--- content into the current buffer as Markdown blocks.
function M.inject_file()
  local builtin = require "telescope.builtin"
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  -- Lock in the current buffer and window BEFORE opening Telescope
  local target_buf = vim.api.nvim_get_current_buf()
  local target_win = vim.api.nvim_get_current_win()

  builtin.find_files {
    prompt_title = "Inject Text File(s)",
    attach_mappings = function(picker_bufnr, map)
      map({ "n", "i" }, "<Tab>", actions.toggle_selection + actions.move_selection_next)

      actions.select_default:replace(function()
        local picker = action_state.get_current_picker(picker_bufnr)
        local selections = picker:get_multi_selection()

        -- Fallback to single selection if multi-selection is empty
        if vim.tbl_isempty(selections) then
          local single = action_state.get_selected_entry()
          selections = single and { single } or {}
        end

        -- Close the picker first
        actions.close(picker_bufnr)

        if #selections == 0 then
          return
        end

        for _, entry in ipairs(selections) do
          local injection = {}
          local file_path = entry.value

          if M.is_binary(file_path) then
            M.notify("Skipped binary file: " .. file_path, vim.log.levels.WARN)
          else
            local file_ext = vim.fn.fnamemodify(file_path, ":e")
            local lines = vim.fn.readfile(file_path)

            table.insert(injection, "")
            table.insert(injection, "`" .. file_path .. "`")
            table.insert(injection, "")
            table.insert(injection, "```" .. file_ext)

            for _, line in ipairs(lines) do
              table.insert(injection, line)
            end

            table.insert(injection, "```")
            table.insert(injection, "")

            local row, _ = unpack(vim.api.nvim_win_get_cursor(target_win))
            vim.api.nvim_buf_set_lines(target_buf, row, row, false, injection)

            local new_row = row + #injection
            vim.api.nvim_win_set_cursor(target_win, { new_row, 0 })
          end
        end
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
    attach_mappings = function(picker_bufnr, map)
      -- Handle selection
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(picker_bufnr)

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
        actions.close(picker_bufnr)
        on_choice(nil, nil)
      end

      map("i", "<C-c>", cancel)
      map("n", "<Esc>", cancel)

      return true
    end,
  })

  pickers.new(opts, picker_opts):find()
end

--- Returns the current time in milliseconds since the Unix epoch.
--- @return number The current time in milliseconds.
function M.get_time_ms()
  local seconds, microseconds = vim.uv.gettimeofday()
  return (seconds * 1000) + math.floor(microseconds / 1000)
end

--- Deletes a file, with an optional confirmation prompt.
--- @param filename string The path to the file to delete.
--- @param opts { confirm?: boolean }? Optional configuration.
--- @return boolean `true` if the file was deleted successfully, `false` otherwise.
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

--- Finds the first index of a given value in an array-like table.
--- @param tbl table The table to search.
--- @param value any The value to find.
--- @return number? The 1-based index of the value if found, otherwise `nil`.
function M.index_of(tbl, value)
  for i, v in ipairs(tbl) do
    if v == value then
      return i
    end
  end
  return nil -- not found
end

--- Formats a list of curl arguments into a multi-line, escaped shell command string.
--- @param args string[] An array of cURL command arguments.
--- @return string The formatted shell command string.
function M.curl_args_to_shell_command(args)
  local grouped_flags = {
    ["-H"] = true,
    ["-X"] = true,
    ["-d"] = true,
    ["--data"] = true,
    ["--data-raw"] = true,
    ["--data-binary"] = true,
  }

  local function format_arg(str)
    if str:match "^[A-Za-z0-9%-%_%./:=@]+$" then
      return str
    else
      return "'" .. str:gsub("'", "'\\''") .. "'"
    end
  end

  local lines = {}
  local i = 1

  table.insert(lines, format_arg(args[1]) .. " \\")
  i = 2

  while i <= #args do
    local arg = args[i]
    local next_arg = args[i + 1]

    if grouped_flags[arg] and next_arg then
      local formatted

      if arg == "-d" or arg:match "^%-%-data" then
        if next_arg:match "^%b{}$" then
          -- Escape single quotes inside JSON
          local escaped = next_arg:gsub("'", "'\\''")
          formatted = "'\n" .. escaped .. "\n'"
        else
          formatted = format_arg(next_arg)
        end

        table.insert(lines, "  " .. arg .. " " .. formatted .. " \\")
      else
        table.insert(lines, "  " .. arg .. " " .. format_arg(next_arg) .. " \\")
      end

      i = i + 2
    else
      table.insert(lines, "  " .. format_arg(arg) .. " \\")
      i = i + 1
    end
  end

  -- Remove trailing backslash
  lines[#lines] = lines[#lines]:gsub(" \\$", "")

  return table.concat(lines, "\n")
end

--- Dump diagnostic information from Qanda registers into the current buffer, formatted with Markdown headers.
function M.paste_registers()
  local Config = require "qanda.config"
  local registers = { Config.curl_command_register, Config.system_message_register, Config.request_register }
  local titles = { "## Curl command", "## System message", "## Request Data" }
  local lines = {}

  if not vim.api.nvim_get_option_value("modifiable", { buf = 0 }) then
    M.notify("Buffer is not modifiable", vim.log.levels.ERROR)
    return
  end

  for i, reg in ipairs(registers) do
    local content = vim.fn.getreg(reg)
    table.insert(lines, "___")
    table.insert(lines, titles[i])
    table.insert(lines, "")
    if content then
      if reg == Config.curl_command_register then
        table.insert(lines, "```")
      end
      if reg == Config.request_register then
        table.insert(lines, "```json")
      end
      for line in string.gmatch(content, "[^\n]+") do
        table.insert(lines, line)
      end
      if reg == Config.curl_command_register then
        table.insert(lines, "```")
      end
      if reg == Config.request_register then
        table.insert(lines, "```")
      end
    end
  end

  table.insert(lines, "___")

  if #lines > 1 then
    vim.api.nvim_put(lines, "l", true, true)
  end
end

-- Recursive function to ensure numeric strings are converted in-place to numbers in a table.
-- Targets common Ollama/OpenRouter params like temperature, top_p, max_tokens, etc.
-- Preserves other types unchanged.
function M.normalize_numerics(tbl)
  for k, v in pairs(tbl) do
    if type(v) == "string" then
      local num = tonumber(v)
      if num then
        tbl[k] = num
      end
    elseif type(v) == "table" then
      tbl[k] = M.normalize_numerics(v) -- Recurse into nested tables (e.g., options)
    end
  end
end

-- Delete the first matching item from table `tbl`
function M.table_delete_item(tbl, item)
  for i, v in ipairs(tbl) do
    if v == item then
      table.remove(tbl, i)
      break
    end
  end
end

return M
