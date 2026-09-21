# Getting Started & Configuration

This guide walks you through setting up, building, and configuring Jarvis on macOS.

---

## Prerequisites

1. **Hardware**: Apple Silicon Mac (M1, M2, M3, or M4 with Unified Memory).
2. **Operating System**: macOS 14.0 (Sonoma) or later.
3. **Developer Tools**: Xcode 15.0+ or Xcode Command Line Tools.
4. **Local Inference Host**: [LM Studio](https://lmstudio.ai/) (v0.3.0+ or v0.4.0+ recommended).

---

## Setting Up LM Studio

Jarvis communicates directly with the local LM Studio server at `http://127.0.0.1:1234`.

### 1. Install CLI tools
Open Terminal and bootstrap the LM Studio command-line interface:
```bash
lms bootstrap
```

### 2. Download Recommended Models
We recommend any modern reasoning or coding model with tool-use capabilities:
- **Gemma 4**: `google/gemma-4-e2b` or `google/gemma-4-12b`
- **Qwen 2.5 Coder**: `qwen2.5-coder-7b-instruct` or `qwen2.5-coder-14b-instruct`
- **Llama 3.1**: `meta-llama-3.1-8b-instruct`

---

## Building from Source

### Option A: Build with Xcode GUI

1. Clone the repository:
   ```bash
   git clone https://github.com/maksimsterkis/Jarvis.git
   cd Jarvis
   ```

2. Open the Xcode project:
   ```bash
   open Jarvis.xcodeproj
   ```

3. Select the `Jarvis` scheme and target **My Mac**.
4. Press `Cmd + R` to compile and run.

### Option B: Command-Line Build

Run a release build directly from your terminal:
```bash
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Release build
```

---

## Configuration & Settings

Open the **Settings panel** via `Cmd + ,` or from the **Jarvis** application menu.

### 1. Appearance & Theming
- **Theme**: Toggle between **System**, **Light**, and **Dark** mode. Changes apply immediately to window background and chrome.

### 2. Scrolling Behavior
- **Auto-Scroll & Snap to Prompt**: Follows streaming text during generation, then smoothly scrolls back to the prompt when finished.
- **Auto-Scroll Slash Palette on Hover**: Controls whether hovering over items in the slash command overlay automatically aligns scroll position.

### 3. Menu Bar Integration
- **Show Jarvis in macOS Menu Bar**: Adds a status bar icon in the top-right macOS menu bar for quick access or clean quitting.

### 4. Local Inference Engine
- **Server API**: Directly targets `http://127.0.0.1:1234`.
- **Launch Mode**:
  - **Headless (`lms`)**: Starts the fast background daemon without opening GUI windows.
  - **Desktop App**: Launches the full LM Studio desktop app.
- **Auto-Start Server on Launch**: Boots the local inference daemon and loads your selected model when Jarvis opens (disabled by default).
- **Unload Models & Stop Server on Quit**: Automatically unloads model weights and stops the LM Studio daemon when quitting Jarvis (if Jarvis started it).
- **CLI Detection**: Checks standard paths for `lms` and offers a one-click **"Toggle Server"** button.

### 5. Agent & Terminal Permissions
- **Action Approval Policy**:
  - **Strict (Always Ask)**: Requires approval for every read, write, and command.
  - **Auto-Approve Read Only** *(Default & Recommended)*: Auto-approves safe read calls (`read_file`, `read_multiple_files`, `list_directory`); prompts for modifications and shell commands.
  - **Full Autonomous**: Runs all tool calls without prompting.
- **Always-Allowed Whitelist**: View, revoke individual shell binaries (e.g. `git`, `swift`, `cargo`) or native tools, or click **"Revoke All"** to clear.
- **Agent Instructions File**: Direct button to inspect and edit `AgentInstructions.md`.
- **Auto-Collapse Command Output**: Automatically collapses tool output drawers when response generation completes.

*(Note: Reasoning token budgets are adjusted directly from the header toolbar thinking popover or via the [`/think`](commands.md#think) command, not in Settings.)*

---

## Related Documentation

- [Core Features & Capabilities](features.md)
- [Slash Commands & Shortcuts](commands.md)
- [Architecture & Execution Engine](architecture.md)
- [Security & Permission Gateway](security.md)
