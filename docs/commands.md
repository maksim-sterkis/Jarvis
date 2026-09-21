# Slash Commands & Keyboard Shortcuts

Jarvis features an interactive command palette and a dynamic parameter autocompletion engine built into the prompt input box.

---

## Interactive Command Palette

Typing `/` in the prompt input triggers the command overlay. 

- **Category Filtering**: Filter by category chips (**Context**, **Model**, **Tools**, **Session**).
- **Fuzzy Search**: Matching on command names, syntax, and descriptions.
- **Dynamic Argument Autocomplete**: As soon as a command and space are typed (e.g. `/playbooks `), the overlay shifts into argument condensation mode, presenting live contextual options.
- **Keyboard Navigation**:
  - `Up` / `Down`: Move selection highlight.
  - `Tab` or `Enter`: Insert the selected command or argument.
  - `Esc`: Dismiss the overlay.

---

## Slash Commands Reference

| Command | Syntax | Category | Description |
| :--- | :--- | :--- | :--- |
| [`/compress`](#compress) | `/compress [low\|med\|high]` | `Context` | Condenses conversation history into a memory snapshot anchor while preserving visual UI messages. |
| [`/think`](#think) | `/think [low\|med\|high\|max\|off]` | `Model` | Sets the reasoning token budget, custom token number (e.g. `2048`), or toggles reasoning off. |
| [`/model`](#model) | `/model [name]` | `Model` | Switches active model, boots LM Studio if offline, and loads weights into unified memory. |
| [`/dir`](#dir) | `/dir [path]` | `Tools` | Sets the active project working directory, or opens the native macOS folder picker if omitted. |
| [`/playbooks`](#playbooks) | `/playbooks [name]` | `Tools` | Opens the native in-app rendered markdown viewer with tabbed browsing across all playbooks. |
| [`/instructions`](#instructions) | `/instructions` | `Tools` | Opens `~/.jarvis/instructions.md` in the native in-app rendered markdown viewer with editor fallback. |
| [`/export`](#export) | `/export` | `Session` | Formats and copies the complete conversation history as clean Markdown to the clipboard. |

---

## Command Details

### `/compress`
*(Alias: `/compression`)*

Condenses prior conversation turns into a compact `<memory_snapshot>` anchor block to free up context window space.

- **Options**:
  - `low`: Light summarization, preserving high conversational nuance.
  - `med` *(default)*: Balanced snapshot, ideal for normal multi-turn engineering workflows.
  - `high`: Maximum compression, retaining only key facts, architectural decisions, and file targets.
- **Autocomplete**: Typing `/compress ` dynamically displays the 3 level badges for instant `Tab` completion.

### `/think`
Controls model reasoning and chain-of-thought token generation.

- **Presets**:
  - `low`: ~1,024 reasoning tokens.
  - `med`: ~2,048 reasoning tokens.
  - `high`: ~4,096 reasoning tokens.
  - `max`: ~8,192 deep reasoning tokens.
  - `off`: Disables reasoning tokens for direct, fast response streaming.
- **Custom Budgets**: Provide numeric values directly (e.g. `/think 3000`).
- **Toggle**: Running `/think` with no arguments toggles reasoning on/off.

### `/model`
Manages local LLMs hosted in LM Studio.

- **Without arguments**: Lists all models available on disk and notes which model is currently loaded in RAM.
- **With arguments**: Boots the LM Studio background server (if offline), offloads previous weights, and loads the target model.
- **Autocomplete**: Typing `/model ` lists all detected local models on disk for immediate `Tab` completion.

### `/dir`
Sets the root working directory for all subsequent tool calls and shell operations.

- **Without arguments**: Opens the native macOS folder selection sheet (`NSOpenPanel`).
- **With arguments**: Accepts absolute paths or tilde expansion (e.g. `/dir ~/Projects/BackendApp`).
- **Autocomplete**: Typing `/dir ` suggests `~` and `Browse...`.

### `/playbooks`
Reveals and renders domain knowledge playbooks in the in-app document reader.

- **Without arguments**: Opens the in-app markdown viewer displaying all playbooks with interactive navigation tabs.
- **With argument**: Directly selects and opens a specific playbook (e.g. `/playbooks coding_and_testing`).
- **Autocomplete**: Typing `/playbooks ` dynamically queries `PlaybookService` and displays all installed playbooks.

### `/instructions`
Inspects user-defined persistent instructions (`~/.jarvis/instructions.md`) directly in the in-app rendered markdown viewer.

- Includes a one-click **"Open in Editor"** button to modify instructions in VS Code or your preferred editor.

### `/export`
Exports the entire chat thread formatted in GitHub-flavored Markdown directly to the macOS clipboard.

---

## Global Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Cmd + N` | Start a new blank chat session |
| `Cmd + ,` | Open Jarvis Settings panel |
| `Cmd + K` | Focus prompt input box |
| `Tab` | Autocomplete selected suggestion in slash palette |
| `Esc` | Dismiss active slash overlay |
| `Enter` | Submit prompt or execute selected slash command |
| `Shift + Enter` | Insert newline in prompt input |

---

## Related Documentation

- [Core Features & Capabilities](features.md)
- [Tool Ecosystem Reference](tools.md)
- [Getting Started & Configuration](getting-started.md)
