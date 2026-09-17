# Jarvis

**Jarvis** is a native, privacy-first desktop AI assistant for macOS built with SwiftUI and AppKit. It connects directly to local Large Language Models running via [LM Studio](https://lmstudio.ai/) to provide autonomous reasoning, tool execution, and contextual assistance without sending any data to external servers.

---

## Key Features

- **Local & Private AI**: Fully offline execution powered by local models (such as Gemma 4, Qwen, or Llama) connected through LM Studio's local server (`http://127.0.0.1:1234`).
- **Autonomous Multi-Step Execution**:
  - Automatically plans and executes complex multi-step developer workflows.
  - Native batch file inspection (`read_multiple_files`) to analyze several files in a single inference cycle.
  - Safe terminal command execution with safety checks and sandboxing.
- **Transparent Reasoning & Execution Tracing**:
  - Step-by-step thinking processes collapsed into compact, interactive pills.
  - **Task Working Memory**: Preserves locked target lists and active progress checklists across turns.
  - One-click **"Copy Thoughts"** button to export the entire deliberation chain, checklist, and tool execution previews to the clipboard.
- **Granular Security Modes**:
  - **Always Ask (Strict)**: Requires explicit confirmation before executing any terminal command or file operation.
  - **Auto-Approve Read Only**: Automatically permits non-destructive read operations (`read_file`, `read_multiple_files`, `list_directory`) while requiring confirmation for shell commands and file modifications.
  - **Full Autonomous**: Seamless autonomous tool execution for trusted workflows.
  - **Whitelist & Always Allow**: Remember approval for specific base commands or native tools directly from the UI.
- **Context Management & Compression**:
  - Real-time token usage meter and context gauge.
  - Automatic compression boundaries to preserve conversation memory without exceeding model context windows.
- **Built-in Slash Command System**:
  - Quick access to commands via `/` key with an interactive search palette, category badges, and keyboard navigation (`Tab` autocomplete).
- **Native macOS Experience**:
  - Dark, Light, and System theme synchronization.
  - Optional Menu Bar Extra for fast access.
  - Zero external package dependencies—pure Swift, SwiftUI, and AppKit.

---

## Architecture Overview

```
Jarvis/
├── JarvisApp.swift                       # Application entry point and theme lifecycle
├── ContentView.swift                     # Primary chat window layout and turn grouping
├── ChatViewModel.swift                   # State manager for messages, streaming, and tool loop
├── LMStudioClient.swift                  # HTTP/SSE client for LM Studio's OpenAI-compatible API
├── AgentPromptManager.swift              # Dynamic system prompt & autonomous protocol generator
├── AgentInstructions.md                  # Base system directives and behavioral guidelines
├── ToolRegistry.swift                    # Tool definition schemas and execution dispatcher
├── ToolExecutionCardView.swift           # Interactive approval and tool output inspection card
├── PreResponseExecutionContainerView.swift# Collapsible container for thought pills & tool steps
├── PromptInputView.swift                 # Auto-expanding prompt field with slash command overlay
├── SlashCommandService.swift             # Slash command registry, autocomplete, and documentation
├── SettingsView.swift                    # Settings UI for themes, security modes, and whitelists
├── AppSettings.swift                     # Security policy definitions and auto-approval manager
├── FileSystemService.swift               # Local disk I/O, path resolution, and batch reading
├── ShellCommandService.swift             # Zsh subprocess execution and safety parser
└── ConversationStorageService.swift      # Local JSON conversation persistence (~/Library/Application Support)
```

---

## Tool Capabilities

| Tool | Purpose | Permissions |
| :--- | :--- | :--- |
| `read_multiple_files` | Read multiple files in a single batch turn | Auto-approved in Read-Only mode |
| `read_file` | Read the text contents of a single file | Auto-approved in Read-Only mode |
| `list_directory` | List folders, files, and sizes | Auto-approved in Read-Only mode |
| `create_directory` | Create folders and intermediate parents | Requires approval |
| `write_file` | Create or overwrite files atomically | Requires approval |
| `run_terminal_command` | Execute shell commands via `/bin/zsh` | Requires approval (unless whitelisted) |

---

## Security & Privacy

- All LLM inference runs 100% locally on your machine via LM Studio.
- Shell commands undergo syntax analysis before execution to detect chaining, subshell execution, or destructive redirects.
- Destructive actions require manual approval unless you explicitly configure whitelisting or choose Full Autonomous mode in Settings.
