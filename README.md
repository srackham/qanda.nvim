TODO:

- Create sections outline
- Copy relevant NOTES.md notes
- Write an AI prompt to generate the README

# qanda.nvim

An easy-to-use Neovim plugin for conversing with AI models.

There are plenty of feature-rich AI applications AI plugins out there; most impose a cognitive load and a learning curve; many are oriented towards task-specific workflows.

Qanda.nvim is for conversing with an AI, not for workflow execution. It is first and foremost designed for easy on-boarding with a familiar prompt/response chat UI that doesn't get in your way (the default window mappings were chosen for single-key activation and dismissal).

## Features

- Familiar turn-about chatbot UI.
- Ollama, OpenRouter and Google Gemini model providers.
- Models can be switched at any time with the _Recent Models_ picker.
- Conversations (chats) are persistent, resumable and editable.
- Reusable named prompt templates for customisable user messages (prompts) and system messages.
- Template placeholders for prompt inputs.

## Glossary of terms
prompt, user prompt
Prompt window
Chat window
Chat picker
Prompt template picker
system message
System message picker
Model picker
Provider picker
Most recent models picker
turn
chat
request
response
model
provider
session

## Tips

- If Neovim is configured to persist the Neovim registers across sessions the Qanda `/dump_diagnostics` command will also persist across sessions.
- Executing a prompt template from the Prompt picker previews the expanded prompt in the Prompt window; the preview is skipped if you execute a prompt template using the `:Qanda` command.
- If the `new_chat_on
- Chat files are updated after each successful turn.
- You can reinject the current system message into the model messages list by reselecting it with the System Message picker.

## Model options

Model options include the likes of `temperature`, `max_tokens` etc. and are merged from:

- Configuration `model_options` (lowest priority)
- System message model options
- User prompt model options (highest priority)

### Prompt window
- You can create a new prompt from a previous prompt by navigating to it in the Chat window then pressing `<Enter>`.

## Session data
Session data includes:

- The `session.json` file contains the session state which is restored at startup. It contains:
    - Current provider and model names
    - Most recently used chat file name
    - Current system message name
- The `chats` directory containing chat files.
- The `prompts` directory containing prompt template files.

## Session data directories
Session data is sourced from two locations:

- The global data directory which is set by the `data_dir` configuration option (defaults to `vim.fn.stdpath "data" .. "/qanda_nvim"`).
- The option local data directory `$PWD/.qanda_nvim`

If the optional local directory exists then it will store the `session.json` and optionally the `prompts` and `chats` directories.

- The `chats` directory contains the saved chats history (one file per chat).
- The `prompts` directory contains the user prompt templates and system message templates.
- If there is no local `chats` folder Qanda uses the global `chats` folder.
- If there is no local `prompts` folder Qanda uses the global `prompts` folder.

This scheme allows you to selectively share session, prompt templates and chats across projects.

Local data storage is initiated by creating a directory called `.qanda_nvim` in the project root directory. Creating sub-directories `prompts` and `chats` will confine prompt templates and chats to the project.

For example, the following command in the project root directory create the local data folder and a sub-folder for chats; since we didn't create a `prompts` templates folder, they will be sourced from the global data store:

    mkdir -p .qanda_nvim/chats

