//
//  PlaybookService.swift
//  Jarvis
//
//  Created by Antigravity on 2026-09-18.
//

import Foundation

struct PlaybookInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let path: String
    let summary: String
}

final class PlaybookService {
    static let shared = PlaybookService()

    private let playbooksDirectory: URL

    private init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        self.playbooksDirectory = home.appendingPathComponent(".jarvis/playbooks")
        ensurePlaybooksExist()
    }

    /// Ensures the ~/.jarvis/playbooks folder exists and populates standard playbooks if missing.
    func ensurePlaybooksExist() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: playbooksDirectory.path) {
            try? fm.createDirectory(at: playbooksDirectory, withIntermediateDirectories: true)
        }

        let defaultPlaybooks: [(filename: String, content: String)] = [
            ("coding_and_testing.md", codingAndTestingContent),
            ("filesystem_and_paths.md", filesystemAndPathsContent),
            ("terminal_execution.md", terminalExecutionContent),
            ("codebase_auditing.md", codebaseAuditingContent)
        ]

        for item in defaultPlaybooks {
            let fileURL = playbooksDirectory.appendingPathComponent(item.filename)
            if !fm.fileExists(atPath: fileURL.path) {
                try? item.content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Discovers all available playbooks in ~/.jarvis/playbooks.
    func listPlaybooks() -> [PlaybookInfo] {
        ensurePlaybooksExist()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: playbooksDirectory.path) else {
            return []
        }

        var results: [PlaybookInfo] = []
        for file in files.sorted() where file.hasSuffix(".md") {
            let fullPath = playbooksDirectory.appendingPathComponent(file).path
            let summary = extractSummary(from: fullPath)
            let title = file.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: "_", with: " ").capitalized
            results.append(PlaybookInfo(
                id: file,
                title: title,
                path: "~/.jarvis/playbooks/\(file)",
                summary: summary
            ))
        }
        return results
    }

    /// Loads the markdown content of a specific playbook.
    func loadPlaybookContent(info: PlaybookInfo) -> String? {
        let expanded = (info.path as NSString).expandingTildeInPath
        return try? String(contentsOfFile: expanded, encoding: .utf8)
    }

    /// Finds a playbook matching a given query string (e.g. "coding_and_testing", "coding", "coding_and_testing.md")
    func findPlaybook(matching query: String) -> (info: PlaybookInfo, content: String)? {
        let playbooks = listPlaybooks()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else { return nil }

        // 1. Try exact filename match
        if let match = playbooks.first(where: { $0.id.lowercased() == cleanQuery || $0.id.lowercased() == "\(cleanQuery).md" }) {
            if let content = loadPlaybookContent(info: match) {
                return (match, content)
            }
        }

        // 2. Try prefix or contains match
        if let match = playbooks.first(where: {
            $0.id.lowercased().contains(cleanQuery) ||
            $0.title.lowercased().contains(cleanQuery)
        }) {
            if let content = loadPlaybookContent(info: match) {
                return (match, content)
            }
        }

        return nil
    }

    /// Generates markdown documentation of available playbooks for the agent system prompt.
    func playbooksSummaryMarkdown() -> String {
        let playbooks = listPlaybooks()
        guard !playbooks.isEmpty else { return "No specialized playbooks found." }

        var lines = [
            "Jarvis has access to specialized playbooks in `~/.jarvis/playbooks/`. When undertaking these specific workflows, invoke `read_file(path: \"<playbook_path>\")` at the start of your turn to load authoritative guidelines:",
            ""
        ]

        for pb in playbooks {
            lines.append("- **\(pb.title)** (`\(pb.path)`): \(pb.summary)")
        }

        return lines.joined(separator: "\n")
    }

    private func extractSummary(from path: String) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "Domain instructions and best practices."
        }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                return trimmed
            }
        }
        return "Authoritative guidelines and workflow protocols."
    }

    // MARK: - Default Playbook Contents

    private var codingAndTestingContent: String {
        """
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
        """
    }

    private var filesystemAndPathsContent: String {
        """
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
        """
    }

    private var terminalExecutionContent: String {
        """
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
        """
    }

    private var codebaseAuditingContent: String {
        """
        # Playbook: Codebase Auditing & Multi-File Architecture Analysis
        > Protocols for reviewing multi-file repositories, maintaining working memory, and cross-file synthesis.

        ## 1. Target Locking & Working Memory
        - In Turn 1, identify the candidate files required to answer the question.
        - Lock these files inside `<working_memory>`.
        - Once locked, do not drop or change target files across turns.

        ## 2. Batch Inspection
        - Use `read_multiple_files` to retrieve all candidate files in a single turn.
        - Never fabricate or guess unread code.

        ## 3. Synthesis & Formatting
        - Organize explanations logically by file or architectural layer.
        - Use Markdown tables (`| Header | Header |`) to compare features or settings.
        - Use `####` (H4) or `###` (H3) for subheadings.
        """
    }
}
