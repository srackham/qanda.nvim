local utils = require "qanda.utils"

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

---Retrieves the ID of a buffer by its name. If `name` contains a directory separator, it's matched against the full buffer path; otherwise, it's matched against the buffer's basename.
---@param name string The name of the buffer to find (can be a full path or basename).
---@return number|nil The buffer ID if found, otherwise nil.
function M.get_buf_id(name)
  local compare_full_path = name:find "/" ~= nil
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local buf_path = vim.api.nvim_buf_get_name(bufnr)
    local target_name
    if compare_full_path then
      target_name = buf_path
    else
      target_name = vim.fn.fnamemodify(buf_path, ":t")
    end
    if target_name == name then
      return bufnr
    end
  end
  return nil
end

--- Opens a floating window.
---@param opts FloatLayout? Optional configuration parameters
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
---@param opts? UIWindow Window and buffer options.
---@return nil
function M.open_window(buf_name, opts)
  opts = opts or { mode = "normal" }

  -- Check if buffer for path already exists
  local existing_buf = M.get_buf_id(buf_name)
  local buf = existing_buf or vim.api.nvim_create_buf(false, true)

  local existing_win = M.get_winid_of_buffer(buf)
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
    return
  end

  if opts.mode == "float" then
    open_float(buf, opts.float_layout)
  elseif opts.mode == "normal" then
    vim.cmd "enew"
  elseif opts.mode == "top" then
    vim.cmd("split " .. vim.fn.fnameescape(buf_name))
  elseif opts.mode == "left" then
    vim.cmd("vsplit " .. vim.fn.fnameescape(buf_name))
  elseif opts.mode == "bottom" then
    vim.cmd("botright split " .. vim.fn.fnameescape(buf_name))
  elseif opts.mode == "right" then
    vim.cmd("botright vsplit " .. vim.fn.fnameescape(buf_name))
  else
    utils.notify("Invalid window mode '" .. opts.mode .. "'", vim.log.levels.WARN)
  end

  vim.cmd("setlocal " .. (opts.setlocal or "buftype=nofile bufhidden=hide"))
  vim.cmd("file " .. buf_name)
end

-- UIWindow class --

M.UIWindow = {}
M.UIWindow.__index = M.UIWindow

--- Constructor
---@param opts table Initialises UIWindow fields
---@return UIWindow
function M.UIWindow.new(opts)
  local self = setmetatable({}, M.UIWindow)

  for k, v in pairs(opts or {}) do
    self[k] = v
  end

  return self
end

--- Focus or create the window
---@param opts table Initialises UIWindow fields
function M.UIWindow:open(opts)
  for k, v in pairs(opts or {}) do
    self[k] = v
  end

  if not self.buf_name then
    utils.notify("Cannot open UIWindow: buf_name is required.", vim.log.levels.ERROR)
    return
  end

  -- M.open_window handles creating the buffer if it doesn't exist and opening/focusing the window.
  -- It sets the current window and buffer.
  M.open_window(self.buf_name, self)

  -- After opening, update self.bufnr and self.winid based on the currently active window/buffer
  self.bufnr = vim.api.nvim_get_current_buf()
  self.winid = vim.api.nvim_get_current_win()

  vim.api.nvim_set_option_value("modifiable", self.modifiable, { buf = self.bufnr })
end

--- Activate and show cursor position
--- If cursor_position is nil, go to end of buffer
---@param cursor_position? {row: number, col: number}
function M.UIWindow:set_cursor(cursor_position)
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    utils.notify("Cannot set cursor: window is not valid.", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_set_current_win(self.winid) -- Ensure the window is focused
  if cursor_position == nil then
    M.cursor_to_end(self.winid)
  else
    vim.api.nvim_win_set_cursor(self.winid, cursor_position)
  end
end

--- Append lines and position cursor at end
---@param lines string[]
function M.UIWindow:append(lines)
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    utils.notify("Cannot append lines: buffer is not valid.", vim.log.levels.WARN)
    return
  end

  local current_lines_count = vim.api.nvim_buf_line_count(self.bufnr)
  -- Insert at the end of the buffer (after the last line)
  vim.api.nvim_set_option_value("modifiable", true, { buf = self.bufnr })
  vim.api.nvim_buf_set_lines(self.bufnr, current_lines_count, current_lines_count, false, lines)
  vim.api.nvim_set_option_value("modifiable", self.modifiable, { buf = self.bufnr })
  self:set_cursor(nil) -- Move cursor to end
end

--- Return list of buffer lines
---@return string[]
function M.UIWindow:get_lines()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    utils.notify("Cannot get lines: buffer is not valid.", vim.log.levels.WARN)
    return {}
  end
  return vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
end

--- Set buffer lines and position cursor at end
---@param lines string[]
function M.UIWindow:set_lines(lines)
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    utils.notify("Cannot set lines: buffer is not valid.", vim.log.levels.WARN)
    return
  end

  -- Replace all lines in the buffer
  vim.api.nvim_set_option_value("modifiable", true, { buf = self.bufnr })
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", self.modifiable, { buf = self.bufnr })
  self:set_cursor(nil) -- Move cursor to end
end

return M
