local M = {} -- This module

--- Move cursor to the end of the content in a Neovim window and focus it
-- Positions the cursor at the last character of the last line in the window's buffer,
-- then sets the window as the current (focused) window.
-- @param win_id integer|nil The window ID to move cursor to, or nil if invalid
function M.cursor_to_end(win_id)
  if win_id ~= nil and vim.api.nvim_win_is_valid(win_id) then
    -- Move the cursor to the last character in the Responses buffer
    local buf = vim.api.nvim_win_get_buf(win_id)
    local last_row = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, last_row - 1, last_row, false)[1] or ""
    local last_col = math.max(#last_line - 1, 0)
    vim.api.nvim_win_set_cursor(win_id, { last_row, last_col })
    -- Focus Responses window
    vim.api.nvim_set_current_win(win_id)
  end
end

--- Synchronously select an item from a list using vim.ui.select
-- This function wraps the asynchronous vim.ui.select API to provide
-- a synchronous interface using coroutines.
-- @param items table: List of items to choose from
-- @param opts table|nil: Optional configuration options for the selector
-- @return any|nil: The selected item, or nil if selection was cancelled
-- @return number|nil: The index of the selected item, or nil if cancelled
-- @throws error if not called from within a coroutine
function M.select_sync(items, opts)
  local co = coroutine.running()
  if not co then
    error "select_sync must be called from a coroutine"
  end

  vim.ui.select(items, opts, function(choice, idx)
    coroutine.resume(co, choice, idx)
  end)

  return coroutine.yield()
end

--- Retrieves the ID of a buffer by its name.
---@param name string The name of the buffer to find.
---@return number|nil The buffer ID if found, otherwise nil.
function M.get_buf_id(name)
  for _, b_id in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b_id) and vim.api.nvim_buf_get_name(b_id) == name then
      return b_id
    end
  end
  return nil
end

--- Opens a floating window.
---@param opts table|nil Optional configuration parameters
---  - `width` number Width of the float as a percentage of editor width (default: 0.8)
---  - `height` number Height of the float as a percentage of editor height (default: 0.8)
---  - `border` string Border style ("single", "double", "rounded", etc.) (default: "single")
---  - `style` string Window style (default: "minimal")
local function open_float(buf, opts)
  -- Set default options
  opts = vim.tbl_deep_extend("force", {
    width = 0.8,
    height = 0.8,
    border = "single",
    style = "minimal",
  }, opts or {})

  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * opts.width)
  local height = math.floor(ui.height * opts.height)
  local col = math.floor((ui.width - width) / 2)
  local row = math.floor((ui.height - height) / 2)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = opts.style,
    border = opts.border,
    width = width,
    height = height,
    col = col,
    row = row,
    title = opts.title,
    title_pos = opts.title_pos,
  })
end

function M.get_winid_of_buffer(bufnr)
  -- Check if window for buffer already exists
  local winid = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      winid = win
      break
    end
  end
  return winid
end

--- Open a window according to the requested window options.
---
--- If `opts.window_mode` is omitted or `"normal"`, the window replaces the current window.
--- Other options are passed to the underlying window creation function
---
---@param buf_name string Buffer name
---@param opts? CreateWindowOpts Window and buffer options.
---@return nil
function M.open_window(buf_name, opts)
  opts = opts or {window_mode="normal"}

  -- Check if buffer for path already exists
  local existing_buf = M.get_buf_id(buf_name)
  local buf = existing_buf or vim.api.nvim_create_buf(false, true)

  local existing_win = M.get_winid_of_buffer(buf)
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
    return
  end

  local window_mode = opts.window_mode
  if window_mode == "float" then
    open_float(buf, opts)
  elseif window_mode == "normal" then
    vim.cmd "enew"
  elseif window_mode == "top" then
    vim.cmd("split " .. vim.fn.fnameescape(buf_name))
  elseif window_mode == "left" then
    vim.cmd("vsplit " .. vim.fn.fnameescape(buf_name))
  elseif window_mode == "bottom" then
    vim.cmd("botright split " .. vim.fn.fnameescape(buf_name))
  elseif window_mode == "right" then
    vim.cmd("botright vsplit " .. vim.fn.fnameescape(buf_name))
  else
    M.notify("Invalid window mode '" .. window_mode .. "'", vim.log.levels.WARN)
  end

  vim.cmd("setlocal " .. (opts.buffer_options or "buftype=nofile bufhidden=hide"))
  vim.cmd("file " .. buf_name)
end

-- UIWindow class --

local UIWindow = {}
UIWindow.__index = UIWindow

--- Constructor
---@param opts table Initialises UIWindow fields
---@return UIWindow
function UIWindow.new(opts)
  local self = setmetatable({}, UIWindow)

  opts = opts or {}
  self.mode = opts.mode or "normal"
  self.bufnr = opts.bufnr
  self.winid = opts.winid
  self.modifiable = opts.modifiable or false

  return self
end

--- Focus or create the window
function UIWindow:open()
  -- stub
  ---@todo
end

--- Activate and show cursor position
--- If cursor_position is nil, go to end of buffer
---@param cursor_position? table
function UIWindow:set_cursor(cursor_position)
  -- stub
  ---@todo
  _ = cursor_position
end

--- Append lines and position cursor at end
---@param lines string[]
function UIWindow:append(lines)
  -- stub
  ---@todo
  _ = lines
end

--- Return list of buffer lines
---@return string[]
function UIWindow:get_lines()
  -- stub
  ---@todo
  return {}
end

--- Set buffer lines and position cursor at end
---@param lines string[]
function UIWindow:set_lines(lines)
  -- stub
  ---@todo
  _ = lines
end

return M
