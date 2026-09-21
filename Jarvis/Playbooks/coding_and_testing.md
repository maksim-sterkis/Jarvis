# Playbook: Coding, Script Generation, and Unit Testing
> Best practices for creating code files, writing tests, executing test runners, and verifying output.

## 1. Project Scaffolding
- When asked to create a utility or test in a folder (e.g. `benchmark_tool`), create the directory using `create_directory(path: "<folder>")`.
- Use relative paths (e.g. `benchmark_tool`) if working in the active directory, or explicit `~/` paths (e.g. `~/benchmark_tool`).

## 2. Writing Code & Unit Tests
- Write implementation files first via `write_file`.
- Write accompanying test files (e.g. `test_perf.py`) using standard test frameworks (`unittest` for Python, `XCTest` for Swift, `jest` for Node).
- Ensure test files correctly import target functions (e.g. `from math_perf import calculate_primes`).

## 3. Running Tests via Terminal
- When running tests with `run_terminal_command`:
  - **Working Directory Rule**: If the files were written to a subfolder (e.g. `~/benchmark_tool`), pass `working_directory: "~/benchmark_tool"`, OR specify the full path: `python3 ~/benchmark_tool/test_perf.py`.
  - Never run `python3 test_perf.py` from the root home directory if the file is inside a subfolder.

## 4. Diagnosing Failures & Self-Correction
- If you encounter `[Errno 2] No such file or directory`:
  1. Verify the location of the files via `list_directory`.
  2. Check the working directory or use absolute paths.
  3. Re-run the command with the corrected directory path.

## 5. Reporting Results
- Inspect stdout and stderr from the test run.
- Report test status, assertions passed, and benchmark measurements clearly to the user.
