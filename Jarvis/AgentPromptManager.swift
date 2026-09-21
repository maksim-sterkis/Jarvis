//
//  AgentPromptManager.swift
//  Jarvis
//

import Foundation
import AppKit

final class AgentPromptManager {
    static let shared = AgentPromptManager()

    private init() {}

    /// Returns the system prompt incorporating `AgentInstructions.md` and dynamic runtime environment context.
    func buildSystemPrompt(workingDirectory: String, thinkingBudget: Int? = nil, workingMemory: String? = nil) -> String {
        let instructions = loadInstructionsContent()

        let username = NSUserName()
        let homeDir = NSHomeDirectory()
        let nowString = ISO8601DateFormatter().string(from: Date())

        let activeDir = workingDirectory.isEmpty ? homeDir : workingDirectory
        let playbooksSection = PlaybookService.shared.playbooksSummaryMarkdown()

        let context = """

---
## Runtime Environment & Whereabouts
- Current User: \(username)
- Home Directory (~): \(homeDir)
- Active Working Directory: \(activeDir)
- System Time: \(nowString)
- Operating System: macOS (Apple Silicon)

### Critical Path & Directory Rules:
1. **Absolute Paths**: Any path starting with `~` or `/` is absolute (e.g. `~/benchmark_tool` resolves directly to `\(homeDir)/benchmark_tool`). NEVER duplicate or prepend the home directory.
2. **Relative Paths**: Any path without a leading `/` or `~` (e.g. `main.py`, `src/utils.py`) resolves strictly relative to your Active Working Directory (`\(activeDir)`).
3. **Running Scripts in Subfolders**: When you create files in a subfolder (e.g. `~/benchmark_tool` or `benchmark_tool`), running commands like `python3 test_perf.py` requires you to either:
   - Pass `working_directory: "~/benchmark_tool"` in `run_terminal_command`, OR
   - Specify the path in the command (e.g. `python3 ~/benchmark_tool/test_perf.py`).

---
## Specialized Playbooks (Read On-Demand)
\(playbooksSection)
"""

        var protocolText = """

---
## Autonomous Execution & Anti-Hallucination Protocol
1. **Tool Preference & Batch Reading Protocol**:
   - **Batch Efficiency**: When you need to inspect multiple files (e.g. 2 or more files), ALWAYS use `read_multiple_files(paths: [...])` to fetch all files in a **single turn**. This is drastically faster and prevents multi-turn drift.
   - Prefer native tools (`read_multiple_files`, `read_file`, `list_directory`) first. Native tools run automatically without manual terminal approval prompts.
   - Use `run_terminal_command` (`find`, `ls`, `grep`) ONLY when command-line search or piping is strictly needed.
2. **Whole-Response Reasoning & Working Memory Protocol**:
   - For multi-step tasks, you MUST maintain an active task checklist inside `<working_memory>...</working_memory>` at the start of each turn.
   - Example:
     <working_memory>
     Task: Inspect and summarize 5 files
     Locked Target Files: [File1, File2, File3, File4, File5]
     Status:
     - [x] List directory (Completed)
     - [x] Read all 5 files via read_multiple_files
     - [ ] Final comprehensive summary
     </working_memory>
   - **Plan Lock-In**: Target files selected in turn 1 are PERMANENT and LOCKED. Never swap, replace, or add new files across turns.
3. **Completion & Stop Condition**:
   - Once all selected target files have been inspected, STOP invoking tools immediately.
   - Do NOT search for more files or re-read files. Deliver your final comprehensive summary to the user.
4. **Never Hallucinate or Invent Unread Files**:
   - Never guess or fabricate contents of files you have not inspected through tools.
   - Report strictly what is found in actual tool outputs.
"""

        if let memory = workingMemory, !memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            protocolText += """

---
## Persistent Working Memory for Current Request
Jarvis has preserved your previous task checklist across turns:
\(memory)

(Review the checklist and tool outputs in context above. As soon as all target files have been inspected, do NOT invoke more tools. Deliver your final comprehensive summary to the user immediately.)
"""
        }

        let thinkingNote: String
        if let budget = thinkingBudget {
            thinkingNote = "\n- Reasoning Budget: ~\(budget) tokens. Provide thoughtful reasoning before executing tools."
        } else {
            thinkingNote = "\n- Reasoning: Disabled. You must answer directly and immediately without thinking tags (<think>), thought channels, or internal deliberation."
        }

        return instructions + context + protocolText + thinkingNote
    }

    /// Loads the markdown content from the bundle or returns a built-in fallback.
    func loadInstructionsContent() -> String {
        // Check user custom file first (~/.jarvis/instructions.md)
        let customURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".jarvis/instructions.md")
        if FileManager.default.fileExists(atPath: customURL.path),
           let customText = try? String(contentsOf: customURL, encoding: .utf8), !customText.isEmpty {
            return customText
        }

        // Check app bundle
        if let bundleURL = Bundle.main.url(forResource: "AgentInstructions", withExtension: "md"),
           let text = try? String(contentsOf: bundleURL, encoding: .utf8), !text.isEmpty {
            return text
        }

        // Direct path in project directory fallback for development
        let devURL = URL(fileURLWithPath: "/Users/maksimsterkis/Jarvis/Jarvis/AgentInstructions.md")
        if let devText = try? String(contentsOf: devURL, encoding: .utf8), !devText.isEmpty {
            return devText
        }

        return "You are Jarvis, a helpful and secure desktop assistant on macOS."
    }

    /// Opens the instruction markdown file in the user's default text editor.
    func openInstructionsFile() {
        let customDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".jarvis")
        let customFile = customDir.appendingPathComponent("instructions.md")

        if !FileManager.default.fileExists(atPath: customFile.path) {
            try? FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
            let defaultContent = loadInstructionsContent()
            try? defaultContent.write(to: customFile, atomically: true, encoding: .utf8)
        }

        NSWorkspace.shared.open(customFile)
    }
}
