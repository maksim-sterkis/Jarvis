//
//  LMStudioClient.swift
//  Jarvis
//

import Foundation

struct LMModelInfo: Identifiable, Equatable, Codable {
    let id: String
    let isLoaded: Bool
    let contextLength: Int?
}

struct LMModelV0Response: Codable {
    struct ModelData: Codable {
        let id: String
        let state: String?
        let type: String?
        let max_context_length: Int?
        let loaded_context_length: Int?
    }
    let data: [ModelData]
}

struct LMModelListResponse: Codable {
    let data: [LMModelItem]
}

struct LMModelItem: Codable {
    let id: String
}

struct LMStreamChunk: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let content: String?
            let reasoning_content: String?
            let tool_calls: [LMToolCallDelta]?
        }
        let delta: Delta?
        let finish_reason: String?
    }
    struct Usage: Codable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
    let choices: [Choice]?
    let usage: Usage?
}

struct LMToolCallDelta: Codable {
    let index: Int?
    let id: String?
    let type: String?
    let function: LMFunctionDelta?
}

struct LMFunctionDelta: Codable {
    let name: String?
    let arguments: String?
}

enum LMClientError: LocalizedError {
    case serverUnavailable
    case invalidResponse
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .serverUnavailable:
            return "Could not connect to LM Studio at http://127.0.0.1:1234. Make sure LM Studio is running with local server enabled."
        case .invalidResponse:
            return "Invalid response received from local server."
        case .streamError(let message):
            return message
        }
    }
}

final class LMStudioClient {
    static let shared = LMStudioClient()
    var baseURL = URL(string: "http://127.0.0.1:1234/v1")!

    private init() {}

    func fetchModels() async throws -> [LMModelInfo] {
        // First try LM Studio's native v0 API which reports loaded states
        let v0Url = URL(string: "http://127.0.0.1:1234/api/v0/models")!
        var v0Req = URLRequest(url: v0Url)
        v0Req.timeoutInterval = 3

        if let (data, response) = try? await URLSession.shared.data(for: v0Req),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let v0List = try? JSONDecoder().decode(LMModelV0Response.self, from: data) {
            let filtered = v0List.data.filter { $0.type != "embeddings" }
            return filtered.map {
                let ctx = $0.loaded_context_length ?? $0.max_context_length
                return LMModelInfo(id: $0.id, isLoaded: $0.state == "loaded", contextLength: ctx)
            }
        }

        // Fallback to OpenAI-compatible /v1/models
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw LMClientError.invalidResponse
            }
            let list = try JSONDecoder().decode(LMModelListResponse.self, from: data)
            return list.data.map { LMModelInfo(id: $0.id, isLoaded: false, contextLength: nil) }
        } catch {
            throw LMClientError.serverUnavailable
        }
    }

    func streamChat(
        messages: [ChatMessage],
        model: String,
        workingDirectory: String = NSHomeDirectory(),
        isThinkingEnabled: Bool,
        thinkingBudget: Int,
        workingMemory: String? = nil,
        onReasoningDelta: @escaping (String) -> Void,
        onContentDelta: @escaping (String) -> Void,
        onToolCallDetected: @escaping (ToolCallRecord) -> Void,
        onWorkingMemoryUpdate: ((String) -> Void)? = nil,
        onUsageUpdate: ((Int) -> Void)? = nil
    ) async throws {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let systemPrompt = AgentPromptManager.shared.buildSystemPrompt(
            workingDirectory: workingDirectory,
            thinkingBudget: isThinkingEnabled ? thinkingBudget : nil,
            workingMemory: workingMemory
        )

        var apiMessages: [[String: Any]] = [
            [
                "role": "system",
                "content": systemPrompt
            ]
        ]

        for (index, msg) in messages.enumerated() {
            if msg.role == .tool {
                // Check if the preceding tool call was a fallback markdown block
                let isFallbackTool = messages.prefix(index).last(where: { $0.role == .assistant && $0.toolCall != nil })?.toolCall?.isFallback == true

                let toolName = msg.toolCall?.name ?? (messages.prefix(index).last(where: { $0.role == .assistant && $0.toolCall != nil })?.toolCall?.name ?? "tool")
                let systemDirective = """

[System Directive: Tool '\(toolName)' executed successfully. Review the output above:
- If this tool provided the requested file contents or directory listing: STOP invoking tools now. You already have the data in context. Synthesize and write your final comprehensive answer to the user immediately.
- NEVER call the same tool with identical arguments again.
- If pending files from your locked target list still remain to be inspected: invoke the next tool call now. Keep intermediate reasoning brief (~60-120 tokens).]
"""

                if isFallbackTool {
                    // For models using markdown fallback, send tool result as user observation
                    apiMessages.append([
                        "role": "user",
                        "content": "[Tool Output for \(toolName)]:\n\(msg.content)\n\(systemDirective)"
                    ])
                } else {
                    // Standard native OpenAI tool call result
                    apiMessages.append([
                        "role": "tool",
                        "tool_call_id": msg.toolCallId ?? (msg.toolCall?.id ?? "call_default"),
                        "content": "\(msg.content)\n\(systemDirective)"
                    ])
                }
                continue
            }

            var assistantDict: [String: Any] = [
                "role": msg.role.rawValue,
                "content": msg.content
            ]

            if msg.role == .assistant, let tool = msg.toolCall {
                if tool.isFallback == true {
                    // Embed fallback block in content so non-function-calling models see their prior output
                    let fallbackBlock = "```tool_call\n{\n  \"name\": \"\(tool.name)\",\n  \"arguments\": \(tool.argumentsJSON)\n}\n```"
                    let existingContent = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    assistantDict["content"] = existingContent.isEmpty ? fallbackBlock : "\(existingContent)\n\n\(fallbackBlock)"
                } else {
                    assistantDict["tool_calls"] = [
                        [
                            "id": tool.id,
                            "type": "function",
                            "function": [
                                "name": tool.name,
                                "arguments": tool.argumentsJSON
                            ]
                        ]
                    ]
                }
            }

            if index == messages.count - 1 && msg.role == .user {
                var content = msg.content
                if isThinkingEnabled {
                    content += "\n\n[Reasoning Budget: ~\(thinkingBudget) tokens. Reason before output or tool calls.]"
                } else {
                    content += "\n\n[Answer directly without internal reasoning or thinking tags.]"
                }
                assistantDict["content"] = content
            }

            apiMessages.append(assistantDict)
        }

        var bodyPayload: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "tools": ToolRegistry.shared.openAIToolDefinitions,
            "parallel_tool_calls": false,
            "stream": true,
            "temperature": 0.4
        ]

        if isThinkingEnabled {
            // LM Studio's reasoning parameter validator strictly expects 'on' or 'off'
            bodyPayload["reasoning"] = "on"
            bodyPayload["reasoning_budget"] = thinkingBudget
            bodyPayload["thinking"] = [
                "type": "enabled",
                "budget_tokens": thinkingBudget
            ]
        } else {
            bodyPayload["reasoning"] = "off"
            bodyPayload["reasoning_effort"] = "none"
            bodyPayload["reasoning_budget"] = 0
            bodyPayload["thinking"] = [
                "type": "disabled"
            ]
            bodyPayload["chat_template_kwargs"] = [
                "thinking": false
            ]
        }

        bodyPayload["stream_options"] = [
            "include_usage": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            if let data = errorBody.data(using: .utf8),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw LMClientError.streamError("Server error (\((response as? HTTPURLResponse)?.statusCode ?? 400)): \(msg)")
            }
            throw LMClientError.invalidResponse
        }

        struct AccumulatedTool {
            var id: String = ""
            var name: String = ""
            var args: String = ""
        }
        var accumulatedTools: [Int: AccumulatedTool] = [:]
        var accumulatedContent: String = ""
        var accumulatedReasoning: String = ""
        var inThinkTag = false

        for try await line in bytes.lines {
            if Task.isCancelled {
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonString = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)

            if jsonString == "[DONE]" {
                break
            }

            guard let data = jsonString.data(using: .utf8) else { continue }

            if let chunk = try? JSONDecoder().decode(LMStreamChunk.self, from: data) {
                if let usage = chunk.usage, let total = usage.total_tokens {
                    await MainActor.run {
                        onUsageUpdate?(total)
                    }
                }

                if let firstChoice = chunk.choices?.first,
                   let delta = firstChoice.delta {

                    // Only deliver reasoning delta if thinking is actually enabled
                    if isThinkingEnabled, let reasoning = delta.reasoning_content, !reasoning.isEmpty {
                        accumulatedReasoning += reasoning
                        await MainActor.run {
                            onReasoningDelta(reasoning)
                        }
                    }

                    if let content = delta.content, !content.isEmpty {
                        var textToEmit = content

                        // Filter out any inline <think>...</think> blocks if thinking is disabled
                        if !isThinkingEnabled {
                            if textToEmit.contains("<think>") {
                                inThinkTag = true
                            }
                            if inThinkTag {
                                if let endRange = textToEmit.range(of: "</think>") {
                                    inThinkTag = false
                                    textToEmit = String(textToEmit[endRange.upperBound...])
                                } else {
                                    textToEmit = ""
                                }
                            }
                        }

                        if !textToEmit.isEmpty {
                            accumulatedContent += textToEmit
                            await MainActor.run {
                                onContentDelta(textToEmit)
                            }
                        }
                    }

                    if let toolDeltas = delta.tool_calls {
                        for td in toolDeltas {
                            let idx = td.index ?? 0
                            var current = accumulatedTools[idx] ?? AccumulatedTool()
                            if let id = td.id, !id.isEmpty {
                                current.id = id
                            }
                            if let fn = td.function {
                                if let name = fn.name, !name.isEmpty {
                                    current.name += name
                                }
                                if let args = fn.arguments, !args.isEmpty {
                                    current.args += args
                                }
                            }
                            accumulatedTools[idx] = current
                        }
                    }
                }
            }
        }

        // Extract working memory if present in accumulated content or reasoning
        if let memory = LMStudioClient.extractWorkingMemory(from: accumulatedContent) ?? LMStudioClient.extractWorkingMemory(from: accumulatedReasoning) {
            await MainActor.run {
                onWorkingMemoryUpdate?(memory)
            }
        }

        // Handle tool calls once stream ends
        if let firstTool = accumulatedTools.sorted(by: { $0.key < $1.key }).first?.value,
           !firstTool.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let finalId = firstTool.id.isEmpty ? UUID().uuidString : firstTool.id
            let cleanArgs = firstTool.args.trimmingCharacters(in: .whitespacesAndNewlines)
            let toolRecord = ToolCallRecord(
                id: finalId,
                name: firstTool.name.trimmingCharacters(in: .whitespacesAndNewlines),
                argumentsJSON: cleanArgs.isEmpty ? "{}" : cleanArgs,
                status: .pendingApproval,
                isFallback: false
            )
            await MainActor.run {
                onToolCallDetected(toolRecord)
            }
        } else if let fallback = ToolRegistry.shared.parseFallbackToolCall(from: accumulatedContent) {
            let toolRecord = ToolCallRecord(
                id: UUID().uuidString,
                name: fallback.name,
                argumentsJSON: fallback.argumentsJSON,
                status: .pendingApproval,
                isFallback: true
            )
            await MainActor.run {
                onToolCallDetected(toolRecord)
            }
        }
    }

    /// Extracts working memory text enclosed within <working_memory> tags or markdown task checklists
    static func extractWorkingMemory(from text: String) -> String? {
        // 1. Explicit XML tags
        if let start = text.range(of: "<working_memory>"),
           let end = text.range(of: "</working_memory>", range: start.upperBound..<text.endIndex) {
            let memory = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !memory.isEmpty { return memory }
        }

        // 2. Markdown task checklist block: e.g. "Task: ... Locked Target Files: ... Status: ... - [x] ..."
        let patterns = [
            #"(?:Task:[^\n]+\n(?:Locked )?Target Files:[^\n]+\n(?:Status|Progress):[\s\S]*?(?=(?:\n\s*\n\s*\n|\n---\n|\n#|$)))"#,
            #"(?:\*\*(?:Working Memory|Current Status Check|Task Checklist)[^\n]*\*\*[\s\S]*?(?=(?:\n\s*\n\s*\n|\n---\n|\n#|$)))"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = text as NSString
                if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                    let extracted = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                    if (extracted.contains("- [") || extracted.contains("* [") || extracted.contains("Target Files:")) && extracted.count > 25 {
                        return extracted
                    }
                }
            }
        }

        return nil
    }

    /// Strips <working_memory>...</working_memory> blocks from user-visible message content
    static func cleanWorkingMemoryTags(from text: String) -> String {
        return text.replacingOccurrences(
            of: "<working_memory>[\\s\\S]*?</working_memory>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
