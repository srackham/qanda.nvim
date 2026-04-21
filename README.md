# qanda.nvim

Qanda is an AI chatbot for Neovim.

An easy-to-use Neovim plugin for conversing with AI models.

> [!IMPORTANT]
> This is the 1.0 release, I use it daily on NixOS Linux with Neovim v0.11.6, but haven't tested on other systems.

## Features

- Familiar turn-about chatbot UI.
- Chats are persistent, resumable and editable.
- Reusable named prompt templates for customisable user messages (prompts) and system messages.
- Ollama, OpenRouter and Google Gemini model providers.
- Models and providers can be switched at any time.

## Overview

- The user engages in interactive turn-about _chats_ (conversations) with the selected AI model.
- _Chats_ are contextual, persistent, resumable and editable.
- The chat comprises one or more _turns_ (model request + model response).
- A turn is initiated with a user _prompt_ (a question or an instruction)
- Chats can include an optional _system message_

## Rationale

Qanda is for getting answers interactively from an AI, not for automated workflow execution.

It is first and foremost designed for easy on-boarding with a familiar prompt/response chat UI that doesn't get in your way.

There are plenty of feature-rich AI applications AI plugins out there and most are not designed for quick-fire Q&A sessions. Many are task specific and most impose a significant cognitive load.

Qanda is light on token consumption: model requests are explicit (there are no hidden contexts or model requests).

## Glossary of terms

- _chat_: An ordered series of model requests and responses pairs (turns) representing a single turn-based conversation.
- _turn_: (or "turn-about") is one full back-and-forth LLM request and response.
- _request_: The prompt, context and model options sent to the model.
- _response_: Data returned by the model and streamed to the chat window in response to a request.
- _context_: Each chat maintains it's own context comprising the chat's system message, user prompts, and model responses. When a new prompt is submitted to the model it is accompanied by current context.
- _prompt_: (or "user prompt") user questions and instructions submitted to the AI model from the prompt window.

> [!NOTE]
> A user prompt is not the same as a model request; a model request includes the user prompt along with the chat context (system message plus previous requests and responses) and model options.

## Qanda quick start

TODO:

## Qanda commands

| Command                         | Description                                        |
| ------------------------------- | -------------------------------------------------- |
| `:Qanda Prompt template name`   | Execute a named prompt template                    |
| `:Qanda /abort`                 | Abort the current model request                    |
| `:Qanda /chat_picker`           | Open the Chat picker                               |
| `:Qanda /chat_window`           | Open the Chat window                               |
| `:Qanda /dump_diagnostics`      | Display diagnostics for the previous model request |
| `:Qanda /model_picker`          | Select a model from the current provider           |
| `:Qanda /new_chat`              | Start a new Chat                                   |
| `:Qanda /new_prompt`            | Open a new Prompt                                  |
| `:Qanda /prompt_picker`         | Open the Prompt picker                             |
| `:Qanda /prompt_window`         | Open the Prompt window                             |
| `:Qanda /provider_picker`       | Select a provider and a model                      |
| `:Qanda /recent_models`         | Select from the list of recent models              |
| `:Qanda /status`                | Print Qanda status information                     |
| `:Qanda /system_message_picker` | Open the System Message picker                     |
| `:Qanda /turn_picker`           | Open the chat Turn picker                          |

- Qanda commands respond to tabbed command completion.
- See the [Example plugin configuration file](examples/example-qanda-configuration.lua) for example command key-mappings.

## Prompt window

![Alt text](screenshots/prompt-window.png)

The Prompt window is a floating window into which the user enters questions and instructions for the AI model. Prompt submission generates a model request which is saved, along with the model response, to a new chat Turn.

- A prompt is submitted for execution from the Prompt window or directly with a `:Qanda <prompt name>` command.
- A new prompt can be created with the `:Qanda /new_prompt`, with the `:Qanda /prompt_picker` command, or by resubmitting a previous prompt from the Chat window.
- The Prompt window implements the following key-mapped commands:
  - `<S-Enter>` - Submit the prompt to the current chat
  - `<C-s>` - Submit the prompt to a new chat
  - `<C-r>` - Submit the prompt to the current chat replacing the latest turn
  - `<C-Del>` - Clear the prompt window and enter insert mode
  - `<Tab>` - Switch to Chat window †
  - `<Esc>` - Close Prompt window †
  - `<Leader>fi` - Inject file(s) into the prompt †
  - `<C-h>` - List key-mapped commands

† Normal mode commands

## Chat window

![Alt text](screenshots/chat-window.png)

The Chat window displays a chat, one turn at a time. Open the chat window with the `:Qanda /chat_window` command, or from the _chat picker_ or _prompt window_.

- A new chat can be created with the `:Qanda /new_chat` command or directly from the _prompt window_.
- Chats are saved automatically at each turn and is updated with streamed response messages from model.
- The most recent chat is restored when you restart Neovim.
- Use the _chat picker_ to select and resume previous conversations.
- The chat window is read-only, you can't edit it directly.
- By default, the chat window is a floating window (see the `chat_window_mode` configuration option).
- Scroll the chat window turn-wise with the next (`<C-n>`) and previous (`<C-p>`) key-mapped commands.
- The turn in the Chat window can be re-prompted with the `<S-Enter>` key-mapped command — from the prompt window it can be resubmitted using the `<S-Enter>` and `<C-s>` key-mapped commands.
- The chat window implements the following key-mapped commands:
  - `<S-Enter>` - Create a new prompt from the current Chat window prompt
  - `<Tab>` - Switch to Prompt window
  - `<C-Del>` - Clear the prompt window and enter insert mode
  - `<C-p>/<C-n>` Scroll up/down for previous/next prompt (from the current chat message)
  - `<C-d>` - Delete current turn, if last turn delete the chat
  - `<C-e>` - Open the chat file for editing at the selected turn (by searching for the timestamp)
  - `<C-r>` - Delete then rerun the latest turn
  - `<C-k>` - Abort the current request
  - `<Esc>` - Close Chat window
  - `<C-z>` - Toggle truncated fields
  - `<C-h>` - List key-mapped command.

## Prompt template picker

![Alt text](screenshots/prompt-template-picker.png)

The _prompt template picker_ is used to select a user prompt template which is then expanded and opened in the _prompt window_. The _prompt template picker_ is opened with the `:Qanda /prompt_picker` command.

- The prompt template picker implements the following key-mapped commands:
  - `<Enter>` - Expand the prompt template and open in the prompt window
  - `<S-Enter>` - Expand and execute the selected prompt template
  - `<C-e>` - Edit prompt templates file
  - `<Esc>` - Close the picker

## System template picker

![Alt text](screenshots/system-template-picker.png)

The _system template picker_ is used to select and enable or disable the system message. It is opened with the `:Qanda /system_message_picker` command.

- The system template picker implements the following key-mapped commands:
  - `<Enter>` - Enable system message
  - `<C-d>` - Disable system message
  - `<C-e>` - Edit system message templates file
  - `<Esc>` - Close picker

In addition to setting the default system message:

- Disabling the System Message will delete it from the current Chat.
- Selecting the System Message will add/update it in the current Chat.

## Chat picker

![Alt text](screenshots/chat-picker.png)

The _chat picker_ is used to list, preview, select and manage chats. The `:Qanda /chat_picker` command opens the chat picker.

- The _chat picker_ allows previous chats to be selected and resumed.
- The _chat picker_ chronologically orders chats by chat timestamp i.e. a most recently created ordering.
- The most recent chat is restored when the plugin is loaded.
- The default chat name displayed in the chat picker is from the first words of the chat's first turn request (you can rename the chat with the chat picker `<C-s>` key-mapped command).
- The _chat picker_ implements the following key-mapped commands:
  - `<Enter>` - Open chat in Chat window
  - `<C-d>` - Delete selected chat
  - `<C-s>` - Rename selected chat
  - `<C-e>` - Edit the chat file
  - `<Esc>` - Close the picker

## Turn picker

![Alt text](screenshots/turn-picker.png)

The _turn picker_ displays the turns in the current chat, it implements the following key-mapped commands and is opened with the `:Qanda /turn_picker` command:

- `<Enter>` - Open selected turn in the chat window
- `<C-d>` - Delete selected turn
- `<C-z>` - Toggle truncated fields in preview window
- `<Esc>` - Close the picker

## Provider picker

![Alt text](screenshots/provider-picker.png)

Selects a model provider. When you select the provider you'll get prompted to select one of the provider's models. A provider health check is run each time a provider is selected.

The _provider picker_ is opened with the `:Qanda /provider_picker` command and implements the following key-mapped commands:

- `<Enter>` - Select the provider
- `<Esc>` - Close the picker

## Model picker

![Alt text](screenshots/model-picker.png)

Selects a model from a list of models belonging to the current provider. Opened with the `:Qanda /model_picker` command.

The _model picker_ implements the following key-mapped commands:

- `<Enter>` - Select the model
- `<Esc>` - Close the picker

## Recent model picker

![Alt text](screenshots/recent-model-picker.png)

The _recent model picker_ allow you to quickly switch between recently used models. It is opened with the `:Qanda /recent_models`
and implements the following key-mapped commands:

- `<Enter>` - Select the model
- `<Esc>` - Close the picker

Displayed model names are formatted like `<provider>/<model>`.

## Data files

Qanda maintains a number of history and session data files:

- The `session.json` file contains the session state which is restored at startup. It contains:
  - Current provider and model names
  - Most recently used chat file name
  - Current system message template name
  - The list of recently used models
- The `chats` directory containing chat files.
  - Each chat is saved in a separate [JSONL](https://jsonlines.org/) file named like `<creation-date>.chat.json` with date format `YYYYMMDD_HHMMSS` e.g. `20260224_104421.chat.jsonl`.
  - Within each chat file is a chronologically ordered list of JSON-formatted `ChatTurn` objects.

- The `prompts` directory containing prompt and system template files.

## Data directories

Qanda data files are sourced from two locations:

- The global Qanda data directory which is set by the `data_dir` configuration option (defaults to `vim.fn.stdpath "data" .. "/qanda_nvim"`).
- The optional Qanda local data directory `$PWD/.qanda_nvim`

If the optional local directory exists then it will source the `session.json` and optionally, the `prompts` and `chats` subdirectories.

- The `chats` directory contains the saved chats history (one file per chat).
- The `prompts` directory contains the user prompt templates and system message templates.
- If there is no local `chats` folder Qanda uses the global `chats` folder.
- If there is no local `prompts` folder Qanda uses the global `prompts` folder.

This scheme allows you to selectively share sessions, prompt templates and chats across projects.

Local data storage is initiated by creating a directory called `.qanda_nvim` in the project root directory. Creating sub-directories `prompts` and `chats` will confine prompt templates and chats to the project, otherwise they are sourced from the global locations.

For example, the following command in the project root directory create the local data folder and a sub-folder for chats; since we didn't create a `prompts` templates folder, they will be sourced from the global data store:

    mkdir -p .qanda_nvim/chats

## Prompt and System templates

Named templates for user prompts and system messages are selected and managed with the _prompt template picker_ and _system template picker_ respectively.

Both template types share the same format, they generate model request messages with "user" and "system" roles respectively.

- Templates are stored (one or more per file) in the directory set by the `prompts_dir` configuration option (`~/.local/share/nvim/qanda_nvim/prompts/` on most Linux systems).
- Template files are named like `*.user.md` or `*.system.md`.

### Template placeholders

The following placeholders can be used in prompt templates and system templates.

| Syntax                        | Description                                                       |
| ----------------------------- | ----------------------------------------------------------------- |
| `$input`, `${input:<prompt>}` | Prompts user for input and substitutes the value                  |
| `$clipboard`                  | Substitutes content of system clipboard (alias for `$register_+`) |
| `$yanked`                     | Substitutes most recently yanked text (alias for `$register_0`)   |
| `$select`                     | Prompts the user for an input source                              |
| `$filetype`                   | Substitutes current buffer's filetype                             |
| `$register_<register name>`   | Substitutes content of specified register                         |
| `${file:<file name>}`         | Inject text file                                                  |

- The `$select` placeholder allows the user to select from the `$clipboard`, `$text`, `$input` or `$yanked` inputs at the time of template substitution.
- The `$file` placeholder file location is determined by the file name directory prefix:
  - No directory prefix defaults to the Qanda `prompts` data directory e.g. `${file:AGENTS.md}`
  - A relative directory prefix is relative to the current working directory (reported by the `:pwd` command) e.g. `${file:./README.md}`
  - An absolute directory prefix can be used to specify any location e.g. `${file:~/.config/nvim/stylua.toml}`

### Template format

A template is a Markdown text file containing one or more templates separated by a template header.

A template header consists of one or more property declarations formatted like `<property-name>: <property-value>` and delimited top and bottom by a line containing three underscore characters.

- The `name` property is the displayed template name and is mandatory, all other properties are assumed to be model options.

Example prompt template:

```
___
name: Latin: Latin to English
temperature: 0.2
___
Translate the following Latin text to English:

$select
```

System templates can use the same placeholders as prompt templates (with the exception of input placeholders `$input` and `$select`). Here are a couple of examples of system templates:

```
___
name: Generic
temperature: 0.5
___
${file:GENERIC_RULES.md}

___
name: Sarcastic math teacher
___
You are a sarcastic math tutor. Use LaTeX for formulas.
```

## System messages

The System Message (sometimes called the system prompt or system instruction) is the "rulebook" you give an AI which shapes the LLM's persona. The models uses their "attention" layers to weigh the system prompt heavily throughout the entire generation process.

Qanda provides control and customisation of system messages with the _System template picker_. If a System Message has been set, then it will be included in the Chat's first Chat turn when the turn is executed.

## Model options

Model options from prompt and system message headers are passed through to the model, they include the likes of `temperature`, `max_tokens` etc. Model options are often provider or model specific. Options are **merged** from:

- Provider-specific configuration `model_options` (lowest priority)
- System message model options
- User prompt model options (highest priority)

## Configuration

### Authentication

Provider API keys are imported from exported shell environment variables, the variable name is specified in a provider specific `api_key` configuration option e.g.

```lua
-- Provider specific options
provider_options = {
  openrouter = { api_key = "$OPENROUTER_API_KEY" },
  gemini = { api_key = "$GEMINI_API_KEY" },
},
```

You can set the `api_key` with the actual key value (but not recommended for security reasons).

### Configuration options

Default configuration options can be found in [lua/qanda/config.lua](lua/qanda/config.lua).

### Example plugin configuration

Minimal plugin configuration:

```lua
return {
  "srackham/qanda.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    qanda.setup {
    -- Override default options here --
    }
  end,
}
```

Here's an [example plugin configuration file](examples/example-qanda-configuration.lua) with some key mappings.

## Tips

- The Chat and Prompt windows `<C-h>` help command displays a summary available window commands.
- Use the `:Qanda /dump_diagnostics` command to view the model request and response generated by the most recently executed turn.

- If Neovim is configured to persist the Neovim registers across sessions the Qanda `/dump_diagnostics` command will also persist across sessions. Set the maximum number of shada lines saved to accommodate the diagnostics e.g. to 999:

      vim.opt.shada = "!,'100,<999,s10,h"

- Executing a prompt template from the _Prompt picker_ previews the expanded prompt in the _Prompt window_; the preview is skipped if you execute a prompt template using the `:Qanda` command.
