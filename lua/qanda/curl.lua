local M = {}

-- Module-scoped variable to track the active process
local active_job = nil

--- Helper: Appends text to the end of a specific window's buffer
--- Uses vim.schedule to ensure UI calls happen on the main thread.
local function append_to_win(winid, text)
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(winid) then
      return
    end
    local bufnr = vim.api.nvim_win_get_buf(winid)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local last_line_idx = math.max(0, line_count - 1)
    local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line_idx, -1, false)[1] or ""

    local lines = vim.split(text, "\n")

    -- Insert the first chunk of text into the current last line
    vim.api.nvim_buf_set_text(bufnr, last_line_idx, #last_line_content, last_line_idx, #last_line_content, { lines[1] })

    -- If the text contained newlines, append the remaining lines as new buffer lines
    if #lines > 1 then
      local rest = { table.unpack(lines, 2) }
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, rest)
    end

    -- Auto-scroll the window to follow the streaming output
    local new_last_line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(winid, { new_last_line, 0 })
  end)
end

--- Aborts the current process execution if one is running
function M.kill_command()
  if active_job then
    active_job:kill(15) -- Send SIGTERM
    active_job = nil
    vim.notify("Process aborted.", vim.log.levels.WARN)
  end
end

--- Executes the command and streams Ollama JSON 'content' to the window
--- @param cmd table The command array (e.g., {'curl', ...})
--- @param winid number The Neovim window ID to target
function M.execute_command(cmd, winid)
  -- Kill any existing instance to avoid overlapping streams
  M.kill_command()

  local line_buffer = ""

  active_job = vim.system(cmd, {
    stdout = function(err, data)
      if err then
        return
      end
      if data then
        line_buffer = line_buffer .. data

        -- Process complete JSON objects delimited by newlines
        while true do
          local newline_pos = line_buffer:find "\n"
          if not newline_pos then
            break
          end

          local raw_json = line_buffer:sub(1, newline_pos - 1)
          line_buffer = line_buffer:sub(newline_pos + 1)

          if raw_json ~= "" then
            local ok, decoded = pcall(vim.json.decode, raw_json)
            if ok and decoded then
              -- 1. Stream the actual message content
              if decoded.message and decoded.message.content then
                append_to_win(winid, decoded.message.content)
              end

              -- 2. Handle the final "done" signal and metadata
              if decoded.done then
                local duration_sec = (decoded.total_duration or 0) / 1e9
                local stats = string.format("\n\n[Done] Reason: %s | Duration: %.2fs", decoded.done_reason or "stop", duration_sec)
                append_to_win(winid, stats)
              end
            end
          end
        end
      end
    end,
    stderr = function(_, data)
      -- Catch standard curl/shell errors and append them to the buffer
      if data and data:len() > 0 then
        append_to_win(winid, "\n[Error]: " .. data)
      end
    end,
  }, function(_)
    -- Cleanup the reference when the process exits
    active_job = nil
  end)
end

return M
