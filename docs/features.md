# Core Features & Capabilities

Jarvis pairs native macOS speed with local LLM autonomy. Below is a comprehensive breakdown of its primary capabilities.

---

## 1. Local & Private Inference Engine

- **100% Air-Gapped Operation**: Interconnects with local LLMs via LM Studio at `http://127.0.0.1:1234`. No API keys, no telemetry, no cloud relays.
- **Apple Silicon Unified Memory**: Takes full advantage of M-series unified memory architecture (M1–M4 Pro/Max/Ultra) for high-speed local token throughput.
- **Zero-CLI Fast Startup (< 1ms)**: Scans `~/.lmstudio/models` directly via pure Swift `FileManager` without waking background CLI daemons or spawning slow shell commands during app launch.
- **Dynamic Model Switcher & Progress HUD**:
  - One-click **"Start Server & Load"** directly from the header toolbar.
  - Real-time animated progress bar with live percentage extraction while weights are offloaded into unified memory.
  - Automatically unloads idle background models to protect RAM headroom.
- **Smart Ownership Lifecycle**:
  - Distinguishes whether Jarvis launched the server or if it was already running externally (`didJarvisLaunchServer`).
  - Automatically shuts down the server upon quitting Jarvis **only** if Jarvis was the process that initiated it.
- **Instant Termination (< 0.05s)**:
  - Custom SIGKILL cleanup halts helper processes immediately, avoiding macOS watchdog hangs or phantom background activity.

---

## 2. Autonomous Multi-Turn Agentic Workflows

- **Autonomous Feedback Loop**: Jarvis plans, calls tools, evaluates stderr/stdout observations, adjusts its approach when errors arise, and loops autonomously until the task is complete.
- **Execution Safeguard**: Enforces a 15-step execution limit per prompt to prevent infinite loops while giving sufficient headroom for large multi-file tasks.
- **Instant Generation Stop**: Safely cancels streaming inference and aborts active shell subprocesses at any millisecond without losing generated content.

---

## 3. Transparent Reasoning & 120 FPS Popover

- **Separated Thinking Stream**: Intercepts reasoning tokens and renders them inside sleek, collapsible thought pills.
- **Reasoning Telemetry**: Displays exact token counts and elapsed seconds for reasoning phases.
- **One-Click Thought Exporter**: Copies the entire reasoning trace, checklist, and intermediate tool outputs as formatted Markdown to the clipboard.
- **Hardware-Accelerated 120 FPS Thinking Dropdown**:
  - Smooth ProMotion-optimized floating overlay panel anchored to the toolbar via `ThinkingButtonFramePreferenceKey`.
  - Zero layout jumping or content displacement when toggling.
  - Interactive continuous token budget slider (256 to 6,144 tokens) with real-time feedback.
  - Quick presets: **Low (1,024)**, **Med (2,048)**, **High (4,096)**, **Max (8,192)**, and **Off**.

---

## 4. Persistent Working Memory & Anti-Hallucination

- **Plan Lock-In Protocol**: When planning multi-file changes, Jarvis commits target files into an explicit `<working_memory>` anchor.
- **No Target Churning**: Preserves this locked list across subsequent turns, preventing the model from forgetting earlier steps or inventing nonexistent files.
- **Enforced Reading**: Agent instructions strictly forbid summarizing or analyzing files that have not been read via tool calls.

---

## 5. Context Management & Automatic Compression

- **Live Token Gauge**: Real-time meters in the header and sidebar track active context tokens against the model's physical window (e.g. 131,072 tokens for Gemma 4).
- **Compression Boundaries**: When conversations grow large, Jarvis establishes non-destructive compression boundaries (`CompressionBoundaryView.swift`). Earlier turns are compressed into a compact memory snapshot anchor while preserving the full visual history in the UI.
- **Manual Triggering**: Run `/compress [low|med|high]` anytime to snapshot history on demand.

---

## 6. Native In-App Rendered Markdown Document Viewer

- **Modal Sheet Presentation**: View instructions and playbooks directly within Jarvis via `MarkdownDocumentViewerSheet.swift` without switching to an external editor.
- **Rich Typography & Syntax**: Powered by `MarkdownMessageView.swift`, rendering H1–H6 headers, syntax-styled code blocks with copy buttons, tables, bold/italic formatting, and path pills.
- **Live Reading Metrics**: Displays live word count, token estimation (`~words × 1.33`), and file path badges.
- **Interactive Playbook Tab Bar**: Effortlessly switch between all discovered playbooks in the collection with a single click.
- **External Editor Fallback**: Dedicated "Open in Editor" button launches the raw `.md` file in your default editor (VS Code, Cursor, etc.).

---

## 7. Specialized Playbooks & Domain Knowledge Engine

- **Autonomous Discovery & Seeding**: Powered by `PlaybookService.swift`, which provisions 4 authoritative domain guides into `~/.jarvis/playbooks/`:
  - `coding_and_testing.md`: Code scaffolding, test runner configuration, working directory rules, and `Errno 2` diagnostics.
  - `filesystem_and_paths.md`: Authoritative rules on macOS path resolution, `~` expansion, and atomic file creation.
  - `terminal_execution.md`: Non-interactive command best practices, working directory switching, and exit-code validation.
  - `codebase_auditing.md`: Multi-file batch inspection and architectural synthesis.
- **On-Demand Loading**: The model can pull any playbook via `read_file(path: "~/.jarvis/playbooks/<name>.md")` whenever it needs deep domain guidance.
- **User Extensible**: Drop your own `.md` playbooks into `~/.jarvis/playbooks/` anytime to teach Jarvis custom frameworks, APIs, or team guidelines.

---

## 8. Active Workspace & Path Management

- **Interactive Directory Picker**: Set the active working directory via the header button or `/dir` command.
- **Relative Path Resolution**: All file tools and shell commands execute relative to the selected project folder.
- **Context Injection**: Dynamic system prompt automatically injects the current working directory path so the model never has to guess where project files reside.

---

## 9. Native macOS Integration & Theming

- **Appearance Modes**: Built-in Dark, Light, and System themes that immediately synchronize with macOS system appearance.
- **Optional Menu Bar Extra**: Keep Jarvis tucked in the top-right macOS menu bar for rapid access or quick quitting.
- **100% Native**: Zero Electron, zero webviews, zero bloated runtimes. Built purely in Swift, SwiftUI, and AppKit for instant launch times and minimal battery consumption.

---

## Related Documentation

- [Slash Commands & Shortcuts](commands.md)
- [Tool Ecosystem Reference](tools.md)
- [Security & Permission Gateway](security.md)
- [Architecture & Execution Engine](architecture.md)
