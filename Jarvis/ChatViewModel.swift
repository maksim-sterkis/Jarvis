//
//  ChatViewModel.swift
//  Jarvis
//

import SwiftUI
import Combine

enum MessageRole: String, Codable {
    case user
    case assistant
    case tool
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    var reasoningContent: String?
    var toolCall: ToolCallRecord?
    var toolCallId: String?
    let timestamp: Date
    var isCompressionBoundary: Bool?
    var compressedSnapshot: String?
    var compressionSavingsPercent: Int?
    var compressionLevel: String?
    var tokensBeforeCompression: Int?
    var tokensAfterCompression: Int?
    var workingMemory: String?
    var totalTurnDuration: Double?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        reasoningContent: String? = nil,
        toolCall: ToolCallRecord? = nil,
        toolCallId: String? = nil,
        timestamp: Date = Date(),
        isCompressionBoundary: Bool? = nil,
        compressedSnapshot: String? = nil,
        compressionSavingsPercent: Int? = nil,
        compressionLevel: String? = nil,
        tokensBeforeCompression: Int? = nil,
        tokensAfterCompression: Int? = nil,
        workingMemory: String? = nil,
        totalTurnDuration: Double? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCall = toolCall
        self.toolCallId = toolCallId
        self.timestamp = timestamp
        self.isCompressionBoundary = isCompressionBoundary
        self.compressedSnapshot = compressedSnapshot
        self.compressionSavingsPercent = compressionSavingsPercent
        self.compressionLevel = compressionLevel
        self.tokensBeforeCompression = tokensBeforeCompression
        self.tokensAfterCompression = tokensAfterCompression
        self.workingMemory = workingMemory
        self.totalTurnDuration = totalTurnDuration
    }
}

struct ChatConversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date
    var tokenCount: Int?

    init(id: UUID = UUID(), title: String = "New Chat", messages: [ChatMessage] = [], updatedAt: Date = Date(), tokenCount: Int? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
        self.tokenCount = tokenCount
    }
}

enum ThinkingPreset: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Med"
    case high = "High"
    case max = "Max"

    var id: String { rawValue }

    var defaultBudget: Int {
        switch self {
        case .low: return 512
        case .medium: return 1536
        case .high: return 3072
        case .max: return 6144
        }
    }
}

enum CompressionLevel: String, CaseIterable, Identifiable {
    case low = "low"
    case med = "med"
    case high = "high"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low (~50% retention)"
        case .med: return "Med (~75% balanced)"
        case .high: return "High (~90% compact)"
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var selectedConversationId: UUID?
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false

    // Local model connection state
    @Published var isConnected: Bool = false
    @Published var availableModels: [LMModelInfo] = []
    @Published var selectedModel: String = "google/gemma-4-e2b"
    @Published var loadedModelId: String? = nil
    @Published var errorMessage: String? = nil

    // Model Activation & Progress
    @Published var isModelLoading: Bool = false
    @Published var modelLoadProgress: Double = 0.0
    @Published var modelLoadingStatus: String = ""

    // Thinking / Reasoning Configuration
    @Published var isThinkingEnabled: Bool = true
    @Published var thinkingBudget: Double = 1536
    @Published var selectedPreset: ThinkingPreset = .medium

    // Agent Configuration
    @Published var activeWorkingDirectory: String = NSHomeDirectory()
    @Published var activeWorkingMemory: String? = nil
    @Published var turnStartTime: Date? = nil
    @Published var turnActionCount: Int = 0

    // In-App Document Viewer Sheet
    @Published var activeDocumentViewer: DocumentViewerState? = nil

    private var checkTimer: AnyCancellable?
    private var activeGenerationTask: Task<Void, Never>?

    static weak var shared: ChatViewModel?

    static func stopAllTimers() {
        shared?.checkTimer?.cancel()
        shared?.checkTimer = nil
        shared?.stopGenerating()
    }

    init() {
        ChatViewModel.shared = self
        // Load past conversations from disk, then open a fresh new chat
        let saved = ConversationStorageService.shared.loadAllConversations()
        self.conversations = saved
        startNewChat()
        // Load cached disk models immediately so UI has models with 0ms latency and 0 CLI calls
        self.availableModels = LMStudioService.shared.scanDiskModelsWithoutCLI()
        if let first = self.availableModels.first, self.selectedModel.isEmpty {
            self.selectedModel = first.id
        }

        checkConnectionAndAutoStart()

        // Periodic heartbeat check every 15s
        checkTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkConnection()
            }
    }

    var currentConversation: ChatConversation? {
        get {
            guard let id = selectedConversationId else { return nil }
            return conversations.first(where: { $0.id == id })
        }
        set {
            guard let newValue = newValue,
                  let index = conversations.firstIndex(where: { $0.id == newValue.id }) else { return }
            conversations[index] = newValue
            ConversationStorageService.shared.saveConversation(newValue)
        }
    }

    var totalContextLimit: Int {
        if let model = availableModels.first(where: { $0.id == selectedModel }),
           let limit = model.contextLength, limit > 0 {
            return limit
        }
        return 8192
    }

    /// Returns the messages that should actually be sent to the AI model.
    /// If a compression boundary exists, returns an anchor message containing the snapshot + all messages after the boundary.
    func activeContextMessages(for conversation: ChatConversation) -> [ChatMessage] {
        if let lastBoundaryIndex = conversation.messages.lastIndex(where: { $0.isCompressionBoundary == true }),
           let snapshot = conversation.messages[lastBoundaryIndex].compressedSnapshot {
            let anchorMessage = ChatMessage(
                role: .assistant,
                content: "[Prior Context Snapshot - Compressed Memory Anchor]\n" + snapshot
            )
            let postBoundary = conversation.messages.suffix(from: lastBoundaryIndex + 1)
            return [anchorMessage] + Array(postBoundary)
        }
        return conversation.messages
    }

    var currentContextTokens: Int {
        guard let conv = currentConversation else { return 0 }
        let activeMsgs = activeContextMessages(for: conv)
        let totalChars = activeMsgs.reduce(0) { $0 + $1.content.count + ($1.reasoningContent?.count ?? 0) }
        return max(0, Int(Double(totalChars) / 3.8))
    }

    func startNewChat() {
        if let first = conversations.first, first.messages.isEmpty {
            selectedConversationId = first.id
            errorMessage = nil
            return
        }
        let newChat = ChatConversation()
        conversations.insert(newChat, at: 0)
        selectedConversationId = newChat.id
        errorMessage = nil
    }

    func selectConversation(id: UUID) {
        selectedConversationId = id
    }

    func deleteConversation(id: UUID) {
        ConversationStorageService.shared.deleteConversation(id: id)
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = conversations.first?.id
            if selectedConversationId == nil {
                startNewChat()
            }
        }
    }

    func stopGenerating() {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        isGenerating = false

        if let start = turnStartTime,
           let convId = selectedConversationId,
           let convIndex = conversations.firstIndex(where: { $0.id == convId }),
           let lastAssistantIndex = conversations[convIndex].messages.lastIndex(where: { $0.role == .assistant }) {
            let elapsed = Date().timeIntervalSince(start)
            conversations[convIndex].messages[lastAssistantIndex].totalTurnDuration = elapsed
            ConversationStorageService.shared.saveConversation(conversations[convIndex])
        }
    }

    func setThinkingPreset(_ preset: ThinkingPreset) {
        selectedPreset = preset
        thinkingBudget = Double(preset.defaultBudget)
        isThinkingEnabled = true
    }

    /// Checks if LM Studio is already running at startup.
    /// If running: connects to it and sets `didJarvisLaunchServer = false` (user launched it).
    /// If NOT running: sets `didJarvisLaunchServer = false`, stays offline, and NEVER runs CLI commands unless autoStartServerOnLaunch is true.
    func checkConnectionAndAutoStart() {
        Task {
            let isRunning = await LMStudioService.shared.isServerRunning()
            if isRunning {
                // LM Studio was already launched by the user before opening Jarvis!
                // Jarvis connects to the existing instance without claiming ownership.
                await MainActor.run {
                    LMStudioService.shared.didJarvisLaunchServer = false
                }
                await checkConnectionAsync()
            } else {
                await MainActor.run {
                    LMStudioService.shared.didJarvisLaunchServer = false
                    self.isConnected = false
                    self.loadedModelId = nil
                }

                let autoStart = UserDefaults.standard.bool(forKey: "autoStartServerOnLaunch")
                if autoStart {
                    let targetModel = self.selectedModel.isEmpty ? (self.availableModels.first?.id ?? "google/gemma-4-e2b") : self.selectedModel
                    self.activateModel(modelId: targetModel)
                }
            }
        }
    }

    func checkConnection() {
        Task {
            await checkConnectionAsync()
        }
    }

    @MainActor
    private func checkConnectionAsync() async {
        do {
            let models = try await LMStudioClient.shared.fetchModels()
            self.availableModels = models
            LMStudioService.shared.saveCachedModels(models)
            self.isConnected = true
            self.errorMessage = nil

            // Auto-detect and auto-select the loaded model
            if let loaded = models.first(where: { $0.isLoaded }) {
                self.loadedModelId = loaded.id
                self.selectedModel = loaded.id
            } else if !models.contains(where: { $0.id == self.selectedModel }), let first = models.first {
                self.selectedModel = first.id
            }
        } catch {
            self.isConnected = false
            self.loadedModelId = nil
            // When offline, do NOT run `lms ls` CLI which wakes up LM Studio daemon.
        }
    }

    /// Activates (boots server if needed, then loads into unified memory) a model with real-time UI progress updates.
    func activateModel(modelId: String, convIdForNotification: UUID? = nil) {
        guard !isModelLoading else { return }
        isModelLoading = true
        modelLoadProgress = 0.0
        modelLoadingStatus = "Preparing \(modelId)..."

        if let convId = convIdForNotification {
            appendSystemNotification("Initiating model activation for `\(modelId)`...", convId: convId)
        }

        Task {
            do {
                // 1. Check server status; start local server if offline
                let isRunning = await LMStudioService.shared.isServerRunning()
                if !isRunning {
                    await MainActor.run {
                        LMStudioService.shared.didJarvisLaunchServer = true
                    }
                    self.modelLoadingStatus = "Starting LM Studio local server..."
                    self.modelLoadProgress = 0.15
                    let mode = UserDefaults.standard.string(forKey: "lmStudioLaunchMode") ?? "headless"
                    try await LMStudioService.shared.startServer(mode: mode)
                    self.modelLoadProgress = 0.35
                    self.modelLoadingStatus = "Server online. Checking memory..."
                }

                // 2. Authoritative check: Is the model ALREADY loaded in memory?
                let loadedNow = await LMStudioService.shared.listLoadedModels()
                if let alreadyLoaded = loadedNow.first(where: { $0.id == modelId || modelId.hasPrefix($0.id) || $0.id.hasPrefix(modelId) }) {
                    self.selectedModel = alreadyLoaded.id
                    self.loadedModelId = alreadyLoaded.id
                    self.isConnected = true
                    self.modelLoadProgress = 1.0
                    self.modelLoadingStatus = "Model is ready!"
                    if let convId = convIdForNotification {
                        self.appendSystemNotification("Model `\(alreadyLoaded.id)` is already loaded in memory and ready.", convId: convId)
                    }
                    self.checkConnection()
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isModelLoading = false
                    }
                    return
                }

                // 3. Unload other models to free unified memory and prevent guardrail failure
                for other in loadedNow where other.id != modelId {
                    self.modelLoadingStatus = "Freeing memory (unloading \(other.id))..."
                    await LMStudioService.shared.unloadModel(modelKey: other.id)
                }

                // 4. Load model into memory with live percentage updates and auto-recovery
                self.modelLoadingStatus = "Loading \(modelId) into memory..."
                try await LMStudioService.shared.loadModel(modelKey: modelId) { [weak self] progress, status in
                    Task { @MainActor in
                        self?.modelLoadProgress = progress
                        self?.modelLoadingStatus = status
                    }
                }

                // 5. Finalize state
                self.modelLoadProgress = 1.0
                self.modelLoadingStatus = "Model loaded successfully!"
                self.selectedModel = modelId
                self.loadedModelId = modelId
                self.isConnected = true
                self.checkConnection()

                if let convId = convIdForNotification {
                    self.appendSystemNotification("Model `\(modelId)` loaded successfully into memory!", convId: convId)
                }

                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isModelLoading = false
                }
            } catch {
                self.isModelLoading = false
                self.errorMessage = "Failed to load model: \(error.localizedDescription)"
                if let convId = convIdForNotification {
                    self.appendSystemNotification("Failed to load model `\(modelId)`: \(error.localizedDescription)", convId: convId)
                }
            }
        }
    }

    /// One-click helper to start the server and load the selected or default model.
    func startServerAndLoadModel() {
        let target = selectedModel.isEmpty ? (availableModels.first?.id ?? "google/gemma-4-e2b") : selectedModel
        activateModel(modelId: target)
    }

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        // Reset persistent working memory and turn telemetry for each new user prompt
        activeWorkingMemory = nil
        turnStartTime = Date()
        turnActionCount = 0

        // Intercept slash commands
        if trimmed.hasPrefix("/") {
            inputText = ""
            executeSlashCommand(trimmed)
            return
        }

        guard let convId = selectedConversationId,
              let index = conversations.firstIndex(where: { $0.id == convId }) else { return }

        let userMsg = ChatMessage(role: .user, content: trimmed)
        conversations[index].messages.append(userMsg)
        conversations[index].updatedAt = Date()

        if conversations[index].messages.count == 1 {
            let firstWords = trimmed.prefix(32)
            conversations[index].title = String(firstWords)
        }

        inputText = ""
        errorMessage = nil

        ConversationStorageService.shared.saveConversation(conversations[index])

        executeAssistantTurn(convId: convId)
    }

    /// Runs one turn of assistant generation, supporting tool detection.
    private func executeAssistantTurn(convId: UUID) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == convId }) else { return }

        isGenerating = true
        let assistantMsgId = UUID()
        let assistantMsg = ChatMessage(id: assistantMsgId, role: .assistant, content: "", workingMemory: self.activeWorkingMemory)
        conversations[convIndex].messages.append(assistantMsg)

        let activeHistory = activeContextMessages(for: conversations[convIndex]).dropLast()

        activeGenerationTask = Task {
            do {
                try await LMStudioClient.shared.streamChat(
                    messages: Array(activeHistory),
                    model: self.selectedModel,
                    workingDirectory: self.activeWorkingDirectory,
                    isThinkingEnabled: self.isThinkingEnabled,
                    thinkingBudget: Int(self.thinkingBudget),
                    workingMemory: self.activeWorkingMemory,
                    onReasoningDelta: { [weak self] delta in
                        guard let self = self, self.isThinkingEnabled else { return }
                        if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
                           let msgIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == assistantMsgId }) {
                            var currentReasoning = self.conversations[targetConvIndex].messages[msgIndex].reasoningContent ?? ""
                            currentReasoning.append(delta)
                            self.conversations[targetConvIndex].messages[msgIndex].reasoningContent = currentReasoning
                        }
                    },
                    onContentDelta: { [weak self] delta in
                        guard let self = self else { return }
                        if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
                           let msgIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == assistantMsgId }) {
                            self.conversations[targetConvIndex].messages[msgIndex].content.append(delta)
                        }
                    },
                    onToolCallDetected: { [weak self] detectedTool in
                        guard let self = self else { return }
                        if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
                           let msgIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == assistantMsgId }) {
                            var toolRecord = detectedTool

                            // Check security policy mode from AppSettings
                            let securityModeRaw = UserDefaults.standard.string(forKey: "agentSecurityMode") ?? AgentSecurityMode.alwaysAsk.rawValue
                            let securityMode = AgentSecurityMode(rawValue: securityModeRaw) ?? .alwaysAsk

                            // Duplicate Tool Execution Detection
                            let cleanArgs = toolRecord.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                            let alreadyRan = self.conversations[targetConvIndex].messages.suffix(6).contains(where: { msg in
                                if msg.role == .tool, let tc = msg.toolCall {
                                    return tc.name == toolRecord.name && tc.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines) == cleanArgs
                                }
                                return false
                            })

                            if alreadyRan {
                                // Model attempted to execute the exact same tool with exact same arguments repeatedly!
                                toolRecord.status = .rejected
                                self.conversations[targetConvIndex].messages[msgIndex].toolCall = toolRecord
                                let feedbackNotice = ChatMessage(
                                    role: .tool,
                                    content: "[System Directive: Tool '\(toolRecord.name)' was ALREADY executed with these identical arguments. The full output is in your conversation history above. You MUST NOT call this tool again. STOP calling tools and write your final comprehensive answer to the user now.]",
                                    toolCallId: toolRecord.id
                                )
                                self.conversations[targetConvIndex].messages.append(feedbackNotice)
                                ConversationStorageService.shared.saveConversation(self.conversations[targetConvIndex])
                                self.executeAssistantTurn(convId: convId)
                                return
                            }

                            if securityMode.isToolAutoApproved(toolName: toolRecord.name, argumentsJSON: toolRecord.argumentsJSON) {
                                toolRecord.status = .running
                                self.conversations[targetConvIndex].messages[msgIndex].toolCall = toolRecord
                                self.approveToolCall(messageId: assistantMsgId, autoApproved: true)
                            } else {
                                toolRecord.status = .pendingApproval
                                self.conversations[targetConvIndex].messages[msgIndex].toolCall = toolRecord
                            }

                            // Clean up fallback tool call markers from content if needed
                            let content = self.conversations[targetConvIndex].messages[msgIndex].content
                            let cleaned = content.replacingOccurrences(
                                of: "```(?:tool_call|tool|json)\\s*\\n\\{[\\s\\S]*?\\}\\s*\\n```",
                                with: "",
                                options: .regularExpression
                            ).trimmingCharacters(in: .whitespacesAndNewlines)
                            self.conversations[targetConvIndex].messages[msgIndex].content = cleaned
                        }
                    },
                    onWorkingMemoryUpdate: { [weak self] memory in
                        guard let self = self else { return }
                        self.activeWorkingMemory = memory
                        if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
                           let msgIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == assistantMsgId }) {
                            self.conversations[targetConvIndex].messages[msgIndex].workingMemory = memory
                        }
                    },
                    onUsageUpdate: { [weak self] tokens in
                        guard let self = self else { return }
                        if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }) {
                            self.conversations[targetConvIndex].tokenCount = tokens
                        }
                    }
                )
            } catch {
                self.errorMessage = error.localizedDescription
                if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
                   let msgIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == assistantMsgId }) {
                    if self.conversations[targetConvIndex].messages[msgIndex].content.isEmpty {
                        self.conversations[targetConvIndex].messages[msgIndex].content = "Unable to connect to local model: \(error.localizedDescription)"
                    }
                }
            }

            // Clean working memory tags from final assistant content if any remained
            if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
               let msgIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == assistantMsgId }) {
                let currentContent = self.conversations[targetConvIndex].messages[msgIndex].content
                self.conversations[targetConvIndex].messages[msgIndex].content = LMStudioClient.cleanWorkingMemoryTags(from: currentContent)
                if self.conversations[targetConvIndex].messages[msgIndex].workingMemory == nil {
                    self.conversations[targetConvIndex].messages[msgIndex].workingMemory = self.activeWorkingMemory
                }
            }

            self.isGenerating = false
            if let start = self.turnStartTime,
               let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
               let lastAssistantIndex = self.conversations[targetConvIndex].messages.lastIndex(where: { $0.role == .assistant }) {
                let elapsed = Date().timeIntervalSince(start)
                self.conversations[targetConvIndex].messages[lastAssistantIndex].totalTurnDuration = elapsed
                ConversationStorageService.shared.saveConversation(self.conversations[targetConvIndex])
            } else if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }) {
                ConversationStorageService.shared.saveConversation(self.conversations[targetConvIndex])
            }
        }
    }

    /// User approves the tool call and saves it to be auto-approved in the future.
    func alwaysApproveToolCall(messageId: UUID, editedArgumentsJSON: String? = nil) {
        guard let convId = selectedConversationId,
              let convIndex = conversations.firstIndex(where: { $0.id == convId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId }),
              let tool = conversations[convIndex].messages[msgIndex].toolCall else {
            return
        }

        if tool.name == "run_terminal_command" {
            let args = tool.parsedArguments
            let cmd = (args["command"] as? String) ?? ""
            let analysis = ToolAutoApprovalManager.analyzeCommandSafety(cmd)
            for base in analysis.baseCommands {
                ToolAutoApprovalManager.addAutoApprovedCommand(base)
            }
        } else {
            ToolAutoApprovalManager.addAutoApprovedTool(tool.name)
        }
        approveToolCall(messageId: messageId, editedArgumentsJSON: editedArgumentsJSON)
    }

    /// User explicitly approves executing the specified tool call.
    func approveToolCall(messageId: UUID, editedArgumentsJSON: String? = nil, autoApproved: Bool = false) {
        guard let convId = selectedConversationId,
              let convIndex = conversations.firstIndex(where: { $0.id == convId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId }),
              var tool = conversations[convIndex].messages[msgIndex].toolCall else {
            return
        }

        if let newArgs = editedArgumentsJSON {
            tool.argumentsJSON = newArgs
        }

        tool.status = .running
        conversations[convIndex].messages[msgIndex].toolCall = tool
        isGenerating = true

        Task {
            let (stdout, stderr, exitCode, duration) = await ToolRegistry.shared.executeTool(
                name: tool.name,
                argumentsJSON: tool.argumentsJSON,
                workingDirectory: self.activeWorkingDirectory
            )

            tool.stdout = stdout
            tool.stderr = stderr
            tool.exitCode = exitCode
            tool.duration = duration
            tool.status = (exitCode == 0) ? .completed : .failed

            if let targetConv = self.conversations.firstIndex(where: { $0.id == convId }),
               let targetMsg = self.conversations[targetConv].messages.firstIndex(where: { $0.id == messageId }) {
                self.conversations[targetConv].messages[targetMsg].toolCall = tool

                // Append the tool result message into conversation history
                var resultText = stdout
                if !stderr.isEmpty {
                    if !resultText.isEmpty { resultText += "\n" }
                    resultText += stderr
                }
                if resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resultText = (exitCode == 0) ? "Command succeeded with no output." : "Command finished with exit code \(exitCode)."
                }

                let toolResultMsg = ChatMessage(
                    role: .tool,
                    content: resultText,
                    toolCall: tool,
                    toolCallId: tool.id
                )
                self.conversations[targetConv].messages.append(toolResultMsg)
                ConversationStorageService.shared.saveConversation(self.conversations[targetConv])

                // Auto-update activeWorkingMemory checklist when reading files completes
                if exitCode == 0, var memory = self.activeWorkingMemory {
                    if tool.name == "read_multiple_files" {
                        memory = memory.replacingOccurrences(of: "- [ ] Read all 5 files", with: "- [x] Read all 5 files (Completed)")
                        memory = memory.replacingOccurrences(of: "- [/] Read all 5 files", with: "- [x] Read all 5 files (Completed)")
                        memory = memory.replacingOccurrences(of: "- [ ] Read", with: "- [x] Read (Completed)")
                    } else if tool.name == "read_file" {
                        if let path = (tool.parsedArguments["path"] as? String) {
                            let fname = (path as NSString).lastPathComponent
                            memory = memory.replacingOccurrences(of: "- [ ] Read \(fname)", with: "- [x] Read \(fname) (Completed)")
                            memory = memory.replacingOccurrences(of: "- [/] Read \(fname)", with: "- [x] Read \(fname) (Completed)")
                        }
                    }
                    self.activeWorkingMemory = memory
                    self.conversations[targetConv].messages[targetMsg].workingMemory = memory
                }

                // Loop safety guard: limit continuous automated actions to 8
                self.turnActionCount += 1
                if self.turnActionCount >= 8 {
                    self.isGenerating = false
                    if let start = self.turnStartTime,
                       let lastAssistantIndex = self.conversations[targetConv].messages.lastIndex(where: { $0.role == .assistant }) {
                        self.conversations[targetConv].messages[lastAssistantIndex].totalTurnDuration = Date().timeIntervalSince(start)
                    }
                    let pausedMsg = ChatMessage(
                        role: .assistant,
                        content: "Paused after 8 actions to prevent an unnecessary loop or excessive token usage. Here is the current progress:\n\n\(self.activeWorkingMemory ?? "Tasks completed so far.")\n\nPlease let me know if you would like me to continue with the remaining items."
                    )
                    self.conversations[targetConv].messages.append(pausedMsg)
                    ConversationStorageService.shared.saveConversation(self.conversations[targetConv])
                    return
                }

                // Continue agent loop: model reads the result and produces final answer
                self.executeAssistantTurn(convId: convId)
            }
        }
    }

    /// User explicitly declines executing the specified tool call, optionally with feedback.
    func rejectToolCall(messageId: UUID, feedback: String? = nil) {
        guard let convId = selectedConversationId,
              let convIndex = conversations.firstIndex(where: { $0.id == convId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId }),
              var tool = conversations[convIndex].messages[msgIndex].toolCall else {
            return
        }

        tool.status = .rejected
        conversations[convIndex].messages[msgIndex].toolCall = tool

        let declineNote: String
        if let note = feedback?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            declineNote = "Execution of '\(tool.name)' was declined by user with note: \"\(note)\". Please adjust your plan accordingly."
        } else {
            declineNote = "Execution of '\(tool.name)' was declined by user. Please proceed without this tool."
        }

        let declineMsg = ChatMessage(
            role: .tool,
            content: declineNote,
            toolCallId: tool.id
        )
        conversations[convIndex].messages.append(declineMsg)
        ConversationStorageService.shared.saveConversation(conversations[convIndex])

        // Continue agent loop so the model can acknowledge and proceed
        executeAssistantTurn(convId: convId)
    }

    /// Allows the user to edit tool parameters directly before executing.
    func updateToolArguments(messageId: UUID, newArgumentsJSON: String) {
        guard let convId = selectedConversationId,
              let convIndex = conversations.firstIndex(where: { $0.id == convId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId }),
              var tool = conversations[convIndex].messages[msgIndex].toolCall else {
            return
        }

        tool.argumentsJSON = newArgumentsJSON
        conversations[convIndex].messages[msgIndex].toolCall = tool
        ConversationStorageService.shared.saveConversation(conversations[convIndex])
    }

    // MARK: - Slash Commands Execution

    func executeSlashCommand(_ input: String) {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init)
        guard let rawCommand = parts.first?.lowercased() else { return }
        let command = rawCommand.hasPrefix("/") ? String(rawCommand.dropFirst()) : rawCommand
        let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        guard let convId = selectedConversationId,
              let convIndex = conversations.firstIndex(where: { $0.id == convId }) else { return }

        switch command {
        case "compress", "compression":
            compressCurrentConversation(convId: convId, levelArgument: argument)

        case "think":
            if argument.isEmpty {
                isThinkingEnabled.toggle()
                let status = isThinkingEnabled ? "enabled (\(selectedPreset.rawValue) - \(Int(thinkingBudget)) tokens)" : "disabled"
                appendSystemNotification("Thinking / reasoning is now \(status).", convId: convId)
            } else {
                let lower = argument.lowercased()
                if lower == "off" || lower == "no" || lower == "disable" {
                    isThinkingEnabled = false
                    appendSystemNotification("Thinking / reasoning disabled.", convId: convId)
                } else if lower == "on" || lower == "enable" {
                    isThinkingEnabled = true
                    appendSystemNotification("Thinking enabled (\(selectedPreset.rawValue) - \(Int(thinkingBudget)) tokens).", convId: convId)
                } else if let preset = ThinkingPreset.allCases.first(where: { $0.rawValue.lowercased() == lower }) {
                    setThinkingPreset(preset)
                    appendSystemNotification("Thinking level set to \(preset.rawValue) (\(preset.defaultBudget) tokens).", convId: convId)
                } else if let budget = Double(lower), budget >= 256 && budget <= 8192 {
                    thinkingBudget = budget
                    isThinkingEnabled = true
                    appendSystemNotification("Thinking budget set to \(Int(budget)) tokens.", convId: convId)
                } else {
                    appendSystemNotification("Invalid think option '\(argument)'. Use: low, med, high, max, off, or a number (e.g. /think 2048)", convId: convId)
                }
            }

        case "dir":
            if argument.isEmpty {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.prompt = "Set Directory"
                if panel.runModal() == .OK, let url = panel.url {
                    activeWorkingDirectory = url.path
                    appendSystemNotification("Active working directory set to: `\(url.path)`", convId: convId)
                }
            } else {
                let expanded = (argument as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                    activeWorkingDirectory = (expanded as NSString).standardizingPath
                    appendSystemNotification("Active working directory set to: `\(activeWorkingDirectory)`", convId: convId)
                } else {
                    appendSystemNotification("Directory does not exist: `\(argument)`", convId: convId)
                }
            }

        case "model":
            if argument.isEmpty {
                let list = availableModels.map { model in
                    if model.isLoaded {
                        return "• `\(model.id)` *(Loaded in Memory)*"
                    } else {
                        return "• `\(model.id)` *(Available on Disk — `/model \(model.id)` to load)*"
                    }
                }.joined(separator: "\n")
                appendSystemNotification("Current Model: `\(selectedModel)`\n\nAvailable Models:\n\(list.isEmpty ? "• None detected" : list)", convId: convId)
            } else {
                let lowerArg = argument.lowercased()
                if let match = availableModels.first(where: { $0.id.lowercased().contains(lowerArg) }) {
                    if match.isLoaded && isConnected {
                        selectedModel = match.id
                        loadedModelId = match.id
                        appendSystemNotification("Switched to loaded model: `\(match.id)`", convId: convId)
                    } else {
                        activateModel(modelId: match.id, convIdForNotification: convId)
                    }
                } else {
                    activateModel(modelId: argument, convIdForNotification: convId)
                }
            }

        case "export":
            let md = exportConversationAsMarkdown(conversations[convIndex])
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(md, forType: .string)
            appendSystemNotification("Conversation exported! Formatted Markdown has been copied to your clipboard.", convId: convId)

        case "instructions":
            showInstructionsDocument(convId: convId)

        case "playbooks":
            showPlaybooksDocument(playbookQuery: argument, convId: convId)

        default:
            appendSystemNotification("Unknown command `/\(command)`. Type `/` in the prompt box to view available commands.", convId: convId)
        }
    }

    /// Opens ~/.jarvis/instructions.md in the native in-app rendered markdown viewer
    func showInstructionsDocument(convId: UUID? = nil) {
        let customDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".jarvis")
        let customFile = customDir.appendingPathComponent("instructions.md")

        if !FileManager.default.fileExists(atPath: customFile.path) {
            try? FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
            let defaultContent = AgentPromptManager.shared.loadInstructionsContent()
            try? defaultContent.write(to: customFile, atomically: true, encoding: .utf8)
        }

        let content = AgentPromptManager.shared.loadInstructionsContent()
        activeDocumentViewer = DocumentViewerState(
            title: "instructions.md",
            filePath: "~/.jarvis/instructions.md",
            content: content,
            isPlaybookCollection: false,
            selectedPlaybookId: nil,
            playbooksList: []
        )
        if let id = convId {
            appendSystemNotification("Opened `instructions.md` in the Jarvis in-app document viewer.", convId: id)
        }
    }

    /// Opens playbooks in the native in-app rendered markdown viewer
    func showPlaybooksDocument(playbookQuery: String = "", convId: UUID? = nil) {
        PlaybookService.shared.ensurePlaybooksExist()
        let playbooks = PlaybookService.shared.listPlaybooks()

        let cleanQuery = playbookQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanQuery.isEmpty, let match = PlaybookService.shared.findPlaybook(matching: cleanQuery) {
            activeDocumentViewer = DocumentViewerState(
                title: "Playbook: \(match.info.title)",
                filePath: match.info.path,
                content: match.content,
                isPlaybookCollection: true,
                selectedPlaybookId: match.info.id,
                playbooksList: playbooks
            )
            if let id = convId {
                appendSystemNotification("Opened `\(match.info.id)` in the Jarvis in-app document viewer.", convId: id)
            }
        } else {
            let firstContent: String
            if let first = playbooks.first, let c = PlaybookService.shared.loadPlaybookContent(info: first) {
                firstContent = c
            } else {
                firstContent = "# Playbooks\n\nBrowse specialized playbooks using the tabs above."
            }
            activeDocumentViewer = DocumentViewerState(
                title: "Playbooks Collection",
                filePath: "~/.jarvis/playbooks",
                content: firstContent,
                isPlaybookCollection: true,
                selectedPlaybookId: playbooks.first?.id,
                playbooksList: playbooks
            )
            if let id = convId {
                appendSystemNotification("Opened `~/.jarvis/playbooks/` in the Jarvis in-app document viewer.", convId: id)
            }
        }
    }

    func compressCurrentConversation(convId: UUID, levelArgument: String = "") {
        guard let convIndex = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let msgsToCompress = activeContextMessages(for: conversations[convIndex])

        guard msgsToCompress.count >= 2 else {
            appendSystemNotification("Not enough conversation history to compress yet. Add a few messages first.", convId: convId)
            return
        }

        let level: CompressionLevel
        let cleanArg = levelArgument.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanArg.isEmpty || cleanArg == "med" || cleanArg == "medium" {
            level = .med
        } else if cleanArg == "low" || cleanArg == "light" || cleanArg == "soft" {
            level = .low
        } else if cleanArg == "high" || cleanArg == "max" || cleanArg == "hard" {
            level = .high
        } else {
            level = .med
            appendSystemNotification("Unknown compression level '\(cleanArg)'. Defaulting to 'med' (options: low, med, high).", convId: convId)
        }

        // Calculate accurate pre-compression tokens from active context
        let totalCharsBefore = msgsToCompress.reduce(0) { sum, msg in
            sum + msg.content.count + (msg.reasoningContent?.count ?? 0)
        }
        let tokensBefore = max(1, Int(Double(totalCharsBefore) / 3.8))

        isGenerating = true
        let progressMsgId = UUID()
        let progressMsg = ChatMessage(
            id: progressMsgId,
            role: .assistant,
            content: "Compressing conversation context (\(level.rawValue.capitalized) level) into an AI memory snapshot..."
        )
        conversations[convIndex].messages.append(progressMsg)

        var maxToolOutputChars = 1500
        switch level {
        case .low: maxToolOutputChars = 3000
        case .med: maxToolOutputChars = 1500
        case .high: maxToolOutputChars = 500
        }

        var conversationText = ""
        for msg in msgsToCompress {
            switch msg.role {
            case .user:
                conversationText += "User: \(msg.content)\n\n"
            case .assistant:
                if msg.isCompressionBoundary == true, let snap = msg.compressedSnapshot {
                    conversationText += "[Previous Context Snapshot]:\n\(snap)\n\n"
                } else if !msg.content.isEmpty {
                    conversationText += "Assistant: \(msg.content)\n\n"
                }
                if let tool = msg.toolCall {
                    conversationText += "[Tool: \(tool.name) with args \(tool.argumentsJSON)]\n"
                    if let out = tool.stdout, !out.isEmpty {
                        conversationText += "[Tool Output: \(out.prefix(maxToolOutputChars))]\n\n"
                    }
                }
            case .tool:
                conversationText += "[Tool Result: \(msg.content.prefix(maxToolOutputChars))]\n\n"
            }
        }

        let compressionInstruction: String
        switch level {
        case .low:
            compressionInstruction = """
            Create a DETAILED, HIGH-FIDELITY memory snapshot of the conversation (aiming for ~50% retention):
            - PRESERVE extensive technical detail: verbatim user requests, constraints, exact file paths, complete code snippets, function names, specific tool arguments, outputs, error messages, and intermediate debugging steps.
            - KEEP all architectural decisions, configurations, and active work context in full detail.
            - ONLY OMIT: pure conversational pleasantries, duplicate log lines, and repetitive noise.
            - FORMAT:
              ### 1. User Goals, Requirements & Constraints (In-depth)
              ### 2. Architecture & Technical Environment (Settings, directories, active models)
              ### 3. Comprehensive Actions & File Changes (Exact file paths, code diffs/snippets, commands run and specific outcomes)
              ### 4. Current State & Pending Tasks (Immediate next steps with complete context)
            """
        case .med:
            compressionInstruction = """
            Create a BALANCED memory snapshot of the conversation (aiming for ~75-80% token reduction):
            - PRESERVE all core user requests, requirements, and constraints.
            - DOCUMENT all modified/created files, terminal commands executed, and their outcomes.
            - SUMMARIZE key technical decisions, designs, and troubleshooting steps clearly.
            - OMIT conversational pleasantries, excessive tool trial-and-error logs, and verbose command dumps.
            - FORMAT:
              ### 1. User Goals & Directives
              ### 2. Technical Decisions & Working Environment
              ### 3. Completed Actions & Code Changes (Files, commands, results)
              ### 4. Current State & Next Steps
            """
        case .high:
            compressionInstruction = """
            Create an ULTRA-COMPACT executive memory snapshot of the conversation (aiming for ~90-95% token reduction):
            - Distill the conversation into high-level essentials: Goals, Major Decisions, Final Results, and Next Step.
            - Be extremely concise. Omit all minor details, intermediate attempts, and outputs.
            - FORMAT:
              ### 1. Goals
              ### 2. Decisions
              ### 3. Outcomes
              ### 4. Next Step
            """
        }

        let compressionMessages: [ChatMessage] = [
            ChatMessage(
                role: .user,
                content: """
                \(compressionInstruction)

                ---
                Conversation to compress:
                \(conversationText)
                """
            )
        ]

        activeGenerationTask = Task {
            var accumulatedSnapshot = ""
            do {
                try await LMStudioClient.shared.streamChat(
                    messages: compressionMessages,
                    model: self.selectedModel,
                    workingDirectory: self.activeWorkingDirectory,
                    isThinkingEnabled: false,
                    thinkingBudget: 0,
                    onReasoningDelta: { _ in },
                    onContentDelta: { delta in
                        accumulatedSnapshot += delta
                    },
                    onToolCallDetected: { _ in }
                )

                let finalSnapshot = accumulatedSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
                let tokensAfter = max(1, Int(Double(finalSnapshot.count) / 3.8))
                let percentSaved = max(1, min(99, Int(round((Double(tokensBefore - tokensAfter) / Double(tokensBefore)) * 100.0))))

                if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
                   let pIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == progressMsgId }) {

                    let boundaryMsg = ChatMessage(
                        id: progressMsgId,
                        role: .assistant,
                        content: "",
                        isCompressionBoundary: true,
                        compressedSnapshot: finalSnapshot.isEmpty ? "Prior conversation compressed into memory snapshot." : finalSnapshot,
                        compressionSavingsPercent: percentSaved,
                        compressionLevel: level.rawValue,
                        tokensBeforeCompression: tokensBefore,
                        tokensAfterCompression: tokensAfter
                    )
                    self.conversations[targetConvIndex].messages[pIndex] = boundaryMsg
                    self.conversations[targetConvIndex].updatedAt = Date()
                    self.conversations[targetConvIndex].tokenCount = nil
                    ConversationStorageService.shared.saveConversation(self.conversations[targetConvIndex])
                }
            } catch {
                if let targetConvIndex = self.conversations.firstIndex(where: { $0.id == convId }),
                   let pIndex = self.conversations[targetConvIndex].messages.firstIndex(where: { $0.id == progressMsgId }) {
                    self.conversations[targetConvIndex].messages[pIndex].content = "Failed to compress context: \(error.localizedDescription)"
                }
            }
            self.isGenerating = false
        }
    }

    private func appendSystemNotification(_ text: String, convId: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let msg = ChatMessage(role: .assistant, content: text)
        conversations[index].messages.append(msg)
        conversations[index].updatedAt = Date()
        ConversationStorageService.shared.saveConversation(conversations[index])
    }

    private func exportConversationAsMarkdown(_ conv: ChatConversation) -> String {
        var lines: [String] = ["# \(conv.title)", "", "_Exported from Jarvis on \(ISO8601DateFormatter().string(from: Date()))_", ""]
        for msg in conv.messages {
            switch msg.role {
            case .user:
                lines.append("### User")
                lines.append(msg.content)
                lines.append("")
            case .assistant:
                if msg.isCompressionBoundary == true, let snapshot = msg.compressedSnapshot {
                    lines.append("---")
                    lines.append("### [Context Compressed Anchor]")
                    lines.append("```")
                    lines.append(snapshot)
                    lines.append("```")
                    lines.append("---")
                    lines.append("")
                } else {
                    lines.append("### Jarvis")
                    if let reasoning = msg.reasoningContent, !reasoning.isEmpty {
                        lines.append("> **Thought Process:**\n> " + reasoning.replacingOccurrences(of: "\n", with: "\n> "))
                        lines.append("")
                    }
                    if let tool = msg.toolCall {
                        lines.append("`Tool: \(tool.name)` (\(tool.status.rawValue))")
                        lines.append("```json\n\(tool.argumentsJSON)\n```")
                        if let out = tool.stdout, !out.isEmpty {
                            lines.append("```\n\(out)\n```")
                        }
                    }
                    if !msg.content.isEmpty {
                        lines.append(msg.content)
                    }
                    lines.append("")
                }
            case .tool:
                lines.append("> _Tool Result:_")
                lines.append("```\n\(msg.content)\n```")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
