//
//  AppSettings.swift
//  Jarvis
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func applyAppearance() {
        DispatchQueue.main.async {
            switch self {
            case .system:
                NSApp?.appearance = nil
            case .light:
                NSApp?.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp?.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}

enum AgentSecurityMode: String, CaseIterable, Identifiable {
    case alwaysAsk = "Always Ask (Strict)"
    case autoApproveReadOnly = "Auto-Approve Read Only"
    case fullAutonomous = "Full Autonomous"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .alwaysAsk:
            return "Jarvis requires your manual confirmation for all terminal commands and file operations."
        case .autoApproveReadOnly:
            return "Read-only operations (reading files, listing folders) run automatically. Shell commands and file modifications require confirmation."
        case .fullAutonomous:
            return "All tools execute automatically without manual confirmation."
        }
    }

    func isToolAutoApproved(toolName: String, argumentsJSON: String = "{}") -> Bool {
        if toolName == "run_terminal_command" {
            // NEVER blanket auto-approve terminal commands unless in fullAutonomous mode
            if self == .fullAutonomous {
                return true
            }
            if let data = argumentsJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cmd = dict["command"] as? String {
                let analysis = ToolAutoApprovalManager.analyzeCommandSafety(cmd)
                return analysis.isSafe
            }
            return false
        }

        // Check specific user tool override (e.g. read_file, list_directory)
        if ToolAutoApprovalManager.isToolAutoApproved(toolName) {
            return true
        }

        switch self {
        case .alwaysAsk:
            return false
        case .autoApproveReadOnly:
            let readOnlyTools = ["read_file", "read_multiple_files", "list_directory"]
            return readOnlyTools.contains(toolName)
        case .fullAutonomous:
            return true
        }
    }
}

/// Detailed safety analysis of a shell command to prevent injection, redirection writes, or chained attacks
struct ShellCommandSafetyAnalysis {
    let isSafe: Bool
    let baseCommands: [String]
    let hasRedirection: Bool
    let hasPipesOrChaining: Bool
    let hasSubshellOrExec: Bool
    let warningReason: String?
}

struct ToolAutoApprovalManager {
    static let toolStorageKey = "autoApprovedToolNames"
    static let commandStorageKey = "autoApprovedCommandNames"

    /// Performs deep structural safety analysis of a shell command
    static func analyzeCommandSafety(_ rawCommand: String) -> ShellCommandSafetyAnalysis {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ShellCommandSafetyAnalysis(
                isSafe: false,
                baseCommands: [],
                hasRedirection: false,
                hasPipesOrChaining: false,
                hasSubshellOrExec: false,
                warningReason: "Empty command."
            )
        }

        var inSingleQuote = false
        var inDoubleQuote = false
        var hasRedirection = false
        var hasSubshell = false
        var segments: [String] = []
        var currentSegment = ""

        let chars = Array(trimmed)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if c == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                currentSegment.append(c)
                i += 1
                continue
            }

            if c == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                currentSegment.append(c)
                i += 1
                continue
            }

            if !inSingleQuote && !inDoubleQuote {
                // Check command substitution: $(...) or `...`
                if c == "`" || (c == "$" && i + 1 < chars.count && chars[i + 1] == "(") {
                    hasSubshell = true
                }

                // Check file redirection: >, >>, >|, &>, 1>, 2>
                if c == ">" {
                    hasRedirection = true
                }

                // Split segments by pipes (|) and command chaining (&&, ||, ;, &)
                if c == "|" {
                    if i + 1 < chars.count && chars[i + 1] == "|" {
                        // || operator
                        segments.append(currentSegment)
                        currentSegment = ""
                        i += 2
                        continue
                    } else {
                        // | operator
                        segments.append(currentSegment)
                        currentSegment = ""
                        i += 1
                        continue
                    }
                } else if c == "&" {
                    if i + 1 < chars.count && chars[i + 1] == "&" {
                        // && operator
                        segments.append(currentSegment)
                        currentSegment = ""
                        i += 2
                        continue
                    }
                } else if c == ";" {
                    segments.append(currentSegment)
                    currentSegment = ""
                    i += 1
                    continue
                }
            }

            currentSegment.append(c)
            i += 1
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        let hasPipesOrChaining = segments.count > 1

        // Parse each segment for base commands and dangerous flags
        var baseCommands: [String] = []
        var hasDestructiveFlag = false
        var destructiveDetail: String? = nil

        for segment in segments {
            let segTrimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segTrimmed.isEmpty else { continue }

            let tokens = segTrimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let firstToken = tokens.first else { continue }

            var cmdName = firstToken
            // Handle assignments like "FOO=bar cmd"
            if cmdName.contains("=") && tokens.count > 1 {
                cmdName = tokens[1]
            }
            let base = (cmdName as NSString).lastPathComponent
            if !base.isEmpty && !baseCommands.contains(base) {
                baseCommands.append(base)
            }

            // Command-specific dangerous checks: find -delete, find -exec, find -ok
            if base == "find" {
                if tokens.contains("-delete") {
                    hasDestructiveFlag = true
                    destructiveDetail = "Find command contains destructive '-delete' flag."
                }
                if tokens.contains("-exec") || tokens.contains("-execdir") || tokens.contains("-ok") {
                    hasDestructiveFlag = true
                    destructiveDetail = "Find command executes sub-commands via '-exec'."
                }
            }

            // Execution bridges: xargs, eval, sudo, bash, sh, zsh
            let executionBridges = ["xargs", "eval", "sudo", "su", "bash", "sh", "zsh"]
            if executionBridges.contains(base) {
                hasDestructiveFlag = true
                destructiveDetail = "Command utilizes '\(base)' execution bridge."
            }
        }

        let approvedCommands = getAutoApprovedCommands()

        if hasRedirection {
            return ShellCommandSafetyAnalysis(
                isSafe: false,
                baseCommands: baseCommands,
                hasRedirection: true,
                hasPipesOrChaining: hasPipesOrChaining,
                hasSubshellOrExec: hasSubshell || hasDestructiveFlag,
                warningReason: "Command redirects output to file (>), performing a write operation."
            )
        }

        if hasSubshell {
            return ShellCommandSafetyAnalysis(
                isSafe: false,
                baseCommands: baseCommands,
                hasRedirection: false,
                hasPipesOrChaining: hasPipesOrChaining,
                hasSubshellOrExec: true,
                warningReason: "Command contains subshell execution ($(..) or backticks)."
            )
        }

        if hasDestructiveFlag {
            return ShellCommandSafetyAnalysis(
                isSafe: false,
                baseCommands: baseCommands,
                hasRedirection: false,
                hasPipesOrChaining: hasPipesOrChaining,
                hasSubshellOrExec: true,
                warningReason: destructiveDetail ?? "Command contains execution or deletion flags."
            )
        }

        if baseCommands.isEmpty {
            return ShellCommandSafetyAnalysis(
                isSafe: false,
                baseCommands: [],
                hasRedirection: false,
                hasPipesOrChaining: hasPipesOrChaining,
                hasSubshellOrExec: false,
                warningReason: "Could not identify command binary."
            )
        }

        // Check if all extracted base commands are in approvedCommands
        let unapproved = baseCommands.filter { !approvedCommands.contains($0) }
        if unapproved.isEmpty {
            return ShellCommandSafetyAnalysis(
                isSafe: true,
                baseCommands: baseCommands,
                hasRedirection: false,
                hasPipesOrChaining: hasPipesOrChaining,
                hasSubshellOrExec: false,
                warningReason: nil
            )
        } else {
            let list = unapproved.map { "'\($0)'" }.joined(separator: ", ")
            let reason = unapproved.count == 1
                ? "Pipeline or command contains unapproved binary: \(list)."
                : "Pipeline or command contains unapproved binaries: \(list)."
            return ShellCommandSafetyAnalysis(
                isSafe: false,
                baseCommands: baseCommands,
                hasRedirection: false,
                hasPipesOrChaining: hasPipesOrChaining,
                hasSubshellOrExec: false,
                warningReason: reason
            )
        }
    }

    /// Extracts the core executable name from a shell command string (e.g. "find ~/Jarvis -type f" -> "find")
    static func extractBaseCommand(from command: String) -> String {
        let analysis = analyzeCommandSafety(command)
        return analysis.baseCommands.first ?? "command"
    }

    // MARK: - Native Tools Whitelist (read_file, list_directory, etc.)
    static func getAutoApprovedTools() -> [String] {
        return UserDefaults.standard.stringArray(forKey: toolStorageKey) ?? []
    }

    static func isToolAutoApproved(_ toolName: String) -> Bool {
        return getAutoApprovedTools().contains(toolName)
    }

    static func addAutoApprovedTool(_ toolName: String) {
        // Never allow blanket run_terminal_command in tool whitelist
        guard toolName != "run_terminal_command" else { return }
        var list = getAutoApprovedTools()
        if !list.contains(toolName) {
            list.append(toolName)
            UserDefaults.standard.set(list, forKey: toolStorageKey)
        }
    }

    static func removeAutoApprovedTool(_ toolName: String) {
        var list = getAutoApprovedTools()
        list.removeAll { $0 == toolName }
        UserDefaults.standard.set(list, forKey: toolStorageKey)
    }

    // MARK: - Specific Shell Command Whitelist (find, ls, cat, grep, etc.)
    static func getAutoApprovedCommands() -> [String] {
        return UserDefaults.standard.stringArray(forKey: commandStorageKey) ?? []
    }

    static func isCommandAutoApproved(_ baseCommand: String) -> Bool {
        let clean = extractBaseCommand(from: baseCommand)
        return getAutoApprovedCommands().contains(clean)
    }

    static func addAutoApprovedCommand(_ baseCommand: String) {
        let clean = extractBaseCommand(from: baseCommand)
        guard !clean.isEmpty && clean != "command" else { return }
        var list = getAutoApprovedCommands()
        if !list.contains(clean) {
            list.append(clean)
            UserDefaults.standard.set(list, forKey: commandStorageKey)
        }
    }

    static func removeAutoApprovedCommand(_ baseCommand: String) {
        let clean = extractBaseCommand(from: baseCommand)
        var list = getAutoApprovedCommands()
        list.removeAll { $0 == clean }
        UserDefaults.standard.set(list, forKey: commandStorageKey)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: toolStorageKey)
        UserDefaults.standard.removeObject(forKey: commandStorageKey)
    }
}
