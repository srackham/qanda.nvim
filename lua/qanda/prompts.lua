local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {
  user_prompts = {}, ---@type Prompts
  system_prompts = {}, ---@type Prompts
}

function M.setup()
  M.load_user_prompts()
  M.load_system_prompts()
end

---Retrieve a prompt by its name.
---@param prompts Prompts The prompts array to search
---@param name string The name of the prompt.
---@return Prompt|nil The prompt.
function M.get_prompt(prompts, name)
  for _, prompt in ipairs(prompts) do
    if prompt.name == name then
      return prompt
    end
  end
  return nil
end

-- ---Make a copy of `prompt`, set its name to `name` and add/replace to `M.prompts`.
-- ---@param prompt Prompt The prompt.
-- ---@param name string? The name of the prompt.
-- ---@return Prompt The new prompt.
-- function M.set_prompt(prompt, name)
--   local p = vim.tbl_deep_extend("force", {}, prompt)
--   p.name = name or p.name
--   utils.insert_replace(M.user_prompts, p, function(p1, p2)
--     return p1.name == p2.name
--   end)
--   return p
-- end

--- Parses markdown-style prompt files into a Prompts array.
---Each prompt section starts and ends with either `---` or `___`.
---The header envelopes prompt fields formatted like `<name>: <value>`.
---Names not matching `name`, `extract` are added to the `model_options` table.
---| - name (string, required): Unique identifier for the prompt.
---| - extract (string): A regex pattern to extract content from input.
---
---@param text string The full content of the markdown prompt file as a string.
---@return Prompts|nil Returns a Prompts array or nil if parsing fails due to formatting errors.
local function parse_prompts(text)
  local result = {}
  local lines = vim.split(text, "\n")
  local i = 1

  while i <= #lines do
    -- Look for start of header (three hyphens or underscores)
    if lines[i]:match "^%-%-%-$" or lines[i]:match "^___$" then
      i = i + 1
      local prompt = { model_options = {} }

      -- Parse header options until ending delimiter
      local header_start_line = i - 1
      while i <= #lines and not (lines[i]:match "^%-%-%-$" or lines[i]:match "^___$") do
        -- Trim whitespace
        lines[i] = lines[i]:match "^%s*(.-)%s*$"

        -- Skip blank lines and HTML comment lines
        if not lines[i]:match "^%s*$" and not lines[i]:match "^<!--.-?-->$" then
          -- Check for malformed header option format
          local key, value = lines[i]:match "^([^:]+):%s*(.+)$"

          if not key or not value then
            utils.notify("Malformed header option format at line " .. i .. ": " .. lines[i], vim.log.levels.ERROR)
            return nil
          end

          -- Process prompt header fields
          if not utils.table_contains({ "name", "extract" }, key) then
            prompt.model_options[key] = value
          else
            if key == "extract" then
              value = utils.unescape_string(value) -- Translate escaped characters
              local success, _ = pcall(string.match, "", value) -- Validate regex by attempting to compile it
              if not success then
                utils.notify("Invalid regex in extract option at line " .. i .. ": " .. value, vim.log.levels.ERROR)
                return nil
              end
              ---@diagnostic disable-next-line: assign-type-mismatch
              prompt[key] = value
            else
              prompt[key] = value
            end
          end
        end
        i = i + 1
      end

      -- Check for missing closing header line
      if i > #lines or (not lines[i]:match "^%-%-%-$" and not lines[i]:match "^___$") then
        utils.notify("Missing closing header line after header starting at line " .. header_start_line, vim.log.levels.ERROR)
        return nil
      end

      -- Skip the ending delimiter
      i = i + 1

      -- Collect the prompt text until next header or EOF
      local prompt_lines = {}
      while i <= #lines and not (lines[i]:match "^%-%-%-$" or lines[i]:match "^___$") do
        -- Skip HTML comment lines
        if not lines[i]:match "^<!--.-?-->$" then
          table.insert(prompt_lines, lines[i])
        end
        i = i + 1
      end

      -- Create the prompt entry
      prompt.prompt = table.concat(prompt_lines, "\n")
      table.insert(result, prompt)
    else
      i = i + 1
    end
  end

  return result
end

-- local function string_to_prompt(str)
--   if utils.trim_string(str) == "" then
--     return {}
--   end
--
--   local first_line = string.match(str, "^[^\n]*")
--   local with_header
--
--   if first_line ~= "___" and first_line ~= "---" then
--     local header = "___\nname: .\n___\n"
--     with_header = header .. str
--   else
--     with_header = str
--   end
--
--   local prompt = parse_prompts(with_header)
--
--   if prompt == nil or utils.table_size(prompt) ~= 1 or prompt["."] == nil then
--     utils.notify("Invalid prompt:\n" .. str, vim.log.levels.ERROR)
--     return nil
--   end
--
--   return prompt
-- end
--
-- ---Helper to get full path for a prompt name
-- local function get_prompt_file_path(prompts_dir, name)
--   return prompts_dir .. "/" .. name .. ".user.md"
-- end
--
-- -- Helper to validate new prompts file name
-- local function is_valid_filename(name)
--   -- Allowed characters: alphanumeric, '+', '-', ' ', '.', '_'
--   return name:match "^[a-zA-Z0-9%+%-% ._]+$" ~= nil
-- end
--
-- ---Helper to create a new prompts file with a basic template
-- local function create_new_prompts_file_template(filepath, name)
--   local f, err = io.open(filepath, "w")
--   if not f then
--     utils.notify("Error creating file '" .. filepath .. "': " .. (err or "unknown error"), vim.log.levels.ERROR)
--     return false
--   end
--   local display_name = name:gsub("_", " ")
--   local template_content = string.format("---\nname: %s\n---\n\nPrompt text for %s: $text", display_name, display_name)
--   f:write(template_content)
--   f:close()
--   return true
-- end

---@param prompt Prompt
---@return string[]
local function prompt_to_lines(prompt)
  local lines = {}
  local rule = string.rep("─", 40)

  table.insert(lines, rule)
  table.insert(lines, "name: " .. prompt.name)
  if prompt.extract then
    table.insert(lines, "extract: " .. utils.escape_string(prompt.extract))
  end
  if prompt.model_options then
    for k, v in pairs(prompt.model_options) do
      table.insert(lines, k .. ": " .. v)
    end
  end
  table.insert(lines, rule)
  for _, v in ipairs(vim.split(utils.trim_string(prompt.prompt or ""), "\n")) do
    table.insert(lines, v)
  end
  return lines
end

--- Initialise M.prompts table from prompts files (custom markdown file in the configuration prompts directory).
local function load_prompts(role)
  local result = {} ---@type Prompts

  -- Read and merge prompts from all .user.md files
  local prompts_dir = Config.prompts_dir
  local glob_pattern = prompts_dir .. "/*." .. role .. ".md"
  local prompt_files = vim.fn.glob(glob_pattern, false, true)

  if role == "user" then
    -- If there are no prompts files then create one
    if #prompt_files == 0 then
      local path = Config.prompts_dir .. "/default.user.md"

      -- Create parent directory if it does not already exist
      local dir = vim.fn.fnamemodify(path, ":h")
      if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
      end

      local f, err = io.open(path, "w")
      if not f then
        utils.notify("Error creating prompts file '" .. path .. "': " .. (err or "unknown error"), vim.log.levels.ERROR)
        return false
      end
      local content = [[
___
name: Make a request
___
${input:Enter request:}
]]
      f:write(content)
      f:close()
      prompt_files = vim.fn.glob(glob_pattern, false, true)
      assert(#prompt_files == 1)
    end
  end

  -- Load the prompts files
  for _, file_path in ipairs(prompt_files) do
    if vim.fn.filereadable(file_path) == 1 then
      local file_content = vim.fn.readfile(file_path)
      if file_content then
        file_content = table.concat(file_content, "\n")
        local prompts
        prompts = parse_prompts(file_content)
        if prompts then
          for _, v in ipairs(prompts) do
            v.filename = file_path
            table.insert(result, v)
          end
        else
          utils.notify("Failed to parse prompts from '" .. file_path .. "', skipping.", vim.log.levels.ERROR)
        end
      end
    end
  end
  return result
end

function M.load_system_prompts()
  M.system_prompts = load_prompts "system"
  -- Sync the State.system_prompt prompt because loading creates new objects
  if State.system_prompt then
    for _, p in ipairs(M.system_prompts) do
      if p.name == State.system_prompt.name then
        State.system_prompt = p
        return
      end
    end
  end
end

function M.load_user_prompts()
  M.user_prompts = load_prompts "user"
end

---Open prompt window, load the prompt.
---If the prompt window does not exist, create it and attach key-mapped commands.
---@param prompt Prompt
function M.open_prompt(prompt)
  local win = State.prompt_window
  win:open()
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  M.add_prompt_syntax_highlighting(win.bufnr)
  local lines = vim.split(prompt.prompt, "\n")
  win:set_lines(lines)
  -- Attach key commands.
  vim.keymap.set("n", Config.quit_key, function()
    win:close()
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.switch_key, function()
    vim.cmd "Qanda /chat"
  end, { buffer = win.bufnr })
  vim.keymap.set("n", Config.exec_key, function()
    prompt.prompt = table.concat(win:get_lines(), "\n")
    win:close()
    require("qanda").execute_prompt(prompt)
  end, { buffer = win.bufnr })
end

local prompt_syntax_rules = {
  QandaPromptProperty = [[\v^(name|extract|prompt|temperature|top_p|max_tokens|stream):]],
  QandaPromptPlaceholder = [[\v\$(text|input|select|clipboard|yanked|filetype|register_.|register)|\$\{input:.{-}\}|\$\{file:.{-}\}]],
}

-- Define highlight groups once (link to existing groups)
vim.api.nvim_set_hl(0, "QandaPromptProperty", { link = "Keyword" })
vim.api.nvim_set_hl(0, "QandaPromptPlaceholder", { link = "Identifier" })

--- Add extra syntax prompt file highlighting rules to a buffer
--- NOTE: Treesitter highlighting may override these.
---@param bufnr integer
function M.add_prompt_syntax_highlighting(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    for group, pattern in pairs(prompt_syntax_rules) do
      vim.cmd(("syntax match %s /%s/"):format(group, pattern))
    end
  end)
end

---Displays a telescope picker for selecting, editing and executing prompts.
---@param mappings function Telescope attach_mappings callback
local function prompt_picker(prompts, mappings, display_entry)
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"
  local conf = require("telescope.config").values

  -- Prepare prompt data for telescope
  local picker_entries = {}
  for _, prompt in ipairs(prompts) do
    table.insert(picker_entries, prompt)
  end
  table.sort(picker_entries, function(a, b)
    return a.name < b.name
  end)

  -- Create previewer that shows the prompt value
  local prompt_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local prompt = entry.value

      assert(prompt)

      local lines = prompt_to_lines(prompt)

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_prompt_syntax_highlighting(self.state.bufnr)
    end,
  }

  -- Create and run the telescope picker
  pickers
    .new({}, {
      finder = finders.new_table {
        results = picker_entries,
        entry_maker = function(prompt)
          return {
            value = prompt,
            display = display_entry and display_entry(prompt) or prompt.name,
            ordinal = prompt.name,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = prompt_previewer,
      attach_mappings = mappings,
      layout_config = Config.prompt_picker_layout,
    })
    :find()
end

function M.user_prompt_picker(callback)
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  prompt_picker(M.user_prompts, function(bufnr, map)

    -- <Enter> - Close the picker and open the prompt in the prompt window
    actions.select_default:replace(function()
      local selection = action_state.get_selected_entry()
      actions.close(bufnr)
      if selection then
        local prompt = selection.value
        assert(prompt)
        M.open_prompt(prompt)
      else
        utils.notify("User cancelled", vim.log.levels.INFO)
      end
    end)

    -- Close the picker and execute the selected prompt template
    map({ "n", "i" }, Config.exec_key, function()
      local selection = action_state.get_selected_entry()
      actions.close(bufnr)
      if selection then
        callback(selection.value)
      else
        utils.notify("User cancelled", vim.log.levels.INFO)
      end
    end)

    -- Close the picker and edit prompts file containing the selected prompt
    map({ "n", "i" }, Config.edit_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local prompt = selection.value
        assert(prompt)
        actions.close(bufnr)
        if prompt.filename then
          utils.edit_file(prompt.filename, M.add_prompt_syntax_highlighting, "^name:%s*" .. utils.escape_pattern(prompt.name))
        else
          utils.notify("No file associated with built-in prompt '" .. prompt.name .. "'", vim.log.levels.WARN)
        end
      end
    end)

    return true
  end)
end

function M.system_prompt_picker(callback)
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  prompt_picker(M.system_prompts, function(bufnr, map)

    -- <Enter> - Close the picker window; execute callback
    actions.select_default:replace(function()
      local selection = action_state.get_selected_entry()
      actions.close(bufnr)
      if selection then
        callback(selection.value)
      else
        utils.notify("User cancelled", vim.log.levels.INFO)
      end
    end)

    -- Close the picker and edit prompts file containing the selected prompt
    map({ "n", "i" }, Config.edit_key, function()
      local selection = action_state.get_selected_entry()
      if selection then
        local prompt = selection.value
        assert(prompt)
        actions.close(bufnr)
        if prompt.filename then
          utils.edit_file(prompt.filename, M.add_prompt_syntax_highlighting, "^name:%s*" .. utils.escape_pattern(prompt.name))
        else
          utils.notify("No file associated with built-in prompt '" .. prompt.name .. "'", vim.log.levels.WARN)
        end
      end
    end)

    return true
  end, function(prompt)
    if prompt == State.system_prompt then
      return "* " .. prompt.name
    else
      return "  " .. prompt.name
    end
  end)
end

--- Converts a file path to an absolute path based on specific rules.
---
--- Rules:
--- - If the file name has no directory component, it is assumed to reside in `Config.prompts_dir`.
--- - If the file name is relative (e.g., "my/path/file.txt"), it is resolved relative
---   to the current Neovim working directory (`vim.fn.cwd()`).
--- - If the file name is already absolute (e.g., "/home/user/file.txt"), it is returned as is.
---
--- @param file_path string The file path to convert.
--- @return string The absolute file path.
function M.resolve_prompt_path(file_path)
  -- Check if the file_path is just a filename (no directory separators).
  -- vim.fn.fnamemodify(file_path, ':t') extracts only the filename part.
  -- If it's equal to the original file_path, then there was no directory component.
  if vim.fn.fnamemodify(file_path, ":t") == file_path then
    -- If it's just a filename, prepend Config.prompts_dir and then resolve to an absolute path.
    local full_path = Config.prompts_dir .. "/" .. file_path
    return vim.fn.fnamemodify(full_path, ":p")
  else
    -- Otherwise, the path either has directory components (relative to cwd) or is already absolute.
    -- The ':p' modifier handles both cases correctly:
    -- - For relative paths, it makes them absolute relative to vim.fn.cwd().
    -- - For already absolute paths (including those starting with '~'), it returns them as is,
    --   with '~' expanded.
    return vim.fn.fnamemodify(file_path, ":p")
  end
end

--- Substitutes placeholders in the prompt with actual values.
---This function processes a prompt string and replaces special placeholders
---with their corresponding values.
---Placeholders within placeholder values are not replaced.
---
---NOTE: Must be called from a coroutine.
---
---Placeholders processed:
--- - `$input`: Prompts user for input and substitutes the value
--- - `$clipboard`: Substitutes content of system clipboard (alias for `$register_+`)
--- - `$yanked`: Substitutes most recently yanked text (alias for `$register_0`)
--- - `$filetype`: Substitutes current buffer's filetype
--- - `$register_<name>`: Substitutes content of specified register
---
---@param prompt_string string: The prompt string containing placeholders to substitute
---@return string|nil: The prompt with placeholders substituted, or nil if processing should abort
function M.substitute_placeholders(prompt_string)
  if not prompt_string or prompt_string:match "^%s*$" ~= nil then
    return nil
  end

  -- Handle the $select placeholder first
  if string.find(prompt_string, "%$select") then
    -- DEPRECATED: Switched to coroutine-based (async) `vim.ui.select` implementation.
    -- local placeholders = { "$clipboard", "$yanked", "$input" }
    -- local options = { "1. Clipboard", "2. Yanked text", "3. User input" }
    --
    -- local idx = utils.inputlist("Select input source:", options)
    -- if not idx then
    --   return nil
    -- end
    -- vim.cmd "redraw"
    --
    -- prompt_string = prompt_string:gsub("%$select", placeholders[idx])

    local items_map = {
      ["$clipboard"] = "Clipboard",
      ["$input"] = "User input",
      ["$yanked"] = "Yanked text",
      ["__CANCEL__"] = "Cancel (or press Esc)",
    }

    local choice
    choice, _ = utils.ui_select_sync({
      "$clipboard",
      "$input",
      "$yanked",
      string.rep("─", 100), -- Full-width visual break
      "__CANCEL__",
    }, {
      prompt = "Select input source",
      format_item = function(item)
        return items_map[item]
      end,
    })

    -- Arrive here after the user selection.
    if not choice or choice == "__CANCEL__" then
      return nil
    end
    prompt_string = prompt_string:gsub("%$select", choice)
  end

  -- Handle the ${input:<prompt>} syntax
  local cancelled = false
  prompt_string = prompt_string:gsub("%${input:(.-)}", function(prompt_text)
    local answer = vim.fn.input(prompt_text .. ": ")
    if answer == "" then
      cancelled = true
    end
    return (answer:gsub("%$", "\27"))
  end)

  if cancelled then
    return nil
  end

  -- Handle the $input syntax
  if string.find(prompt_string, "%$input") then
    local answer = vim.fn.input "Input: "
    if answer == "" then
      return nil
    end
    prompt_string = prompt_string:gsub("%$input", (answer:gsub("%$", "\27")))
  end

  if cancelled then
    return nil
  end

  -- Handle the ${file:<filename>} syntax
  prompt_string = prompt_string:gsub("%${file:(.-)}", function(file_name)
    file_name = M.resolve_prompt_path(file_name)
    utils.debug("Reading file: " .. vim.inspect(file_name))
    local file_content, err = utils.read_file_to_string(file_name)
    if not file_content then
      utils.notify("Error: " .. err, vim.log.levels.ERROR)
      return file_content
    end
    return (file_content:gsub("%$", "\27"))
  end)

  prompt_string = prompt_string:gsub("%$clipboard", "$register_+")
  prompt_string = prompt_string:gsub("%$yanked", "$register_0")

  local register_error = false
  prompt_string = prompt_string:gsub('%$register_([%w*+:/"])', function(r_name)
    local register = vim.fn.getreg(r_name)
    if not register or register:match "^%s*$" then
      local msg = "Register" .. r_name
      if r_name == "+" then
        msg = "Clipboard"
      elseif r_name == "0" then
        msg = "Yanked text"
      end
      utils.notify(msg .. " is empty", vim.log.levels.ERROR)
      register_error = true
      return ""
    end
    return (register:gsub("%$", "\27"))
  end)
  if register_error then
    return nil
  end

  prompt_string = prompt_string:gsub("%$filetype", (vim.bo.filetype:gsub("%$", "\27")))

  prompt_string = prompt_string:gsub("\27", "$") -- Restore the $'s

  return prompt_string
end

return M
