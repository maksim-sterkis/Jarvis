# Playbook: macOS Filesystem & Path Resolution
> Rules for macOS paths, relative vs. absolute resolution, tilde expansion, and folder creation.

## 1. Path Resolution on macOS
- `~` represents the current user's home folder (`/Users/<username>`).
- Any path starting with `~` or `/` is ABSOLUTE.
- Any path without a leading `~` or `/` is RELATIVE to the Active Working Directory.
- NEVER concatenate home directories (e.g. `/Users/user/Users/user`).

## 2. Inspecting Files & Directories
- Always prefer native tools `read_file`, `read_multiple_files`, and `list_directory`.
- When inspecting 2 or more files, ALWAYS use `read_multiple_files` to fetch them in a single batch turn.

## 3. Writing Files & Creating Directories
- `create_directory`: Creates the folder and all necessary parent folders automatically.
- `write_file`: Writes complete contents atomically, creating parent folders if needed.
