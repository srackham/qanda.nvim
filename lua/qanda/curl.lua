local utils = require "qanda.utils"

local M = {}

local active_job = nil
local job_status = "stopped" ---@type JobStatus
local error_message = nil
local stop_spinner = function(_, _) end
local model_response = {} -- Stores the full model response as a table of lines

--- Helper: Appends text to the end of a specific window's buffer
--- Uses vim.schedule to ensure UI calls happen on the main thread.
local function append_to_win(winid, text, window_only)
  vim.schedule(function()
    local bufnr = vim.api.nvim_win_get_buf(winid)
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local last_line_idx = math.max(0, line_count - 1)
    local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line_idx, -1, false)[1] or ""

    local lines_from_text = vim.split(text, "\n")

    -- Update model_response to correctly reflect the accumulated lines
    if not window_only then
      if #model_response == 0 then
        -- If model_response is empty, populate it with the initial lines
        for _, line_part in ipairs(lines_from_text) do
          table.insert(model_response, line_part)
        end
      else
        -- Append the first part of the text to the last line in model_response
        model_response[#model_response] = (model_response[#model_response] or "") .. (lines_from_text[1] or "")

        -- If there are additional parts (due to newlines in 'text'), add them as new lines
        for i = 2, #lines_from_text do
          table.insert(model_response, lines_from_text[i])
        end
      end
    end

    -- Insert the first chunk of text into the current last line
    vim.api.nvim_buf_set_text(bufnr, last_line_idx, #last_line_content, last_line_idx, #last_line_content, { lines_from_text[1] })

    -- If the text contained newlines, append the remaining lines as new buffer lines
    if #lines_from_text > 1 then
      local rest = { unpack(lines_from_text, 2) }
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, rest)
    end

    -- Auto-scroll the window to follow the streaming output
    local new_last_line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(winid, { new_last_line, 0 })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  end)
end

---Kill existing job instance and reset job status to "stopped"
local function stop_job()
  if active_job then
    active_job:kill(15) -- Send SIGTERM
    active_job = nil
  end
  job_status = "stopped"
end

--- Aborts the current process execution if one is running
function M.kill_command()
  if active_job then
    stop_job()
    job_status = "aborted"
  end
end

function M.get_job_status()
  return job_status
end

function M.is_active_job()
  return active_job ~= nil
end

--- Executes the command and streams API 'content' to the window.
--- The data_normaliser should convert raw_json response data into Ollama‑shape response data.
--- @param cmd table The command array (e.g., {'curl', ...})
--- @param stdin string|string[]|nil If non-nil is written to the process stdin
--- @param data_normaliser function (raw_json: string) -> table | nil
--- @param winid number The Neovim window ID to target
--- @param on_exit_callback function Function to call when job finishes
function M.execute_command(cmd, stdin, data_normaliser, winid, on_exit_callback)
  if not vim.api.nvim_win_is_valid(winid) then
    utils.notify("Invalid Chat window ID: " .. winid, vim.log.levels.ERROR)
    return
  end

  utils.clear_sequence(model_response)

  stop_job()
  stop_spinner = utils.notify_with_spinner("Generating...", { interval = 100, hl_group = "QandaSpinner" })

  local line_buffer = ""
  local done = false

  local start_ms = utils.get_time_ms()

  local log_error = function(msg)
    error_message = msg
    append_to_win(winid, "\n\n___\n**Error: " .. msg .. "**", true)
    job_status = "error"
    done = true
  end

  active_job = vim.system(cmd, {
    stdin = stdin,
    stdout = function(err, data)
      if done then -- Discard second and subsequent "done" messages
        return
      end
      if err then
        if err ~= "closed" and err ~= "timeout" then -- Don't break streaming on closure/timeout
          log_error("stdout: " .. err)
        end
        return
      end
      if not data then
        return
      end

      line_buffer = line_buffer .. data

      -- Handle non-newline delimited Ollama errors.
      -- If the buffer starts like a JSON object and contains "error", try to parse it immediately.
      -- NOTE: This match is valid for all providers.
      if line_buffer:match "^%s*{" and line_buffer:match '"error"%s*:' then
        local ok, decoded = pcall(data_normaliser, line_buffer)
        if ok and decoded and decoded.error then
          log_error(decoded.error)
          return
        end
      end

      -- Process complete JSON objects delimited by newlines
      while true do
        local newline_pos = line_buffer:find "\n"
        if not newline_pos then
          break
        end

        local raw_json = line_buffer:sub(1, newline_pos - 1)
        line_buffer = line_buffer:sub(newline_pos + 1)

        raw_json = vim.trim(raw_json)
        if raw_json == "" then
          goto continue
        end

        -- Let the data_normaliser convert raw_json to Ollama‑shape
        local ok, decoded = pcall(data_normaliser, raw_json)
        if not ok or type(decoded) ~= "table" then
          goto continue
        end

        -- If we already emitted the done message, skip all further processing for that line
        if done then
          goto continue
        end

        -- Now treat decoded_or_normalized as Ollama‑style
        local chunk = nil
        local duration_msg = nil

        if decoded.message and decoded.message.content then
          chunk = decoded.message.content
        end

        if decoded.done then
          -- Compute elapsed time in ms, convert to seconds for display
          local now_ms = utils.get_time_ms()
          local duration_sec = (now_ms - start_ms) / 1000.0

          duration_msg = string.format("\n\n___\n**Time taken**: %.2fs", duration_sec)
          done = true
        end

        if chunk then
          append_to_win(winid, chunk)
        end
        if duration_msg then
          append_to_win(winid, duration_msg, true)
        end

        ::continue::
      end
    end,
    stderr = function(_, data)
      if data and data:len() > 0 then
        log_error("curl: " .. data)
      end
    end,
  }, function(_)
    if job_status == "aborted" then
      stop_spinner("User aborted!", { hl_group = "WarningMsg" })
    elseif job_status == "error" then
      stop_spinner("Error: " .. error_message, { hl_group = "ErrorMsg" })
    else
      stop_spinner "Execution complete!"
    end
    active_job = nil
    if on_exit_callback then
      on_exit_callback(model_response, error_message)
    end
  end)
end

return M
