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

Open the **Settings panel** via `Cmd + ,` or from the **Jarvis** menu.

### 1. Appearance & Menu Bar
- **Theme**: Toggle between **System**, **Light**, and **Dark** mode.
- **Menu Bar Extra**: Enable the status bar icon for quick background status and fast access.

### 2. Local Inference Engine
- **Launch Mode**:
  - **Headless (`lms`)**: Fast, background CLI daemon without GUI windows.
  - **Desktop App**: Launches the full LM Studio application interface.
- **Auto-Start Server on Launch**: Automatically boots the local inference daemon and loads your default model when Jarvis opens.
- **Unload Models & Stop Server on Quit**: When closing Jarvis, automatically unloads model weights and stops the background server if Jarvis was the process that started it.

### 3. Security Policies & Whitelist
- **Security Mode**:
  - **Strict (Always Ask)**: Prompts for all reads, writes, and commands.
  - **Auto-Approve Read Only** *(Recommended)*: Seamless read-only browsing; writes and commands require confirmation.
  - **Full Autonomous**: Hands-free execution for automated tasks.
- **Command Whitelist**: Review, add, or revoke pre-approved binaries (e.g. `swift`, `git`, `python3`).

### 4. Default Reasoning Budget
Configure the initial thinking token budget for models with reasoning support:
- **Low**: ~1,024 tokens
- **Medium**: ~4,096 tokens
- **High**: ~8,192 tokens
- **Max**: ~16,384 tokens

---

## Related Documentation

- [Core Features & Capabilities](features.md)
- [Slash Commands & Shortcuts](commands.md)
- [Architecture & Execution Engine](architecture.md)
- [Security & Permission Gateway](security.md)
