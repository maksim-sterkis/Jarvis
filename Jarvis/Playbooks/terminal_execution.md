# Playbook: Safe Terminal Command Execution
> Guidelines for running shell commands safely in /bin/zsh on macOS.

## 1. Environment & Working Directory
- Commands run in a `/bin/zsh` login shell on Apple Silicon.
- Always set `working_directory` when running commands in subprojects or created folders.

## 2. Non-Interactive Command Rule
- Never run interactive commands that wait for keyboard input (`top`, `less`, `nano`, `vi`).
- Use non-interactive flags:
  - `head -n 20` instead of `less`
  - `ps aux` instead of `top`
  - `git commit -m "..."` instead of `git commit`
  - `python3 -m unittest` instead of interactive runners

## 3. Chaining & Efficiency
- Combine fast related read commands using `&&` (e.g. `git status && git log -n 5 --oneline`).
- Check exit codes: non-zero exit codes indicate failure. Inspect stderr for error messages.
