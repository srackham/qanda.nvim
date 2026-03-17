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
---@field [string] any Additional options forwarded to the underlying window creation function TODO: is this comment correct?

-- Model definitions --

---@class Provider
---@field name string The filename of the provider (without extension)
---@field module table The required Lua module for the provider
---@field model? string The name of the current provider model

---@alias Providers Provider[]

---@alias Role "user" | "assistant" | "system"

---@class Message
---@field role Role The role of the model message
---@field content string The text of the message

---@class RequestData
---@field model string
---@field provider string
---@field model_options table? Additional model request fields
---@field messages Message[]

---@class Request
---@field host? string From Config
---@field port? string From Config
---@field data RequestData

---@readonly
---@class Prompt An immutable prompt template loaded from user prompt template files or previously executed prompt extracted from chat history
---@field name? string The prompt name
---@field prompt string The prompt string
---@field expanded? string The prompt string after placeholder expansion
---@field extract string? A regex pattern to extract content from the model's response
---@field system string? Name of system prompt template
---@field provider? string The provider name
---@field model? string The model name
---@field model_options table? Additional model request fields
---@field filename string? The prompt definition's source file
---@field consumed boolean? Flag the prompt as having been appended to the model messages array

---@alias Prompts Prompt[]

---@class ChatTurn A model user request and response (called a turn or a turn-about)
---@field chat string? The chat name (if a custom value is set it is stored in the first turn)
---@field request string Model prompt (expanded)
---@field response string Model response (extracted)
---@field system string? System prompt (expanded)
---@field provider string The provider name
---@field model string The model name
---@field model_options table? Additional model request fields inherited from a parent prompt and configuration
---@field extract string? A regex pattern to extract content from the model's response.
---@field timestamp string The time/date the request was sent

---@class Chat
---@field turns ChatTurn[] A list of conversation request/response pairs
---@field filename string? The chat JSONL file path, set when the chat is saved for the first time

---@alias Chats Chat[]

-- Model command execution --

---@alias JobStatus
---| "running"
---| "stopped"
---| "error"
---| "aborted"

