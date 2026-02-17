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

function M.write_string_to_file(str, fname, mode)
  mode = mode or "w" -- Replace file contents by default
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
  vim.api.nvim_echo({ { msg, opts.hl_group or "Normal" } }, opts.history or false, echo_opts)
end

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

return M
