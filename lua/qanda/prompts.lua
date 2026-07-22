local Config = require "qanda.config" -- User configuration options
local State = require "qanda.state"
local utils = require "qanda.utils"
local ui = require "qanda.ui"
local curl = require "qanda.curl"

local M = {
  CURSOR_TAG = "\02(.-)\02", -- Prompt cursor placeholder tag
  APPEND_CHAT_TAG = "\04", -- Prompt new chat tag
  user_prompts = {}, ---@type Prompts
  system_messages = {}, ---@type Prompts
}

--- Sets up the prompt module, including loading templates and setting the default system message.
function M.setup()
  State.system_message = nil

  -- Close existing Prompt window
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      -- vim.schedule waits until the current main loop finishes
      -- This ensures the session is 100% loaded before we touch windows
      vim.schedule(function()
        pcall(utils.close_ephemeral_window, Config.PROMPT_BUFFER_NAME)
      end)
    end,
  })

  -- Load user prompt and system message templates
  M.load_user_templates()
  M.load_system_templates()

  -- Set global system message
  local system_message_template = State.saved_state.system_message_template
  if system_message_template then
    local template = M.get_prompt(M.system_messages, system_message_template)
    if template then
      M.set_system_message(template)
    end
  end

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

--- Sets the active system message.
--- If `system_message` is `nil`, the system message is disabled.
--- Expands placeholders in the system message content.
--- @param system_message_template Prompt|nil The system message template, or `nil` to disable.
--- @param opts? { update_chat: boolean } If `update_chat=true` then update the current chat's system message.
function M.set_system_message(system_message_template, opts)
  opts = opts or {}

  local win = State.chat_window

  local refresh_chat_window = function()
    if win.current_turn and win.current_turn == win.chat.turns[1] then
      local lines = require("qanda.chats").turn_to_lines(win.chat, win.current_turn)
      win:set_lines(lines)
    end
  end

  if system_message_template ~= nil then

    -- Clone and expand the template and assign to State.system_message
    local system_message = vim.tbl_deep_extend("force", {}, system_message_template)
    local expanded = M.substitute_placeholders(system_message.content)
    if not expanded then
      return
    end
    system_message.content = expanded
    State.system_message = system_message
    State.saved_state.system_message_template = system_message.name

    if opts.update_chat then
      -- Update it in the current chat
      if win.chat and #win.chat.turns > 0 then
        win.chat.turns[1].system = expanded
      end
      refresh_chat_window()
    end

  else

    -- Disable system message
    State.system_message = nil
    State.saved_state.system_message_template = nil

    if opts.update_chat then
      -- Delete it from the current chat
      if win.chat and #win.chat.turns > 0 then
        win.chat.turns[1].system = nil
      end
      refresh_chat_window()
    end
  end
  State.save_state()
end

--- Parses markdown-style templates file into a Prompts array.
---Each prompt section starts and ends with `___`.
---The header envelopes prompt fields formatted like `<name>: <value>`.
---The `name` field (template name) is mandatory, all other fields are model options.
---@param lines string[] The full content of the markdown prompt file as an array of strings.
---@return Prompts|nil Returns a Prompts array or nil if parsing fails due to formatting errors.
local function parse_templates(lines)
  local result = {}
  local i = 1

  local match_ruler = function(line)
    return line:match "^___+%s*$"
  end

  while i <= #lines do
    -- Look for start of header
    if match_ruler(lines[i]) then
      i = i + 1
      local prompt = { model_options = {} }

      -- Parse header options until ending delimiter
      local header_start_line = i - 1
      while i <= #lines and not match_ruler(lines[i]) do
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
          if key == "name" then
            prompt[key] = value
          elseif key == "stream" then
            prompt.model_options[key] = value ~= "false"
          else
            prompt.model_options[key] = value
          end
        end
        i = i + 1
      end

      -- Check for missing closing header line
      if i > #lines or not match_ruler(lines[i]) then
        utils.notify("Missing closing header line after header starting at line " .. header_start_line, vim.log.levels.ERROR)
        return nil
      end

      -- Name is mandatory
      if not prompt.name or utils.trim_string(prompt.name) == "" then
        utils.notify("Missing mandatory template name in header starting at line " .. header_start_line, vim.log.levels.ERROR)
        return nil
      end

      -- Skip the ending delimiter
      i = i + 1

      -- Collect the prompt text until next header or EOF
      local prompt_lines = {}
      while i <= #lines and not match_ruler(lines[i]) do
        -- Skip HTML comment lines
        if not lines[i]:match "^<!--.-?-->$" then
          table.insert(prompt_lines, lines[i])
        end
        i = i + 1
      end

      -- Check we have a prompt
      prompt.content = table.concat(utils.trim_table(prompt_lines), "\n")
      if utils.trim_string(prompt.content) == "" then
        utils.notify("Missing prompt after header starting at line " .. header_start_line, vim.log.levels.ERROR)
        return nil
      end

      -- Create the prompt entry
      table.insert(result, prompt)
    else
      i = i + 1
    end
  end

  return result
end

--- Parses lines from the Prompt window into a Prompt object.
--- @param lines string[] The lines from the prompt buffer.
--- @return Prompt|nil The parsed prompt object, or `nil` if parsing fails.
local function parse_prompt(lines)
  if utils.trim_string(table.concat(lines, "\n")) == "" then
    utils.notify("Blank prompt", vim.log.levels.ERROR)
    return nil
  end

  local prompt = { model_options = {} }
  local i = 1

  local match_ruler = function(line)
    return line:match "^___+%s*$"
  end

  -- Match blank lines
  local match_blank_line = function()
    return lines[i]:match "^%s*$"
  end

  -- Skip leading blank lines
  while i <= #lines do
    if not match_blank_line() then
      break
    end
    i = i + 1
  end

  -- Process optional header
  if match_ruler(lines[i]) then
    i = i + 1

    -- Parse header options until ending delimiter
    while i <= #lines and not match_ruler(lines[i]) do
      -- Trim whitespace
      lines[i] = lines[i]:match "^%s*(.-)%s*$"

      -- Skip blank lines
      if not match_blank_line() then
        -- Check for malformed header option format
        local key, value = lines[i]:match "^([^:]+):%s*(.+)$"

        if not key or not value then
          utils.notify("Malformed header option format at line " .. i .. ": " .. lines[i], vim.log.levels.ERROR)
          return nil
        end

        -- Process prompt header fields
        if key == "stream" then
          prompt.model_options[key] = value ~= "false"
        else
          prompt.model_options[key] = value
        end
      end
      i = i + 1
    end

    -- Check for missing closing header line
    if i > #lines or not match_ruler(lines[i]) then
      utils.notify("Missing closing header line", vim.log.levels.ERROR)
      return nil
    end
    i = i + 1 -- Skip the ending delimiter
  end

  -- Collect the prompt content text until EOF
  local content_lines = {}
  while i <= #lines do
    table.insert(content_lines, lines[i])
    i = i + 1
  end

  -- Add content to prompt
  prompt.content = table.concat(utils.trim_table(content_lines), "\n")

  -- Check we have a prompt
  if utils.trim_string(prompt.content) == "" then
    utils.notify("Blank prompt", vim.log.levels.ERROR)
    return nil
  end

  return prompt
end

--- Converts a Prompt object into an array of lines suitable for display in a buffer.
--- @param prompt Prompt The prompt object to convert.
--- @return string[] An array of strings representing the prompt's content and metadata.
function M.prompt_to_lines(prompt)
  local lines = {}
  local rule = string.rep("_", 3)

  if prompt.name then
    table.insert(lines, "name: " .. prompt.name)
  end
  if prompt.model_options then
    for k, v in pairs(prompt.model_options) do
      table.insert(lines, k .. ": " .. v)
    end
  end
  if #lines > 0 then
    table.insert(lines, 1, rule)
    table.insert(lines, rule)
  end
  for _, v in ipairs(vim.split(utils.trim_string(prompt.content or ""), "\n")) do
    table.insert(lines, v)
  end
  return lines
end

--- Loads templates from files in the configured prompts directory.
--- @param role "user"|"system" The role of the templates to load.
--- @return Prompts An array of loaded prompt objects.
local function load_templates(role)
  assert(role == "user" or role == "system")

  local result = {} ---@type Prompts

  -- Read and merge all *.md templates files
  local glob_pattern = Config.prompts_dir .. "/*." .. role .. ".md"
  local template_files = vim.fn.glob(glob_pattern, false, true)

  -- If there are no role templates files then create default examples
  if #template_files == 0 then
    local path = Config.prompts_dir .. "/default." .. role .. ".md"

    -- Create parent directory if it does not already exist
    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end

    utils.notify("Creating default " .. role .. " templates file: " .. path, vim.log.levels.INFO)
    local f, err = io.open(path, "w")
    if not f then
      utils.notify("Error creating templates file '" .. path .. "': " .. (err or "unknown error"), vim.log.levels.ERROR)
      return result
    end
    local content
    if role == "user" then
      content = [[
<!-- Example user prompts templates installed by qanda.nvim -->
___
name: Dictionary definition
___
Briefly explain the meaning and etymology the following word: ${input:Enter word to find in dictionary}

___
name: Spell a word
___
What is the correct spelling for "${input:Enter word to spell}"

___
name: Synonyms
___
List synonyms for the word "${input:Enter a word to find synonyms}:

___
name: Antonyms
___
List antonyms for the word "${input:Enter a word to find antonyms}:
]]
    else
      content = [[
<!-- Example system message template installed by qanda.nvim -->
___
name: Generic
___
- Do not use introductory phrases like 'I understand' or 'Based on your request.', get straight to the point.
- Use bullet lists for multiple items.
]]
    end
    f:write(content)
    f:close()
    template_files = vim.fn.glob(glob_pattern, false, true)
    assert(#template_files == 1)
  end

  -- Load the templates files
  for _, file_path in ipairs(template_files) do
    if utils.file_exists(file_path) then
      local lines = vim.fn.readfile(file_path)
      if lines then
        local prompts
        prompts = parse_templates(lines)
        if prompts then
          for _, v in ipairs(prompts) do
            v.filename = file_path
            table.insert(result, v)
          end
        else
          utils.notify("Failed to parse templates from '" .. file_path .. "', skipping.", vim.log.levels.ERROR)
        end
      end
    end
  end
  return result
end

--- Loads system message templates from files and updates `M.system_messages` and `State.system_message`.
function M.load_system_templates()
  M.system_messages = load_templates "system"
  -- Sync the State.system_message prompt because loading creates new objects
  if State.system_message then
    for _, t in ipairs(M.system_messages) do
      if t.name == State.system_message.name then
        M.set_system_message(t)
        return
      end
    end
  end
end

--- Loads user prompt templates from files and updates `M.user_prompts`.
function M.load_user_templates()
  M.user_prompts = load_templates "user"
end

---Checks if the prompt specifies a system message template and validates it.
---@param prompt Prompt|nil The prompt object to check.
---@return Prompt|nil The system message template if specified and found, otherwise `nil`.
---@return boolean True if an error occurred (e.g. invalid template name), false otherwise.
function M.has_system_prompt(prompt)
  local result = nil
  local err = false
  if prompt and prompt.model_options and prompt.model_options.system then
    result = M.get_prompt(M.system_messages, prompt.model_options.system)
    if result == nil then
      utils.notify("Invalid system message template name: '" .. prompt.model_options.system .. "'", vim.log.levels.ERROR)
      err = true
    end
  end
  return result, err
end

---Open prompt window, load the prompt.
---If the prompt window does not exist, create it and attach key-mapped commands.
---@param prompt Prompt?
function M.open_prompt(prompt)
  local win = State.prompt_window ---@type UIWindow
  local already_open = win.winid ~= nil
  win:open()
  if not already_open then
    ui.move_float_by(win.winid, 5, 5)
  end
  win:set_title("Prompt [" .. Config.help_key .. " help]")
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = win.bufnr })
  M.add_prompt_syntax_highlighting(win.bufnr)

  if prompt then
    if prompt.content:find(M.APPEND_CHAT_TAG) ~= nil then
      prompt.content = prompt.content:gsub(M.APPEND_CHAT_TAG, "") -- Delete unused append chat tags
      utils.notify("New chat input placeholder suffixes ignored", vim.log.levels.WARN)
    end

    local lines = M.prompt_to_lines(prompt)
    win:set_lines(lines)

    -- Process cursor placeholder
    for i, line in ipairs(lines) do
      local s, e = line:find(M.CURSOR_TAG)
      if s then
        local cursor_prompt = line:match(M.CURSOR_TAG)
        local new_line = line:sub(1, s - 1) .. line:sub(e + 1)
        vim.api.nvim_buf_set_lines(win.bufnr, i - 1, i, false, { new_line })
        local col = s - 1
        vim.api.nvim_win_set_cursor(win.winid, { i, col })
        local insert_cmd = (col == #new_line) and "a" or "i" -- Append if at end of line
        vim.schedule(function()
          vim.api.nvim_feedkeys(insert_cmd, "n", false)
          if not utils.nil_or_blank(cursor_prompt) then
            local original_showmode = vim.o.showmode

            -- Restore showmode when the user leaves Insert mode
            vim.api.nvim_create_autocmd("InsertLeave", {
              once = true,
              callback = function()
                vim.o.showmode = original_showmode
              end,
            })

            vim.o.showmode = false -- So the notification is not overridden by status line "-- INSERT --"
            vim.notify(cursor_prompt, vim.log.levels.INFO)
          end
        end)

        break
      end
    end

  end

  -- Attach key commands.
  vim.keymap.set("n", Config.prompt_close_key, function()
    win:close()
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.prompt_switch_key, function()
    vim.cmd "Qanda /chat_window"
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v", "i" }, Config.prompt_submit_key, function()
    local lines = win:get_lines()
    win:close()
    local p = parse_prompt(lines)
    if p then
      local _, err = M.has_system_prompt(p)
      if err then
        return
      end
      p.content = p.content .. M.APPEND_CHAT_TAG
      require("qanda").execute_prompt(p)
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v", "i" }, Config.prompt_new_chat_key, function()
    local lines = win:get_lines()
    win:close()
    local p = parse_prompt(lines)
    if p then
      local _, err = M.has_system_prompt(p)
      if err then
        return
      end
      require("qanda.chats").new_chat()
      require("qanda.chats").open_chat()
      require("qanda").execute_prompt(p)
    end
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v", "i" }, Config.prompt_new_key, function()
    -- Clear the current buffer in the window
    vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
    -- Go to insert mode
    vim.cmd "startinsert"
  end, { buffer = win.bufnr })

  vim.keymap.set("n", Config.prompt_inject_key, utils.inject_files, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v", "i" }, Config.prompt_redo_key, function()
    local chat_window = State.chat_window
    if curl.is_active_job() then
      return
    end
    if #chat_window.chat.turns == 0 then
      utils.notify("Empty chat, there is nothing to redo", vim.log.levels.WARN)
      return
    end

    -- Delete the most recent turn
    table.remove(chat_window.chat.turns)
    chat_window.current_turn = nil
    require("qanda.chats").open_chat()

    -- Execute prompt
    local prompt_lines = win:get_lines()
    utils.trim_table(prompt_lines)
    local content = table.concat(prompt_lines, "\n")
    require("qanda").execute_prompt {
      content = content,
    }
  end, { buffer = win.bufnr })

  vim.keymap.set({ "n", "v", "i" }, Config.help_key, function()
    local help_message = ([[-- Prompt Window Commands --

- %s - Submit the prompt with the current chat
- %s - Submit the prompt in a new chat
- %s - Submit the prompt to the current chat replacing the latest turn
- %s - Clear the prompt window and enter insert mode
- %s - Switch to the Chat window †
- %s - Close the Prompt window †
- %s - Inject file(s) into the prompt †

† Normal mode

]]):format(
      Config.prompt_submit_key,
      Config.prompt_new_chat_key,
      Config.prompt_redo_key,
      Config.prompt_new_key,
      Config.prompt_switch_key,
      Config.prompt_close_key,
      Config.prompt_inject_key
    )
    vim.notify(help_message, vim.log.levels.INFO)
  end, { buffer = win.bufnr, desc = "Show Prompt window help" })
end

local prompt_syntax_rules = {
  QandaPromptProperty = [[\v^(name|prompt|system|temperature|top_p|max_tokens|stream):]],
  QandaPromptPlaceholder = [[\v\$(cursor|input|clipboard|yanked|register_.|register|files)|\$\{input:.{-}\}|\$\{file:.{-}\}|\$\{cursor:.{-}\}|\$\{shell:.*\}]],
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

--- Displays a Telescope picker for selecting, editing, and executing prompt and system templates.
--- @param prompts Prompts The array of templates to display.
--- @param display_entry? fun(prompt: Prompt): string? Optional function to format how each entry is displayed in the picker.
--- @param opts table? Optional configuration options for the Telescope picker.
local function template_picker(prompts, display_entry, opts)
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

      local lines = M.prompt_to_lines(prompt)

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
      M.add_prompt_syntax_highlighting(self.state.bufnr)
    end,
  }

  -- Create and run the telescope picker
  pickers
    .new(
      {},
      vim.tbl_deep_extend("force", {
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
        layout_config = Config.template_picker_layout,
      }, opts)
    )
    :find()
end

--- Displays a Telescope picker for user prompt templates, allowing selection, execution, or editing.
function M.prompt_template_picker()
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  template_picker(M.user_prompts, nil, {
    results_title = "Prompt Templates",
    preview_title = "Preview",
    prompt_title = "[" .. Config.help_key .. " help]",

    attach_mappings = function(picker_bufnr, map)

      map({ "n", "i" }, Config.prompt_picker_open_key, function()
        local selection = action_state.get_selected_entry()
        actions.close(picker_bufnr)
        if selection then
          local prompt = selection.value
          assert(prompt)
          -- Expand prompt template and open in Prompt window
          coroutine.wrap(function()
            prompt = vim.tbl_deep_extend("force", {}, prompt)
            local expanded = M.substitute_placeholders(prompt.content)
            if expanded then
              prompt.name = nil -- Convert prompt template to an anonymous (expanded) prompt
              prompt.content = expanded
              vim.schedule(function()
                M.open_prompt(prompt)
              end)
            end
          end)()
        else
          utils.notify("User cancelled", vim.log.levels.INFO)
        end
      end, { desc = "Expand the prompt template and open in the prompt window" })

      map({ "n", "i" }, Config.prompt_picker_exec_key, function()
        local selection = action_state.get_selected_entry()
        actions.close(picker_bufnr)
        if selection then
          -- State.prompt_window:close()
          require("qanda").execute_prompt(selection.value)
        else
          utils.notify("User cancelled", vim.log.levels.INFO)
        end
      end, { desc = "Expand and execute the selected prompt template" })

      map({ "n", "i" }, Config.prompt_picker_edit_key, function()
        local selection = action_state.get_selected_entry()
        if selection then
          local prompt = selection.value
          assert(prompt)
          actions.close(picker_bufnr)
          if prompt.filename then
            utils.edit_file(prompt.filename, M.add_prompt_syntax_highlighting, "^name:%s*" .. utils.escape_pattern(prompt.name), function()
              M.load_user_templates() -- Reload templates after edited file is saved
            end)
          else
            utils.notify("No file associated with built-in prompt '" .. prompt.name .. "'", vim.log.levels.WARN)
          end
        end
      end, { desc = "Close the picker and edit prompts file containing the selected prompt" })

      map({ "n", "i" }, Config.help_key, function()
        local help_message = ([[-- User Prompt Template Picker Commands --

- %s - Expand the prompt template and open in the prompt window
- %s - Expand and execute the selected prompt template
- %s - Edit the prompt templates file

]]):format(Config.prompt_picker_open_key, Config.prompt_picker_exec_key, Config.prompt_picker_edit_key)
        vim.notify(help_message, vim.log.levels.INFO)
      end, { buffer = picker_bufnr, desc = "Show User prompt picker help" })

      return true
    end,
  })
end

--- Displays a Telescope picker for system message templates, allowing selection, disabling, or editing.
function M.system_template_picker()
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local finders = require "telescope.finders"

  local function display_entry(prompt)
    if State.system_message and prompt.name == State.system_message.name then
      return "* " .. prompt.name
    else
      return "  " .. prompt.name
    end
  end

  local function make_finder()
    local picker_entries = {}
    for _, prompt in ipairs(M.system_messages) do
      table.insert(picker_entries, prompt)
    end
    table.sort(picker_entries, function(a, b)
      return a.name < b.name
    end)
    return finders.new_table {
      results = picker_entries,
      entry_maker = function(prompt)
        return {
          value = prompt,
          display = display_entry(prompt),
          ordinal = prompt.name,
        }
      end,
    }
  end

  template_picker(M.system_messages, display_entry, {
    results_title = "System Templates",
    preview_title = "Preview",
    prompt_title = "[" .. Config.help_key .. " help]",
    attach_mappings = function(picker_bufnr, map)

      map({ "n", "i" }, Config.system_picker_select_key, function()
        local selection = action_state.get_selected_entry()
        if selection then
          M.set_system_message(selection.value, { update_chat = true })
          local current_picker = action_state.get_current_picker(picker_bufnr)
          current_picker:refresh(make_finder())
        end
      end, { desc = "Set the system message and refresh the picker" })

      map({ "n", "i" }, Config.system_picker_disable_key, function()
        local selection = action_state.get_selected_entry()
        if selection then
          M.set_system_message(nil, { update_chat = true })
          local current_picker = action_state.get_current_picker(picker_bufnr)
          current_picker:refresh(make_finder())
        end
      end, { desc = "Disable the system message and refresh the picker" })

      map({ "n", "i" }, Config.system_picker_edit_key, function()
        local selection = action_state.get_selected_entry()
        if selection then
          local prompt = selection.value
          assert(prompt)
          actions.close(picker_bufnr)
          if prompt.filename then
            utils.edit_file(prompt.filename, M.add_prompt_syntax_highlighting, "^name:%s*" .. utils.escape_pattern(prompt.name), function()
              M.load_system_templates() -- Reload templates after edited file is saved
            end)
          else
            utils.notify("No file associated with built-in prompt '" .. prompt.name .. "'", vim.log.levels.WARN)
          end
        end
      end, { desc = "Close the picker and edit system templates file containing the selected prompt" })

      map({ "n", "i" }, Config.help_key, function()
        local help_message = ([[-- System Message Template Picker Commands --

- %s - Enable the system message
- %s - Disable the system message
- %s - Edit the system message templates file
- <Esc> - Close the picker

]]):format(Config.system_picker_select_key, Config.system_picker_disable_key, Config.system_picker_edit_key)
        vim.notify(help_message, vim.log.levels.INFO)
      end, { buffer = picker_bufnr, desc = "Show System message picker help" })

      return true
    end,
  })
end

--- Prompt template file name expansion. Used for `${file:<filename>}` placeholder expansion.
---
--- - If the file name has no directory component, it is assumed to reside in configuration `prompts` directory
--- - If the file name is relative (e.g., "my/path/file.txt"), it is resolved relative
---   to `Config.ROOT_DIR`.
--- - If the file name is already absolute (e.g., "/home/user/file.txt"), it is returned as is.
---
--- @param file_path string The file path to convert.
--- @return string The absolute file path.
function M.resolve_prompt_path(file_path)
  -- Check if the file_path is just a filename (no directory separators).
  -- vim.fn.fnamemodify(file_path, ':t') extracts only the filename part.
  -- If it's equal to the original file_path, then there was no directory component.
  if vim.fn.fnamemodify(file_path, ":t") == file_path then
    -- If it's just a filename, prepend prompts_dir and then resolve to an absolute path.
    local full_path = Config.prompts_dir .. "/" .. file_path
    return vim.fn.fnamemodify(full_path, ":p")
  elseif vim.fn.fnamemodify(file_path, ":p") == file_path or file_path:sub(1, 1) == "~" then
    -- Already absolute or starts with '~'; expand and return as is.
    return vim.fn.fnamemodify(file_path, ":p")
  else
    -- Relative path with directory components: resolve relative to Config.ROOT_DIR.
    local full_path = Config.ROOT_DIR .. "/" .. file_path
    return vim.fn.fnamemodify(full_path, ":p")
  end
end

--- Substitutes placeholders in the prompt template with actual values.
---This function processes a prompt string and replaces special placeholders
---with their corresponding values.
---Placeholders within placeholder values are not replaced.
---
---@param prompt_string string The prompt string containing placeholders to substitute
---@return string|nil The prompt with placeholders substituted, or `nil` if processing should abort i.e. user cancelled or substitution error.
function M.substitute_placeholders(prompt_string, opts)
  -- Convert no-prompt syntax to canonical form
  prompt_string = prompt_string:gsub("%$cursor", "${cursor:}")

  -- Non-printable character is used to escape placeholders to ensure occurrences in substituted text are ignored.
  local DOLLAR_TAG = "\03"

  -- Non-printable characters are used to escape cursor placeholders to ensure occurrences in substituted text are ignored.
  prompt_string = prompt_string:gsub("%${cursor:([^\n]-)}", "\02%1\02", 1)

  opts = opts or {}

  -- Convert no-prompt syntax to canonical form
  prompt_string = prompt_string:gsub("%$input", "${input:}")

  -- Handle the ${input:<prompt>} syntax
  local cancelled = false
  prompt_string = prompt_string:gsub("%${input:([^\n]-)}", function(prompt_text)
    if utils.nil_or_blank(prompt_text) then
      prompt_text = "Input"
    end
    local answer = vim.fn.input(prompt_text .. ": ")
    if answer == "" then
      cancelled = true
    end
    if answer:match " %+$" then
      answer = answer:gsub(" %+$", M.APPEND_CHAT_TAG)
    end
    -- NOTE: `text:gsub("%%", "%%%%")` doubles every `%` so that the outer `gsub` interprets each `%%` as a literal `%` in the output.
    return (answer:gsub("%%", "%%%%"):gsub("%$", DOLLAR_TAG))
  end)
  if cancelled then
    utils.notify("User cancelled", vim.log.levels.INFO)
    return nil
  end

  -- Handle the ${file:<filename>} syntax
  local file_error = false
  prompt_string = prompt_string:gsub("%${file:([^\n]-)}", function(file_name)
    file_name = M.resolve_prompt_path(file_name)
    local file_content, err = utils.read_file_to_string(file_name)
    if file_content == nil then
      file_error = true
      utils.notify("Error: " .. err, vim.log.levels.ERROR)
      return ""
    end
    return (file_content:gsub("%%", "%%%%"):gsub("%$", DOLLAR_TAG))
  end)
  if file_error then
    return nil
  end

  -- Handle the ${shell:<command>} syntax
  local shell_error = false
  prompt_string = prompt_string:gsub("%${shell:([^\n]*)}", function(cmd) -- Greedy match but don't cross line boundaries
    local ok, out = pcall(function()
      return vim.fn.system(cmd)
    end)
    if not ok or vim.v.shell_error ~= 0 then
      shell_error = true
      utils.notify("Error executing shell command: " .. cmd .. ": " .. out, vim.log.levels.ERROR)
      out = "${shell:" .. cmd .. "}"
    end
    -- escape any `%` and `$` that the user may want to keep literally
    return (out:gsub("%%", "%%%%"):gsub("%$", DOLLAR_TAG))
  end)
  if shell_error then
    return nil
  end

  -- Handle the $files syntax
  -- NOTE: Cannot use gsub with a callback here because concat_files_as_markdown_sync
  -- yields (via coroutine), and gsub is a C function that cannot be yielded across.
  if string.find(prompt_string, "%$files") then
    local lines = utils.concat_files_as_markdown_sync()
    if #lines == 0 then
      return nil
    end
    local text = table.concat(lines, "\n")
    prompt_string = prompt_string:gsub("%$files", (text:gsub("%%", "%%%%"):gsub("%$", DOLLAR_TAG)))
  end

  prompt_string = prompt_string:gsub("%$clipboard", "$register_+")
  prompt_string = prompt_string:gsub("%$yanked", "$register_0")

  prompt_string = prompt_string:gsub('%$register_([%w*+:/"])', function(r_name)
    local register = vim.fn.getreg(r_name)
    if not register or utils.trim_string(register) == "" then
      local msg = "Register" .. r_name
      if r_name == "+" then
        msg = "Clipboard"
      elseif r_name == "0" then
        msg = "Yanked text"
      end
      utils.notify(msg .. " is empty", vim.log.levels.WARN)
      return ""
    end
    return (register:gsub("%%", "%%%%"):gsub("%$", DOLLAR_TAG))
  end)

  prompt_string = prompt_string:gsub(DOLLAR_TAG, "$") -- Restore the $'s

  return prompt_string
end

return M
