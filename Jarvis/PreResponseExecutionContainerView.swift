//
//  PreResponseExecutionContainerView.swift
//  Jarvis
//
//  Created by Antigravity on 2026-09-17.
//

import SwiftUI
import AppKit

struct PreResponseExecutionContainerView: View {
    let steps: [ChatMessage]
    var finalReasoning: String? = nil
    var workingMemory: String? = nil
    var isGenerating: Bool = false
    var turnDuration: Double? = nil
    var onApproveToolCall: ((UUID) -> Void)? = nil
    var onAlwaysApproveToolCall: ((UUID) -> Void)? = nil
    var onRejectToolCall: ((UUID) -> Void)? = nil
    var onRejectWithFeedback: ((UUID, String) -> Void)? = nil
    var onUpdateArguments: ((UUID, String) -> Void)? = nil

    @State private var isExpanded: Bool
    @State private var isHeaderHovered: Bool = false
    @State private var isCopiedThoughts: Bool = false

    init(
        steps: [ChatMessage],
        finalReasoning: String? = nil,
        workingMemory: String? = nil,
        isGenerating: Bool = false,
        turnDuration: Double? = nil,
        onApproveToolCall: ((UUID) -> Void)? = nil,
        onAlwaysApproveToolCall: ((UUID) -> Void)? = nil,
        onRejectToolCall: ((UUID) -> Void)? = nil,
        onRejectWithFeedback: ((UUID, String) -> Void)? = nil,
        onUpdateArguments: ((UUID, String) -> Void)? = nil
    ) {
        self.steps = steps
        self.finalReasoning = finalReasoning
        self.workingMemory = workingMemory
        self.isGenerating = isGenerating
        self.turnDuration = turnDuration
        self.onApproveToolCall = onApproveToolCall
        self.onAlwaysApproveToolCall = onAlwaysApproveToolCall
        self.onRejectToolCall = onRejectToolCall
        self.onRejectWithFeedback = onRejectWithFeedback
        self.onUpdateArguments = onUpdateArguments

        // Expand while generating or executing
        _isExpanded = State(initialValue: isGenerating)
    }

    private var toolCallsWithIds: [(id: UUID, tool: ToolCallRecord)] {
        var seenIds = Set<String>()
        var list: [(id: UUID, tool: ToolCallRecord)] = []
        for msg in steps {
            if let tool = msg.toolCall, tool.status != .pendingApproval {
                if !seenIds.contains(tool.id) {
                    seenIds.insert(tool.id)
                    list.append((id: msg.id, tool: tool))
                }
            }
        }
        return list
    }

    private var allReasoningCombined: String {
        var sections: [String] = []

        // 1. Task Working Memory
        let mem = workingMemory?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mem = mem, !mem.isEmpty {
            sections.append("### Task Working Memory\n\(mem)")
        }

        // 2. Step Reasoning and Thoughts
        var stepCount = 0
        var seenToolIds = Set<String>()

        for step in steps {
            var stepParts: [String] = []

            // Collect thought text from either reasoningContent or pre-tool assistant content
            var thoughtText: String?
            if let r = step.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
                thoughtText = r
            } else if step.role == .assistant && step.toolCall != nil {
                let c = step.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !c.isEmpty {
                    thoughtText = c
                }
            }

            if let thought = thoughtText {
                stepParts.append(thought)
            }

            // Include tool execution info if not previously included
            if let tool = step.toolCall, tool.status != .pendingApproval, !seenToolIds.contains(tool.id) {
                seenToolIds.insert(tool.id)
                var toolSummary = "Action: `\(tool.name)`"
                let args = tool.parsedArguments
                if tool.name == "run_terminal_command", let cmd = args["command"] as? String {
                    toolSummary += "\nCommand: `\(cmd)`"
                } else if let path = args["path"] as? String {
                    toolSummary += " (\(path))"
                } else if let paths = args["paths"] as? [String] {
                    toolSummary += " (\(paths.joined(separator: ", ")))"
                }
                if let stdout = tool.stdout?.trimmingCharacters(in: .whitespacesAndNewlines), !stdout.isEmpty {
                    let preview = stdout.count > 300 ? String(stdout.prefix(300)) + "..." : stdout
                    toolSummary += "\nOutput Preview:\n```\n\(preview)\n```"
                }
                stepParts.append(toolSummary)
            }

            if !stepParts.isEmpty {
                stepCount += 1
                sections.append("#### Step \(stepCount)\n" + stepParts.joined(separator: "\n\n"))
            }
        }

        // 3. Final Assistant Reasoning
        if let fr = finalReasoning?.trimmingCharacters(in: .whitespacesAndNewlines), !fr.isEmpty {
            if !sections.contains(where: { $0.contains(fr) }) {
                sections.append("### Final Reasoning\n\(fr)")
            }
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    private var totalToolDuration: Double {
        toolCallsWithIds.compactMap { $0.tool.duration }.reduce(0, +)
    }

    private var formattedDuration: String? {
        guard let dur = turnDuration ?? (totalToolDuration > 0 ? totalToolDuration : nil) else {
            return nil
        }
        if dur < 1.0 {
            return String(format: "%.1fs", dur)
        } else if dur < 60.0 {
            return String(format: "%.0fs", dur)
        } else {
            let minutes = Int(dur) / 60
            let seconds = Int(dur) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Container Header / Toggle Pill
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 10)

                        Image(systemName: isGenerating ? "brain.head.profile" : "shield.checkered")
                            .font(.system(size: 11))
                            .foregroundColor(isGenerating ? .accentColor : .secondary)

                        Text(headerTitle)
                            .font(.system(size: 12, weight: .medium))

                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    }
                    .foregroundColor(isHeaderHovered ? .primary : .secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .background(isHeaderHovered ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHeaderHovered = hovering
                }

                // Copy Thoughts Button
                if !allReasoningCombined.isEmpty {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(allReasoningCombined, forType: .string)
                        isCopiedThoughts = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isCopiedThoughts = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isCopiedThoughts ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(isCopiedThoughts ? "Copied Thoughts" : "Copy Thoughts")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(isCopiedThoughts ? .green : .secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 7)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Copy all internal reasoning steps to clipboard")
                }

                Spacer()
            }

            // Expanded Container Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // 1. Persistent Working Memory (if active, with scrollable compact frame)
                    if let memory = workingMemory, !memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: "list.bullet.clipboard.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.teal)
                                Text("Task Working Memory")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            ScrollView(.vertical) {
                                Text(memory)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 120)
                            .background(Color.teal.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.teal.opacity(0.2), lineWidth: 1)
                            )
                            .cornerRadius(6)
                        }
                        .padding(.bottom, 2)
                    }

                    // 2. Sequential Execution Steps (Reasoning + Tool Cards)
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            // Intermediate reasoning for this step (compact expandable pill)
                            let thoughtToDisplay: String? = {
                                if let r = step.reasoningContent, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return r.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                if step.role == .assistant && step.toolCall != nil {
                                    let c = step.content.trimmingCharacters(in: .whitespacesAndNewlines)
                                    return c.isEmpty ? nil : c
                                }
                                return nil
                            }()

                            if let reasoning = thoughtToDisplay {
                                StepReasoningPillView(reasoning: reasoning, stepIndex: index + 1)
                            }

                            // Tool Execution Card (only after approved / running / completed / rejected)
                            if let tool = step.toolCall, tool.status != .pendingApproval {
                                ToolExecutionCardView(
                                    toolCall: tool,
                                    isGenerating: isGenerating,
                                    isDocked: false,
                                    onApprove: { onApproveToolCall?(step.id) },
                                    onReject: { onRejectToolCall?(step.id) },
                                    onAlwaysApprove: { onAlwaysApproveToolCall?(step.id) },
                                    onRejectWithFeedback: { fb in onRejectWithFeedback?(step.id, fb) },
                                    onUpdateArguments: { args in onUpdateArguments?(step.id, args) }
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }
                    }
                }
                .padding(.leading, 6)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: isGenerating) { generating in
            // Auto-collapse when generation finishes
            if !generating {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded = false
                }
            }
        }
    }

    private var headerTitle: String {
        let count = toolCallsWithIds.count
        if isGenerating {
            if count > 0 {
                return "Executing Action \(count)..."
            }
            return "Thinking & Preparing..."
        }
        let durStr = formattedDuration != nil ? " • \(formattedDuration!)" : ""
        if count > 0 {
            return "Execution & Reasoning (\(count) action\(count == 1 ? "" : "s")\(durStr))"
        }
        return "Thought Process\(durStr)"
    }
}

/// Compact, collapsible thought process pill for individual execution steps
struct StepReasoningPillView: View {
    let reasoning: String
    var stepIndex: Int? = nil

    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false
    @State private var isCopied: Bool = false

    private var wordCount: Int {
        reasoning.split(whereSeparator: { $0.isWhitespace }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 8)

                        Image(systemName: "brain")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        let label = stepIndex != nil ? "Thought Process • Step \(stepIndex!) (\(wordCount) words)" : "Thought Process (\(wordCount) words)"
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(isHovered ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovered = hovering
                }

                if isExpanded {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reasoning, forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isCopied = false
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(isCopied ? "Copied" : "Copy")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(isCopied ? .green : .secondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            if isExpanded {
                Text(reasoning)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
