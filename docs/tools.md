# Tool Ecosystem Reference

Jarvis equips local Large Language Models with 6 native system tools formatted as standard OpenAI function-calling schemas. All tools are dispatched locally by `ToolRegistry.swift` and executed by native Swift services without external dependencies.

---

## Tool Overview Table

| Tool Name | Parameters | Description | Default Security (Read-Only Mode) |
| :--- | :--- | :--- | :--- |
| [`read_multiple_files`](#1-read_multiple_files) | `paths`: `[string]`, `max_bytes_per_file`: `int?` | Reads multiple files concurrently in a single turn. **Preferred tool** for codebase audits. | **Auto-Approved** |
| [`read_file`](#2-read_file) | `path`: `string`, `max_bytes`: `int?` | Reads the text content of a single local file. Supports `~` and relative paths. | **Auto-Approved** |
| [`list_directory`](#3-list_directory) | `path`: `string` | Lists directory contents with item names, types (file vs directory), and file sizes. | **Auto-Approved** |
| [`write_file`](#4-write_file) | `path`: `string`, `content`: `string`, `overwrite`: `bool?` | Creates or updates a file with exact text content. Automatically creates parent directories. | Requires Approval |
| [`create_directory`](#5-create_directory) | `path`: `string` | Creates a new directory and any intermediate parent folders on disk. | Requires Approval |
| [`run_terminal_command`](#6-run_terminal_command) | `command`: `string`, `working_directory`: `string?` | Executes a shell command via `/bin/zsh`. Captures stdout, stderr, exit code, and runtime duration. | Requires Approval (or Whitelist) |

---

## Tool Specifications

### 1. `read_multiple_files`
Reads up to 50 files concurrently in a single roundtrip to minimize turn latency during audits.

- **Parameters**:
  - `paths` (*array of strings, required*): The list of absolute or relative file paths to read.
  - `max_bytes_per_file` (*integer, optional*): Maximum bytes to read per file (default: 12,288 bytes).
- **Behavior**:
  - Automatically resolves relative paths against the active working directory.
  - Expands tilde (`~`) prefixes.
  - If one file does not exist, returns specific file error without halting other file reads.

### 2. `read_file`
Reads the exact text content of a single file from disk.

- **Parameters**:
  - `path` (*string, required*): The file path to inspect.
  - `max_bytes` (*integer, optional*): Maximum bytes to read before truncating with an offset warning (default: 102,400 bytes).
- **Behavior**:
  - Returns raw UTF-8 string content.
  - Flags binary or non-UTF8 files cleanly.

### 3. `list_directory`
Inspects directory structure to map project trees and discover files.

- **Parameters**:
  - `path` (*string, required*): Path to the directory.
- **Behavior**:
  - Returns an alphabetically sorted list of entries formatted as `[FILE] name (bytes)` or `[DIR] name/`.
  - Excludes standard noise directories (like `.git`) from verbose output unless explicitly requested.

### 4. `write_file`
Atomic file writer for creating or modifying project files.

- **Parameters**:
  - `path` (*string, required*): Target destination path.
  - `content` (*string, required*): Exact text content to write.
  - `overwrite` (*boolean, optional*): Defaults to `true`.
- **Behavior**:
  - Automatically creates intermediate parent folders (`FileManager.createDirectory(at:withIntermediateDirectories: true)`).
  - Uses atomic disk writing to prevent corrupted or partial file writes.

### 5. `create_directory`
Creates folders and package directory structures.

- **Parameters**:
  - `path` (*string, required*): The path of the folder to create.
- **Behavior**:
  - Safely succeeds if the directory already exists (`withIntermediateDirectories: true`).

### 6. `run_terminal_command`
Executes arbitrary non-interactive commands in a native `/bin/zsh` subshell.

- **Parameters**:
  - `command` (*string, required*): Shell command string to execute.
  - `working_directory` (*string, optional*): Custom execution directory (defaults to active working directory).
- **Behavior**:
  - Runs in non-interactive mode with standard environment variables.
  - Captures combined `stdout`, `stderr`, numeric exit code, and execution time in milliseconds.
  - **30-Second Timeout Guard**: Background watchdog forcibly terminates commands that exceed 30 seconds.
  - **Safety Heuristics**: Checked against the security policy and user-defined binary whitelist.

---

## Related Documentation

- [Security & Permission Gateway](security.md)
- [Architecture & Execution Engine](architecture.md)
- [Slash Commands & Shortcuts](commands.md)
