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
---@field float_layout FloatLayout
---@field new fun(opts: table): UIWindow Constructor
---@field open fun(self: UIWindow, opts?: table) Focus or create the window. `opts` can initialize or override `UIWindow` fields.
---@field close fun(self: UIWindow) Close the window. The buffer is not deleted.
---@field is_open fun(self: UIWindow): boolean Return true if the window is open.
---@field set_title fun(self: UIWindow, title: string) Set window title
---@field set_cursor fun(self: UIWindow, cursor_position?: {row: number, col: number}) Activate and show cursor position. If `cursor_position` is `nil`, go to end of buffer.
---@field append fun(self: UIWindow, lines: string[]) Append lines and position cursor at end.
---@field get_lines fun(self: UIWindow): string[] Return list of buffer lines.
---@field set_lines fun(self: UIWindow, lines: string[]) Set buffer lines and position cursor at end.
---@field chat Chat? The Chat window chat object
---@field current_turn ChatTurn? Chat window current turn

-- State --

---@class State
---@field provider Provider
---@field chats Chats
---@field chat_window UIWindow
---@field prompt_window UIWindow
---@field system_message Prompt The current system message object
---@field recent_models Model[] A list of the most recently selected models

---@class SavedState -- Saved in STATE.json
---@field provider? string -- Most recently selected provider
---@field model? string -- Most recently selected model
---@field chat_file? string -- Most recently updated chat file
---@field system_message_template? string
---@field recent_models Model[] A list of the most recently selected models

-- Model definitions --

---@class Model
---@field provider_name string
---@field model_name string

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
---@field content string The prompt message string
---@field extract string? A regex pattern to extract content from the model's response
---@field system string? Name of system message template -- TODO: why is this necessary?
---@field provider? string The provider name
---@field model? string The model name
---@field model_options table? Additional model request fields
---@field filename string? The definition's source file

---@alias Prompts Prompt[]

---@class ChatTurn A model user request and response (called a turn or a turn-about)
---@field chat string? The chat name (if a custom value is set it is stored in the first turn)
---@field request string Model user prompt (expanded)
---@field response string Model response (extracted)
---@field system string? Model system message (expanded)
---@field provider string The provider name
---@field model string The model name
---@field model_options table? Additional model request fields inherited from a parent prompt and configuration
---@field extract string? A regex pattern to extract content from the model's response.
---@field timestamp string The time/date the request was sent
---@field duration number The time taken for the request in seconds

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

---@class CurlResponse
---@field data? string[] The aggregated response body data
---@field error? string Error message if the request failed
---@field duration? number Request duration in seconds

--- Diagnostic types
---@alias Diagnostic
---| '"curl_command"'
---| '"system_message"'
---| '"request"'
---| '"response"'

