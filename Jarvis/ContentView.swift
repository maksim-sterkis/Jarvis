//
//  ContentView.swift
//  Jarvis
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            ChatDetailView(viewModel: viewModel)
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showThinkingPopover: Bool = false
    @AppStorage("snapToTopAfterGeneration") private var snapToTopAfterGeneration: Bool = true
    @FocusState private var isInputFocused: Bool

    private let suggestions = [
        "List files in my home folder and show disk space",
        "Create a test folder on my Desktop with a hello.py file",
        "Read system uptime and network info via terminal",
        "What terminal and file capabilities do you have?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            HStack(spacing: 10) {
                // 1. Model Selector Menu
                Menu {
                    if viewModel.availableModels.isEmpty {
                        Button(displayModelName(viewModel.selectedModel)) {
                            viewModel.selectedModel = "google/gemma-4-e2b"
                        }
                    } else {
                        ForEach(viewModel.availableModels) { model in
                            Button(action: {
                                viewModel.selectedModel = model.id
                            }) {
                                Label {
                                    Text(boldMenuLabel(model.id, isLoaded: model.isLoaded))
                                } icon: {
                                    if model.id == viewModel.selectedModel {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Refresh Models & Status") {
                        viewModel.checkConnection()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)

                        Text(displayModelName(viewModel.selectedModel))
                            .font(.system(size: 13, weight: .semibold))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // 2. Thinking / Reasoning Button (Fixed 155pt width, no truncation, no token numbers)
                Button(action: {
                    showThinkingPopover.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isThinkingEnabled ? "brain.fill" : "brain")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(viewModel.isThinkingEnabled ? .accentColor : .secondary)

                        Text("Thinking: \(viewModel.isThinkingEnabled ? viewModel.selectedPreset.rawValue : "Off")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(viewModel.isThinkingEnabled ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 155) // Constant width: perfectly stable, never truncates
                    .background(viewModel.isThinkingEnabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showThinkingPopover, arrowEdge: .bottom) {
                    ThinkingPopoverView(viewModel: viewModel, isPresented: $showThinkingPopover)
                }

                // 3. Workspace Working Directory Selector
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.prompt = "Set Directory"
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.activeWorkingDirectory = url.path
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(displayPath(viewModel.activeWorkingDirectory))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Active directory for commands and file tools. Click to change.")

                if !viewModel.isConnected {
                    Text("Offline • Check LM Studio (127.0.0.1:1234)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    isInputFocused = false
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            )

            Divider()

            // Chat Area
            ScrollViewReader { proxy in
                ScrollView {
                    let messages = viewModel.currentConversation?.messages ?? []

                    if messages.isEmpty {
                        // Empty State / Welcome Screen
                        VStack(spacing: 24) {
                            Spacer(minLength: 40)

                            JarvisLogoView(size: 60, showBackground: false, color: .primary)

                            VStack(spacing: 6) {
                                Text("What can I help you with today?")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.primary)

                                HStack(spacing: 6) {
                                    Text("Model: \(viewModel.selectedModel)")
                                    Text("•")
                                    Text(viewModel.isThinkingEnabled ? "Reasoning: \(viewModel.selectedPreset.rawValue)" : "Reasoning: Off")
                                    Text("•")
                                    Text("Tools: Enabled")
                                }
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            }

                            // Suggestions Grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(action: {
                                        viewModel.inputText = suggestion
                                    }) {
                                        HStack {
                                            Text(suggestion)
                                                .font(.system(size: 13))
                                                .foregroundColor(.primary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: 620)
                            .padding(.top, 10)

                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        // Messages Stream grouped by turns
                        VStack(spacing: 20) {
                            ForEach(groupMessagesIntoTurns(messages)) { turn in
                                if let boundary = turn.compressionBoundaryMessage {
                                    MessageRowView(
                                        message: boundary,
                                        isGenerating: false
                                    )
                                    .id(boundary.id)
                                } else {
                                    VStack(alignment: .leading, spacing: 14) {
                                        // 1. User Message
                                        if let userMsg = turn.userMessage {
                                            MessageRowView(
                                                message: userMsg,
                                                isGenerating: false
                                            )
                                            .id(userMsg.id)
                                        }

                                        // 2. Pre-Response Execution Container (Collapsible)
                                        if hasVisiblePreResponseContent(in: turn) {
                                            let isCurrentTurnActive = viewModel.isGenerating && (turn.finalAssistantMessage == messages.last || turn.preResponseSteps.last == messages.last)
                                            PreResponseExecutionContainerView(
                                                steps: turn.preResponseSteps,
                                                finalReasoning: turn.finalAssistantMessage?.reasoningContent,
                                                workingMemory: turn.workingMemory ?? viewModel.activeWorkingMemory,
                                                isGenerating: isCurrentTurnActive,
                                                turnDuration: turn.totalTurnDuration,
                                                onApproveToolCall: { id in
                                                    viewModel.approveToolCall(messageId: id)
                                                },
                                                onAlwaysApproveToolCall: { id in
                                                    viewModel.alwaysApproveToolCall(messageId: id)
                                                },
                                                onRejectToolCall: { id in
                                                    viewModel.rejectToolCall(messageId: id)
                                                },
                                                onRejectWithFeedback: { id, fb in
                                                    viewModel.rejectToolCall(messageId: id, feedback: fb)
                                                },
                                                onUpdateArguments: { id, args in
                                                    viewModel.updateToolArguments(messageId: id, newArgumentsJSON: args)
                                                }
                                            )
                                            .id("\(turn.id)-execution-container")
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                        }

                                        // 3. Final Assistant Response
                                        if let assistantMsg = turn.finalAssistantMessage {
                                            MessageRowView(
                                                message: assistantMsg,
                                                isGenerating: viewModel.isGenerating && assistantMsg == messages.last,
                                                hideReasoningPill: !turn.preResponseSteps.isEmpty,
                                                onApproveToolCall: {
                                                    viewModel.approveToolCall(messageId: assistantMsg.id)
                                                },
                                                onAlwaysApproveToolCall: {
                                                    viewModel.alwaysApproveToolCall(messageId: assistantMsg.id)
                                                },
                                                onRejectToolCall: {
                                                    viewModel.rejectToolCall(messageId: assistantMsg.id)
                                                },
                                                onRejectWithFeedback: { feedback in
                                                    viewModel.rejectToolCall(messageId: assistantMsg.id, feedback: feedback)
                                                },
                                                onUpdateArguments: { newArgs in
                                                    viewModel.updateToolArguments(messageId: assistantMsg.id, newArgumentsJSON: newArgs)
                                                }
                                            )
                                            .id(assistantMsg.id)
                                        }
                                    }
                                }
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("bottomAnchor")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                    }
                }
                .onChange(of: viewModel.currentConversation?.messages.last?.content) { _ in
                    if viewModel.isGenerating && snapToTopAfterGeneration {
                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.currentConversation?.messages.last?.reasoningContent) { _ in
                    if viewModel.isGenerating && snapToTopAfterGeneration {
                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isGenerating) { isGenerating in
                    if !isGenerating && snapToTopAfterGeneration {
                        if let currentMessages = viewModel.currentConversation?.messages,
                           let lastUserMsg = currentMessages.last(where: { $0.role == .user }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(lastUserMsg.id, anchor: .top)
                                }
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isInputFocused = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                )
            }

            // Prompt Box at bottom with Send & Stop actions + Docked Approval Card
            HStack(spacing: 0) {
                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isInputFocused = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                VStack(spacing: 10) {
                    // Docked Action Approval Card directly above prompt input box
                    if let pendingMsg = pendingApprovalMessage, let tool = pendingMsg.toolCall {
                        ToolExecutionCardView(
                            toolCall: tool,
                            isGenerating: viewModel.isGenerating,
                            isDocked: true,
                            onApprove: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.approveToolCall(messageId: pendingMsg.id)
                                }
                            },
                            onReject: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.rejectToolCall(messageId: pendingMsg.id)
                                }
                            },
                            onAlwaysApprove: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.alwaysApproveToolCall(messageId: pendingMsg.id)
                                }
                            },
                            onRejectWithFeedback: { feedback in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.rejectToolCall(messageId: pendingMsg.id, feedback: feedback)
                                }
                            },
                            onUpdateArguments: { newArgs in
                                viewModel.updateToolArguments(messageId: pendingMsg.id, newArgumentsJSON: newArgs)
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }

                    PromptInputView(
                        text: $viewModel.inputText,
                        isGenerating: viewModel.isGenerating,
                        contextUsed: viewModel.currentContextTokens,
                        contextTotal: viewModel.totalContextLimit,
                        isFocused: $isInputFocused,
                        onSend: {
                            viewModel.sendMessage()
                        },
                        onStop: {
                            viewModel.stopGenerating()
                        }
                    )
                }
                .frame(maxWidth: 760)

                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isInputFocused = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: isInputFocused) { focused in
            if focused && showThinkingPopover {
                showThinkingPopover = false
            }
        }
    }

    private var pendingApprovalMessage: ChatMessage? {
        viewModel.currentConversation?.messages.last(where: { $0.toolCall?.status == .pendingApproval })
    }

    private func hasVisiblePreResponseContent(in turn: ConversationTurn) -> Bool {
        if let memory = turn.workingMemory, !memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        for step in turn.preResponseSteps {
            if let r = step.reasoningContent, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            if step.role == .assistant && step.toolCall != nil && !step.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            if let tool = step.toolCall, tool.status != .pendingApproval {
                return true
            }
        }
        return false
    }

    private func displayModelName(_ id: String) -> String {
        if id.contains("/") {
            return id.components(separatedBy: "/").last ?? id
        }
        return id
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        } else if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return (path as NSString).lastPathComponent
    }

    private func boldMenuLabel(_ id: String, isLoaded: Bool) -> AttributedString {
        var str = AttributedString(id)
        if isLoaded {
            str.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        }
        return str
    }

    private func groupMessagesIntoTurns(_ messages: [ChatMessage]) -> [ConversationTurn] {
        var turns: [ConversationTurn] = []
        var currentTurn: ConversationTurn?

        for message in messages {
            if message.isCompressionBoundary == true {
                if let t = currentTurn {
                    turns.append(t)
                    currentTurn = nil
                }
                turns.append(ConversationTurn(
                    id: message.id,
                    userMessage: nil,
                    preResponseSteps: [],
                    finalAssistantMessage: nil,
                    compressionBoundaryMessage: message,
                    workingMemory: nil
                ))
                continue
            }

            if message.role == .user {
                if let t = currentTurn {
                    turns.append(t)
                }
                currentTurn = ConversationTurn(
                    id: message.id,
                    userMessage: message,
                    preResponseSteps: [],
                    finalAssistantMessage: nil,
                    compressionBoundaryMessage: nil,
                    workingMemory: nil
                )
            } else if message.role == .tool {
                if currentTurn == nil {
                    currentTurn = ConversationTurn(id: message.id, userMessage: nil, preResponseSteps: [], finalAssistantMessage: nil, compressionBoundaryMessage: nil, workingMemory: nil)
                }
                currentTurn?.preResponseSteps.append(message)
            } else if message.role == .assistant {
                if currentTurn == nil {
                    currentTurn = ConversationTurn(id: message.id, userMessage: nil, preResponseSteps: [], finalAssistantMessage: nil, compressionBoundaryMessage: nil, workingMemory: nil)
                }
                if message.toolCall != nil {
                    currentTurn?.preResponseSteps.append(message)
                } else {
                    if let wm = message.workingMemory {
                        currentTurn?.workingMemory = wm
                    }
                    currentTurn?.finalAssistantMessage = message
                }
                if let dur = message.totalTurnDuration {
                    currentTurn?.totalTurnDuration = dur
                }
            }
        }

        func finalizeTurnDuration(_ turn: inout ConversationTurn) {
            if turn.totalTurnDuration != nil { return }
            guard let userTimestamp = turn.userMessage?.timestamp else { return }
            let endTimestamp = turn.finalAssistantMessage?.timestamp ?? turn.preResponseSteps.last?.timestamp
            if let end = endTimestamp {
                let diff = end.timeIntervalSince(userTimestamp)
                if diff > 0.1 {
                    turn.totalTurnDuration = diff
                }
            }
        }

        if var t = currentTurn {
            finalizeTurnDuration(&t)
            turns.append(t)
        }

        return turns
    }
}

struct ConversationTurn: Identifiable {
    let id: UUID
    var userMessage: ChatMessage?
    var preResponseSteps: [ChatMessage] = []
    var finalAssistantMessage: ChatMessage?
    var compressionBoundaryMessage: ChatMessage?
    var workingMemory: String?
    var totalTurnDuration: Double?
}

struct ThinkingPopoverView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Reasoning / Thinking", systemImage: "brain")
                    .font(.subheadline.bold())
                Spacer()
                Toggle("", isOn: $viewModel.isThinkingEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }

            if viewModel.isThinkingEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reasoning Level")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    // Preset Buttons
                    HStack(spacing: 6) {
                        ForEach(ThinkingPreset.allCases) { preset in
                            Button(action: {
                                viewModel.setThinkingPreset(preset)
                            }) {
                                Text(preset.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(viewModel.selectedPreset == preset ? Color.accentColor : Color.secondary.opacity(0.12))
                                    .foregroundColor(viewModel.selectedPreset == preset ? .white : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Continuous Slider
                    VStack(spacing: 4) {
                        HStack {
                            Text("Token Budget:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(viewModel.thinkingBudget)) tokens")
                                .font(.system(.caption, design: .monospaced).bold())
                        }

                        Slider(value: $viewModel.thinkingBudget, in: 256...6144, step: 256)
                    }
                    .padding(.top, 4)
                }

                Text("Appends a thinking level instruction to the prompt.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("Thinking is disabled. A tag is sent with each prompt instructing the model to answer directly without internal reasoning.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

struct MessageRowView: View {
    let message: ChatMessage
    var isGenerating: Bool = false
    var hideReasoningPill: Bool = false
    var onApproveToolCall: (() -> Void)? = nil
    var onAlwaysApproveToolCall: (() -> Void)? = nil
    var onRejectToolCall: (() -> Void)? = nil
    var onRejectWithFeedback: ((String) -> Void)? = nil
    var onUpdateArguments: ((String) -> Void)? = nil
    @State private var isCopied: Bool = false
    @State private var isThoughtCopied: Bool = false
    @State private var isThoughtExpanded: Bool
    @State private var isThoughtHovered: Bool = false

    init(
        message: ChatMessage,
        isGenerating: Bool = false,
        hideReasoningPill: Bool = false,
        onApproveToolCall: (() -> Void)? = nil,
        onAlwaysApproveToolCall: (() -> Void)? = nil,
        onRejectToolCall: (() -> Void)? = nil,
        onRejectWithFeedback: ((String) -> Void)? = nil,
        onUpdateArguments: ((String) -> Void)? = nil
    ) {
        self.message = message
        self.isGenerating = isGenerating
        self.hideReasoningPill = hideReasoningPill
        self.onApproveToolCall = onApproveToolCall
        self.onAlwaysApproveToolCall = onAlwaysApproveToolCall
        self.onRejectToolCall = onRejectToolCall
        self.onRejectWithFeedback = onRejectWithFeedback
        self.onUpdateArguments = onUpdateArguments

        // If the message has already finished generating, collapse the thought by default
        let toolFinished = message.toolCall?.status == .completed || message.toolCall?.status == .failed || message.toolCall?.status == .rejected
        let isHistorical = !isGenerating && (!message.content.isEmpty || toolFinished)
        _isThoughtExpanded = State(initialValue: !isHistorical)
    }

    var body: some View {
        if message.isCompressionBoundary == true {
            CompressionBoundaryView(
                snapshot: message.compressedSnapshot ?? "",
                tokenSavingsPercent: message.compressionSavingsPercent ?? 80,
                compressionLevel: message.compressionLevel,
                tokensBefore: message.tokensBeforeCompression,
                tokensAfter: message.tokensAfterCompression
            )
        } else {
            HStack(alignment: .top, spacing: 12) {
                if message.role == .assistant {
                    VStack(alignment: .leading, spacing: 8) {
                        // Collapsible Reasoning / Thought Process
                        if !hideReasoningPill, let reasoning = message.reasoningContent, !reasoning.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isThoughtExpanded.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: isThoughtExpanded ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 9, weight: .bold))
                                                .frame(width: 10)

                                            Image(systemName: "brain")
                                                .font(.system(size: 11))

                                            Text(isGenerating && message.content.isEmpty ? "Thinking..." : "Thought Process")
                                                .font(.system(size: 12, weight: .medium))

                                            if isGenerating && message.content.isEmpty {
                                                ProgressView()
                                                    .scaleEffect(0.5)
                                            }
                                        }
                                        .foregroundColor(isThoughtHovered ? .primary : .secondary)
                                        .padding(.vertical, 5)
                                        .padding(.horizontal, 8)
                                        .background(isThoughtHovered ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.05))
                                        .cornerRadius(6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { hovering in
                                        isThoughtHovered = hovering
                                    }

                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(reasoning, forType: .string)
                                        isThoughtCopied = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            isThoughtCopied = false
                                        }
                                    }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: isThoughtCopied ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 10))
                                            Text(isThoughtCopied ? "Copied" : "Copy thought")
                                                .font(.system(size: 10))
                                        }
                                        .foregroundColor(isThoughtCopied ? .green : .secondary)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 6)
                                        .background(Color.secondary.opacity(0.06))
                                        .cornerRadius(5)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy reasoning to clipboard")
                                }
                                .onChange(of: isGenerating) { generating in
                                    // Auto-collapse once response finishes (plain text reply)
                                    if !generating && !message.content.isEmpty {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isThoughtExpanded = false
                                        }
                                    }
                                }
                                .onChange(of: message.toolCall?.status) { status in
                                    // Auto-collapse when a tool call on this message completes/fails
                                    // (in tool-call messages, content stays empty, so we watch status instead)
                                    if status == .completed || status == .failed || status == .rejected {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isThoughtExpanded = false
                                        }
                                    }
                                }

                                if isThoughtExpanded {
                                    Text(reasoning)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.06))
                                        .cornerRadius(8)
                                        .textSelection(.enabled)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.bottom, 4)
                        }

                        // Tool Execution Card (if a tool was called and not pending approval)
                        if let tool = message.toolCall, tool.status != .pendingApproval {
                            ToolExecutionCardView(
                                toolCall: tool,
                                isGenerating: isGenerating,
                                isDocked: false,
                                onApprove: { onApproveToolCall?() },
                                onReject: { onRejectToolCall?() },
                                onAlwaysApprove: { onAlwaysApproveToolCall?() },
                                onRejectWithFeedback: { feedback in onRejectWithFeedback?(feedback) },
                                onUpdateArguments: { newArgs in onUpdateArguments?(newArgs) }
                            )
                            .padding(.vertical, 2)
                        }

                        // Rich Markdown Formatted Content
                        if message.content.isEmpty {
                            if isGenerating && (message.reasoningContent == nil || message.reasoningContent?.isEmpty == true) && message.toolCall == nil {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Connecting to model...")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            MarkdownMessageView(content: message.content)
                        }

                        // Action bar
                        if !message.content.isEmpty {
                            HStack(spacing: 12) {
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.content, forType: .string)
                                    isCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        isCopied = false
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                        Text(isCopied ? "Copied" : "Copy message")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 40)
                } else if message.role == .tool {
                    // Subtle tool result log indicator
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Result received • Model responding")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                } else {
                    Spacer(minLength: 40)

                    // User Bubble
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                        )
                        .textSelection(.enabled)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
