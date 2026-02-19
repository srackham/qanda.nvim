local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"

local M = {
  prompts = {}, ---@type Prompts
}

function M.setup()
  M.load_prompts()
end

---Retrieve a prompt by its name.
---@param name string The name of the prompt.
---@return Prompt|nil The prompt.
function M.get_prompt(name)
  for _, prompt in ipairs(M.prompts) do
    if prompt.name == name then
      return prompt
    end
  end
  return nil
end

---Make a copy of `prompt`, set its name to `name` and add/replace to `M.prompts`.
---@param prompt Prompt The prompt.
---@param name string? The name of the prompt.
---@return Prompt The new prompt.
function M.set_prompt(prompt, name)
  local p = vim.tbl_deep_extend("force", {}, prompt)
  p.name = name or p.name
  utils.insert_replace(M.prompts, p, function(p1, p2)
    return p1.name == p2.name
  end)
  return p
end

--- Parses markdown-style prompt files into a Prompts array.
---Each prompt section starts and ends with either `---` or `___`.
---The header envelopes prompt fields formatted like `<name>: <value>`.
---Names not matching `name`, `model`, `extract` are added to the `model_options` table.
---| - name (string, required): Unique identifier for the prompt.
---| - model (string): Model name to use for this prompt.
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
          if not utils.table_contains({ "name", "model", "extract", "paste" }, key) then
            prompt.model_options[key] = value
          else
            -- Validate paste option (paste is DEPRECATED)
            if key == "paste" and not utils.table_contains({ "after", "before", "replace" }, value) then
              utils.notify("Invalid paste value '" .. value .. "' at line " .. i, vim.log.levels.ERROR)
              return nil
            end

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
--   return prompts_dir .. "/" .. name .. ".prompts.md"
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
  if prompt.model then
    table.insert(lines, "model: " .. prompt.model)
  end
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

-- ---@param prompt Prompt
-- ---@return string
-- local function prompt_to_string(prompt)
--   return table.concat(prompt_to_lines(prompt), "\n")
-- end

--- Initialise M.prompts table from prompts files (custom markdown file in the configuration prompts directory).
function M.load_prompts()
  local dot_prompt = M.get_prompt "."
  M.prompts = {}
  if dot_prompt then
    table.insert(M.prompts, dot_prompt) -- Restore ephemeral dot prompt
  end

  -- Read and merge prompts from all .prompts.md files
  local prompts_dir = Config.prompts_dir
  local glob_pattern = prompts_dir .. "/*.prompts.md"
  local prompt_files = vim.fn.glob(glob_pattern, false, true)

  -- If there are no prompts files then create one
  if #prompt_files == 0 then
    local path = Config.prompts_dir .. "/default.prompts.md"

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
            table.insert(M.prompts, v)
          end
        else
          utils.notify("Failed to parse prompts from '" .. file_path .. "', skipping.", vim.log.levels.ERROR)
        end
      end
    end
  end
end

local function edit_prompt(prompt)
  vim.cmd("edit " .. vim.fn.fnameescape(prompt.filename))
  local edited_bufnr = vim.api.nvim_get_current_buf()
  M.add_prompt_syntax_highlighting_rules(edited_bufnr)

  -- Position cursor at the line containing the prompt name
  local lines = vim.api.nvim_buf_get_lines(edited_bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("name:%s*" .. prompt.name) then
      vim.api.nvim_win_set_cursor(0, { i, 0 }) -- i is 1-indexed line number
      break
    end
  end
end

---Open prompt window, load the prompt.
---If the prompt window does not exist, create it and attach key-mapped commands.
---If the `prompt` is `nil` then don't load the prompt text into the window.
---@param prompt Prompt?
function M.open_prompt(prompt)
  local win = State.prompt_window
  win:open()
  if prompt then
    local lines = vim.split(prompt.prompt, "\n")
    win:set_lines(lines)
  end
  -- Attach key commands.
  vim.keymap.set("n", "q", function()
    win:close()
  end, { buffer = win.bufnr })
  vim.keymap.set("n", "<Tab>", function()
    vim.cmd "Qanda /chat"
  end, { buffer = win.bufnr })
  vim.keymap.set("n", "<C-Space>", function()
    local prompt_string = table.concat(win:get_lines(), "\n")
    win:close()
    require("qanda").execute_prompt_string(prompt_string)
  end, { buffer = win.bufnr })
end

local prompt_syntax_rules = {
  QandaPromptProperty = [[\v^(name|model|extract|prompt|temperature|top_p|max_tokens|stream):]],
  QandaPromptPlaceholder = [[\v\$(text|input|select|clipboard|yanked|filetype|register_.|register)|\$\{input:.{-}\}]],
}

-- Define highlight groups once (link to existing groups)
vim.api.nvim_set_hl(0, "QandaPromptProperty", { link = "Keyword" })
vim.api.nvim_set_hl(0, "QandaPromptPlaceholder", { link = "Identifier" })

--- Add extra syntax prompt file highlighting rules to a buffer
--- NOTE: Treesitter highlighting may override these.
---@param bufnr integer
function M.add_prompt_syntax_highlighting_rules(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    for group, pattern in pairs(prompt_syntax_rules) do
      vim.cmd(("syntax match %s /%s/"):format(group, pattern))
    end
  end)
end

---Displays a telescope picker for selecting, editing and executing prompts.
---@param callback function Callback to execute the selected prompt
function M.prompt_picker(callback)
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"
  local conf = require("telescope.config").values

  -- Prepare prompt data for telescope
  local prompt_names = {}
  for _, prompt in ipairs(M.prompts) do
    table.insert(prompt_names, prompt.name)
  end
  table.sort(prompt_names)

  -- Create previewer that shows the prompt value
  local prompt_previewer = previewers.new_buffer_previewer {
    define_preview = function(self, entry)
      local prompt_name = entry.value
      local prompt = M.get_prompt(prompt_name)

      assert(prompt)

      local lines = prompt_to_lines(prompt)

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      -- vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_prompt_syntax_highlighting_rules(self.state.bufnr)
    end,
  }

  -- Create and run the telescope picker
  pickers
    .new({}, {
      finder = finders.new_table {
        results = prompt_names,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry,
            ordinal = entry,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = prompt_previewer,
      attach_mappings = function(prompt_bufnr)

        -- Close the picker and open the prompt in the prompt window
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            local prompt = M.get_prompt(selection.value)
            M.open_prompt(prompt)
          else
            utils.notify("User cancelled", vim.log.levels.INFO)
          end
        end)

        -- Close the picker and execute the selected prompt template
        vim.keymap.set({ "n", "i" }, "<C-Space>", function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            callback(M.get_prompt(selection.value))
          else
            utils.notify("User cancelled", vim.log.levels.INFO)
          end
        end, { buffer = prompt_bufnr })

        -- Close the picker and edit prompts file containing the selected prompt
        vim.keymap.set({ "n", "i" }, "<C-e>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            local prompt_name = selection.value
            local prompt = M.get_prompt(prompt_name)
            assert(prompt)
            actions.close(prompt_bufnr)
            if prompt.filename then
              edit_prompt(prompt)
            else
              utils.notify("No file associated with built-in prompt '" .. prompt_name .. "'", vim.log.levels.WARN)
            end
          end
        end, { buffer = prompt_bufnr })

        return true
      end,
      layout_config = Config.prompt_picker_layout,
    })
    :find()
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

    local dot_prompt = M.get_prompt "."
    if dot_prompt then
      dot_prompt.prompt = prompt_string -- Remember the $select source in the dot prompt
    end
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
