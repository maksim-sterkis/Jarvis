# Jarvis

<p align="center">
  <strong>Native, Privacy-First Autonomous AI Desktop Assistant for macOS</strong><br>
  Powered by Local LLMs via LM Studio • Built with 100% Native SwiftUI & AppKit • Zero External Dependencies
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0+-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon-blue?style=flat-square&logo=apple" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-5.10-orange?style=flat-square&logo=swift" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%26%20AppKit-purple?style=flat-square" alt="SwiftUI & AppKit">
  <img src="https://img.shields.io/badge/Inference-100%25%20Local%20(LM%20Studio)-green?style=flat-square" alt="LM Studio">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square" alt="MIT License">
</p>

---

## Overview

**Jarvis** is an autonomous developer copilot running natively on macOS. Unlike cloud-based AI tools, Jarvis operates **100% locally** by interfacing directly with local Large Language Models (LLMs) hosted inside [LM Studio](https://lmstudio.ai/) (e.g. Gemma 4, Qwen 2.5, Llama 3).

Jarvis inspects multi-file codebases, executes terminal workflows, runs test suites, creates project structures, and reasons through complex programming tasks—**all without sending a single byte of telemetry or code to external servers**.

---

## 📚 Documentation Index

Explore the comprehensive documentation guides in the [`docs/`](docs/) directory:

| Guide | Description |
| :--- | :--- |
| 🚀 **[Getting Started & Configuration](docs/getting-started.md)** | Hardware prerequisites, LM Studio setup, building from source, and settings. |
| 🏗️ **[Architecture & Execution Engine](docs/architecture.md)** | Subsystem diagrams, autonomous plan-and-solve sequence, and codebase file tree. |
| 🛡️ **[Security & Permission Gateway](docs/security.md)** | 3-tier security policy, permission flowchart, whitelist engine, and shell heuristics. |
| ⚡ **[Core Features & Capabilities](docs/features.md)** | Deep dive into inference lifecycle, reasoning popovers, playbooks, and context compression. |
| 🛠️ **[Tool Ecosystem Reference](docs/tools.md)** | Complete parameter schemas and behaviors for all 6 native system tools. |
| ⌨️ **[Slash Commands & Shortcuts](docs/commands.md)** | Interactive command overlay, dynamic argument autocomplete, and keyboard shortcuts. |

---

## Key Highlights

- **100% Air-Gapped & Private**: Interconnects with LM Studio at `http://127.0.0.1:1234`. No API keys, zero cloud relays.
- **Autonomous Multi-Turn Execution**: Plans, inspects, edits files, executes shell commands, analyzes stderr/stdout, and iterates until the objective is accomplished.
- **Hardware-Accelerated 120 FPS Thinking**: Smooth, ProMotion-optimized floating overlay panel with interactive budget slider (256–6,144 tokens) and quick presets.
- **In-App Rendered Markdown Viewer**: Native macOS sheet modal ([`MarkdownDocumentViewerSheet`](docs/features.md#6-native-in-app-rendered-markdown-document-viewer)) for viewing instructions and playbooks with tabbed navigation and code syntax highlighting.
- **Domain Playbooks Engine**: Pre-loaded with 4 authoritative guides in `~/.jarvis/playbooks/` (coding, filesystem, terminal, codebase auditing) with on-demand agent loading and custom user extensibility.
- **Granular 3-Tier Security Policy**: Choose between **Strict (Always Ask)**, **Auto-Approve Read Only** (default), or **Full Autonomous** with persistent command whitelists and shell safety guards.
- **Context Compression Engine**: Automatic non-destructive compression boundaries prevent context overflow while preserving full visual message history.

---

## Quick Start

### 1. Prerequisites
- macOS 14.0 (Sonoma) or later on Apple Silicon (M1/M2/M3/M4).
- [LM Studio](https://lmstudio.ai/) running with local server enabled (`lms bootstrap`).

### 2. Build & Run
```bash
# Clone the repository
git clone https://github.com/maksimsterkis/Jarvis.git
cd Jarvis

# Build via Xcode command line
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Release build
```

Or open `Jarvis.xcodeproj` directly in Xcode and press `Cmd + R`.

---

## Quick Command Reference

Trigger commands anywhere in the chat prompt using `/`:

| Command | Syntax | Description |
| :--- | :--- | :--- |
| `/compress` | `/compress [low\|med\|high]` | Condenses conversation history into a memory snapshot anchor. |
| `/think` | `/think [low\|med\|high\|max\|off]` | Sets reasoning token budget, custom token number, or toggles thinking off. |
| `/model` | `/model [name]` | Switches model, boots LM Studio if offline, and loads weights into memory. |
| `/dir` | `/dir [path]` | Sets active working directory, or opens native folder picker if omitted. |
| `/playbooks` | `/playbooks [name]` | Opens in-app rendered markdown viewer with tabbed browsing across playbooks. |
| `/instructions`| `/instructions` | Opens `~/.jarvis/instructions.md` in the in-app rendered markdown viewer. |
| `/export` | `/export` | Formats and copies complete conversation as Markdown to clipboard. |

*Press `Return` (`⏎`) to send, `Option + Return` (`⌥⏎`) to insert a newline, `Tab` to autocomplete slash commands, and `Esc` to dismiss.* See the [Slash Commands & Shortcuts Guide](docs/commands.md) for full details.

---

## License

Jarvis is open-source software licensed under the [MIT License](LICENSE).
