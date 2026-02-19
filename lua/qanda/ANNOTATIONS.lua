---@meta

-- UI definitions --

---@alias UIMode
---| "linked"     # Linked floating Prompt and Chat windows
---| "separate"   # Floating Prompt window and normal Chat window

--- Display mode for opening a window.
---@alias WindowMode
---| '"normal"'  # Open in the current window (default)
---| '"float"'   # Open in a floating window
---| '"top"'     # Horizontal split above
---| '"bottom"'  # Horizontal split below
---| '"left"'    # Vertical split to the left
---| '"right"'   # Vertical split to the right

---@class FloatLayout
---@field width number Width of the float as a percentage of editor width (default: 0.8)
---@field height number Height of the float as a percentage of editor height (default: 0.8)
---@field border string Border style ("single", "double", "rounded", etc.) (default: "single")
---@field style string Window style (default: "minimal")
---@field [string] any Additional options forwarded to the underlying `vim.api.nvim_open_win` window creation function.

---@class UIWindow
---@field mode WindowMode
---@field bufnr number
---@field winid number
---@field modifiable boolean
---@field buf_name string? The name of the buffer. Required if bufnr is not provided and window is to be opened.
---@field setlocal? string Vim `:setlocal` options. Summary:
---| - `buftype=nofile` : No disk I/O
---| - `buflisted=true` : Shows in `:ls`
---| - `bufhidden=hide` : Buffer persists when not shown
---| - `bufhidden=wipe` : Buffer erased entirely
---@field float_layout FloatLayout
---@field [string] any Additional options forwarded to the underlying window creation function.

-- Model definitions --

---@class Provider
---@field name string The filename of the provider (without extension)
---@field module table The required Lua module for the provider
---@field model? string The name of the current provider model

---@alias Providers Provider[]

---@class Message
---@field role Role The role of the model message
---@field content string The text of the message

---@class RequestData : { [string]: any } Model request data (model, messages et al)
---@field model string
---@field messages Message[]

---@class Request
---@field host? string
---@field port? string
---@field data RequestData

---@alias Role "user" | "assistant" | "system" | "tool"

---@class Prompt
---@field name string The prompt name.
---@field prompt string The prompt string.
---@field extract string? A regex pattern to extract content from the model's response.
---@field model string? The model name to use for this prompt.
---@field model_options table? Additional model request fields
---@field filename string? The prompt definition's source file

---@alias Prompts Prompt[]

---@class ChatMessage
---@field role Role The role of the message sender
---@field content string The text of the message
---@field model? string The model used (optional, usually present for user/assistant)
---@field date? string The timestamp of the message (optional)

---@class Chat
---@field name string The title or topic of the chat
---@field messages ChatMessage[] A list of messages in the conversation

---@alias Chats Chat[]

