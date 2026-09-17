//
//  ToolExecutionCardView.swift
//  Jarvis
//

import SwiftUI
import AppKit

struct ToolExecutionCardView: View {
    let toolCall: ToolCallRecord
    var isGenerating: Bool = false
    var isDocked: Bool = false
    let onApprove: () -> Void
    let onReject: () -> Void
    var onAlwaysApprove: (() -> Void)? = nil
    var onRejectWithFeedback: ((String) -> Void)? = nil
    var onUpdateArguments: ((String) -> Void)? = nil

    @AppStorage("autoCollapseToolOutput") private var autoCollapseToolOutput: Bool = true
    @State private var isOutputExpanded: Bool
    @State private var isCopied: Bool = false
    @State private var isOutputHeaderHovered: Bool = false

    // State for interactive approval editing & feedback
    @State private var isEditing: Bool = false
    @State private var editedCommand: String = ""
    @State private var editedPath: String = ""
    @State private var editedContent: String = ""
    @State private var showFeedbackInput: Bool = false
    @State private var feedbackText: String = ""

    init(
        toolCall: ToolCallRecord,
        isGenerating: Bool = false,
        isDocked: Bool = false,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void,
        onAlwaysApprove: (() -> Void)? = nil,
        onRejectWithFeedback: ((String) -> Void)? = nil,
        onUpdateArguments: ((String) -> Void)? = nil
    ) {
        self.toolCall = toolCall
        self.isGenerating = isGenerating
        self.isDocked = isDocked
        self.onApprove = onApprove
        self.onReject = onReject
        self.onAlwaysApprove = onAlwaysApprove
        self.onRejectWithFeedback = onRejectWithFeedback
        self.onUpdateArguments = onUpdateArguments

        // Output drawers are collapsed by default to prevent large files from dominating the UI
        _isOutputExpanded = State(initialValue: false)

        let args = toolCall.parsedArguments
        _editedCommand = State(initialValue: (args["command"] as? String) ?? "")
        _editedPath = State(initialValue: (args["path"] as? String) ?? "")
        _editedContent = State(initialValue: (args["content"] as? String) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: iconName(for: toolCall.name))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor(for: toolCall.name))

                Text(displayTitle(for: toolCall.name))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                statusBadge
            }

            // Command / Arguments Preview (or inline editor)
            commandPreview

            // Human-in-the-Loop Action Gate (Strict Approval Required)
            if toolCall.status == .pendingApproval {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Action Confirmation Required")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(approvalNoticeText)
                                .font(.system(size: 11))
                                .foregroundColor(terminalSafetyAnalysis?.hasRedirection == true ? .orange : .secondary)
                        }

                        Spacer()

                        // Edit Button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing.toggle()
                                if !isEditing {
                                    commitEdits()
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isEditing ? "checkmark.circle" : "pencil")
                                Text(isEditing ? "Done Editing" : "Edit")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isEditing ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                            .foregroundColor(isEditing ? .accentColor : .secondary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        // Decline Button
                        Button(action: {
                            if showFeedbackInput {
                                handleDecline()
                            } else {
                                onReject()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                Text("Decline")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        // Note / Feedback toggle button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFeedbackInput.toggle()
                            }
                        }) {
                            Image(systemName: showFeedbackInput ? "chevron.up.circle.fill" : "text.bubble")
                                .font(.system(size: 12))
                                .foregroundColor(showFeedbackInput ? .orange : .secondary)
                                .padding(5)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Decline with feedback note to AI")

                        // Approve Once Button
                        Button(action: handleApprove) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                Text("Approve Once")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        // Always Allow Button (only available for safe, non-redirecting commands)
                        if canAlwaysAllow {
                            Button(action: handleAlwaysAllow) {
                                HStack(spacing: 4) {
                                    Image(systemName: toolCall.name == "run_terminal_command" ? "terminal.fill" : "checkmark.seal.fill")
                                    Text(alwaysAllowTitle)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.18))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .help("Save to settings and auto-approve without asking in the future")
                        }
                    }

                    // Expandable Decline with Note Input
                    if showFeedbackInput {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            TextField("Why decline? (Optional feedback note for AI)", text: $feedbackText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                                .cornerRadius(6)

                            Button(action: handleDecline) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                    Text("Decline with Note")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(8)
            }

            // Running State Spinner
            if toolCall.status == .running {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Executing on macOS...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Output Drawer with full-row click hitbox & auto-collapse support
            if let output = toolCall.stdout, !output.isEmpty || (toolCall.stderr != nil && !toolCall.stderr!.isEmpty) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isOutputExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isOutputExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .frame(width: 10)

                                Text("Execution Output")
                                    .font(.system(size: 11, weight: .semibold))

                                if let exitCode = toolCall.exitCode {
                                    Text("exit \(exitCode)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(exitCode == 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                        .foregroundColor(exitCode == 0 ? .green : .red)
                                        .cornerRadius(4)
                                }

                                if let duration = toolCall.duration {
                                    Text(String(format: "%.2fs", duration))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .foregroundColor(isOutputHeaderHovered ? .primary : .secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(isOutputHeaderHovered ? Color.secondary.opacity(0.12) : Color.clear)
                            .cornerRadius(5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isOutputHeaderHovered = hovering
                        }

                        Button(action: {
                            let fullOutput = "\(toolCall.stdout ?? "")\n\(toolCall.stderr ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fullOutput, forType: .string)
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isCopied = false
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "Copied" : "Copy")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if isOutputExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            if let stdout = toolCall.stdout, !stdout.isEmpty {
                                Text(stdout)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if let stderr = toolCall.stderr, !stderr.isEmpty {
                                Text(stderr)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.red.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } else if toolCall.status == .rejected {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Execution was declined by user.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDocked ? Color(nsColor: .controlBackgroundColor).opacity(0.96) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDocked ? Color.orange.opacity(0.4) : strokeColor, lineWidth: isDocked ? 1.5 : 1)
        )
        .shadow(color: isDocked ? Color.black.opacity(0.18) : Color.clear, radius: isDocked ? 12 : 0, x: 0, y: isDocked ? 4 : 0)
        .cornerRadius(12)
        .onAppear {
            if autoCollapseToolOutput && (toolCall.status == .completed || toolCall.status == .failed) && !isGenerating && isOutputExpanded {
                isOutputExpanded = false
            }
        }
        .onChange(of: toolCall.status) { newStatus in
            // Collapse as soon as execution finishes (completed or failed)
            if autoCollapseToolOutput && (newStatus == .completed || newStatus == .failed) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isOutputExpanded = false
                }
            }
        }
        .onChange(of: isGenerating) { generating in
            // Also collapse when full generation cycle ends
            if autoCollapseToolOutput && !generating && (toolCall.status == .completed || toolCall.status == .failed) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isOutputExpanded = false
                }
            }
        }
    }

    private var strokeColor: Color {
        switch toolCall.status {
        case .pendingApproval: return Color.orange.opacity(0.4)
        case .running: return Color.accentColor.opacity(0.4)
        case .completed: return Color.green.opacity(0.3)
        case .failed: return Color.red.opacity(0.3)
        case .rejected: return Color.secondary.opacity(0.2)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            switch toolCall.status {
            case .pendingApproval:
                Image(systemName: "exclamationmark.shield")
                Text("Approval Needed")
            case .running:
                Image(systemName: "gearshape.arrow.triangle.2.circlepath")
                Text("Running")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                Text("Success")
            case .failed:
                Image(systemName: "xmark.circle.fill")
                Text("Failed")
            case .rejected:
                Image(systemName: "nosign")
                Text("Declined")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(statusBackgroundColor)
        .foregroundColor(statusForegroundColor)
        .cornerRadius(6)
    }

    private var statusBackgroundColor: Color {
        switch toolCall.status {
        case .pendingApproval: return Color.orange.opacity(0.15)
        case .running: return Color.accentColor.opacity(0.15)
        case .completed: return Color.green.opacity(0.15)
        case .failed: return Color.red.opacity(0.15)
        case .rejected: return Color.secondary.opacity(0.15)
        }
    }

    private var statusForegroundColor: Color {
        switch toolCall.status {
        case .pendingApproval: return .orange
        case .running: return .accentColor
        case .completed: return .green
        case .failed: return .red
        case .rejected: return .secondary
        }
    }

    @ViewBuilder
    private var commandPreview: some View {
        let args = toolCall.parsedArguments

        if isEditing && toolCall.status == .pendingApproval {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 11, weight: .semibold))
                    Text("Edit Command Before Running")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Reset") {
                        let original = toolCall.parsedArguments
                        editedCommand = (original["command"] as? String) ?? ""
                        editedPath = (original["path"] as? String) ?? ""
                        editedContent = (original["content"] as? String) ?? ""
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                switch toolCall.name {
                case "run_terminal_command":
                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        TextField("command", text: $editedCommand)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )

                case "write_file":
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Path:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            TextField("file path", text: $editedPath)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(6)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(6)

                        Text("Content:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        TextEditor(text: $editedContent)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 80, maxHeight: 180)
                            .padding(4)
                            .background(Color.black.opacity(0.25))
                            .cornerRadius(6)
                    }

                case "read_file", "create_directory", "list_directory":
                    HStack(spacing: 6) {
                        Text("Path:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("path", text: $editedPath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )

                default:
                    Text(toolCall.argumentsJSON)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
        } else {
            switch toolCall.name {
            case "run_terminal_command":
                let cmd = (args["command"] as? String) ?? ""
                terminalCommandBox("$ \(cmd)")

            case "list_directory":
                let path = (args["path"] as? String) ?? "."
                terminalCommandBox("$ ls -la \(path)")

            case "read_file":
                let path = (args["path"] as? String) ?? ""
                terminalCommandBox("$ cat \(path)")

            case "create_directory":
                let path = (args["path"] as? String) ?? ""
                terminalCommandBox("$ mkdir -p \(path)")

            case "write_file":
                VStack(alignment: .leading, spacing: 4) {
                    let path = (args["path"] as? String) ?? "file"
                    terminalCommandBox("$ cat > \(path)")

                    if let content = args["content"] as? String {
                        Text(content)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(5)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                }

            default:
                Text(toolCall.argumentsJSON)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func commitEdits() {
        var args = toolCall.parsedArguments
        switch toolCall.name {
        case "run_terminal_command":
            args["command"] = editedCommand
        case "write_file":
            args["path"] = editedPath
            args["content"] = editedContent
        case "read_file", "create_directory", "list_directory":
            args["path"] = editedPath
        default:
            break
        }
        if let data = try? JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed]),
           let json = String(data: data, encoding: .utf8) {
            onUpdateArguments?(json)
        }
    }

    private func handleApprove() {
        if isEditing {
            commitEdits()
            isEditing = false
        }
        onApprove()
    }

    private var terminalSafetyAnalysis: ShellCommandSafetyAnalysis? {
        guard toolCall.name == "run_terminal_command" else { return nil }
        let args = toolCall.parsedArguments
        let cmd = (args["command"] as? String) ?? ""
        return ToolAutoApprovalManager.analyzeCommandSafety(cmd)
    }

    private var approvalNoticeText: String {
        if let analysis = terminalSafetyAnalysis, let reason = analysis.warningReason {
            return reason
        }
        return "Jarvis will not execute this without your explicit permission."
    }

    private var canAlwaysAllow: Bool {
        if toolCall.name == "run_terminal_command" {
            guard let analysis = terminalSafetyAnalysis else { return false }
            // Commands that redirect to a file (writes) or execute subshells cannot be permanently auto-approved
            if analysis.hasRedirection || analysis.hasSubshellOrExec {
                return false
            }
            return !analysis.baseCommands.isEmpty
        }
        return true
    }

    private var alwaysAllowTitle: String {
        if toolCall.name == "run_terminal_command" {
            guard let analysis = terminalSafetyAnalysis else { return "Always Allow" }
            if analysis.baseCommands.count == 1 {
                return "Always Allow '\(analysis.baseCommands[0])'"
            } else if analysis.baseCommands.count > 1 {
                let list = analysis.baseCommands.map { "'\($0)'" }.joined(separator: ", ")
                return "Always Allow (\(list))"
            }
            return "Always Allow"
        } else {
            return "Always Allow '\(toolCall.name)'"
        }
    }

    private func handleAlwaysAllow() {
        if isEditing {
            commitEdits()
            isEditing = false
        }
        if toolCall.name == "run_terminal_command" {
            if let analysis = terminalSafetyAnalysis {
                for base in analysis.baseCommands {
                    ToolAutoApprovalManager.addAutoApprovedCommand(base)
                }
            }
        } else {
            ToolAutoApprovalManager.addAutoApprovedTool(toolCall.name)
        }
        onAlwaysApprove?()
    }

    private func handleDecline() {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRejectWithFeedback?(trimmed)
        } else {
            onReject()
        }
        showFeedbackInput = false
    }

    private func terminalCommandBox(_ commandText: String) -> some View {
        HStack {
            Text(commandText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(4)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(8)
        .background(Color.black.opacity(0.25))
        .cornerRadius(6)
    }

    private func iconName(for tool: String) -> String {
        switch tool {
        case "run_terminal_command": return "terminal.fill"
        case "write_file": return "square.and.pencil"
        case "read_file": return "doc.text.magnifyingglass"
        case "create_directory": return "folder.badge.plus"
        case "list_directory": return "list.bullet.rectangle.portrait"
        default: return "wrench.and.screwdriver"
        }
    }

    private func iconColor(for tool: String) -> Color {
        switch tool {
        case "run_terminal_command": return .green
        case "write_file": return .blue
        case "read_file": return .purple
        case "create_directory": return .orange
        case "list_directory": return .teal
        default: return .secondary
        }
    }

    private func displayTitle(for tool: String) -> String {
        let args = toolCall.parsedArguments
        switch tool {
        case "run_terminal_command":
            if let cmd = args["command"] as? String {
                let firstWord = cmd.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? "command"
                return "Command: \(firstWord)"
            }
            return "Terminal Command"
        case "list_directory":
            let path = (args["path"] as? String) ?? "."
            return "Command: ls \(path)"
        case "read_file":
            let path = (args["path"] as? String) ?? ""
            let filename = (path as NSString).lastPathComponent
            return "Command: cat \(filename.isEmpty ? path : filename)"
        case "write_file":
            let path = (args["path"] as? String) ?? ""
            let filename = (path as NSString).lastPathComponent
            return "Command: write \(filename.isEmpty ? path : filename)"
        case "create_directory":
            let path = (args["path"] as? String) ?? ""
            let foldername = (path as NSString).lastPathComponent
            return "Command: mkdir \(foldername.isEmpty ? path : foldername)"
        default:
            return tool
        }
    }
}
