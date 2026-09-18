//
//  LMStudioService.swift
//  Jarvis
//

import Foundation
import AppKit
import Combine

enum LMServerState: Equatable {
    case offline
    case startingServer
    case loadingModel(name: String, progress: Double)
    case ready
    case error(String)
}

final class LMStudioService: ObservableObject {
    static let shared = LMStudioService()

    @Published var serverState: LMServerState = .offline
    @Published var loadProgress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var isModelLoading: Bool = false
    @Published var isShuttingDown: Bool = false
    @Published var didJarvisLaunchServer: Bool = false

    private init() {}

    /// Returns the absolute path to the `lms` CLI tool on macOS.
    var lmsPath: String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.lmstudio/bin/lms",
            "/usr/local/bin/lms",
            "\(home)/.cache/lm-studio/bin/lms",
            "/opt/homebrew/bin/lms"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Checks if the local LM Studio server is responding on port 1234.
    func isServerRunning() async -> Bool {
        let url = URL(string: "http://127.0.0.1:1234/api/v0/models")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5

        if let (_, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            return true
        }

        // Fallback check on standard /v1/models
        let v1Url = URL(string: "http://127.0.0.1:1234/v1/models")!
        var v1Req = URLRequest(url: v1Url)
        v1Req.timeoutInterval = 1.5

        if let (_, response) = try? await URLSession.shared.data(for: v1Req),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            return true
        }

        return false
    }

    /// Caches the known model list in UserDefaults for instant startup retrieval.
    func saveCachedModels(_ models: [LMModelInfo]) {
        guard !models.isEmpty else { return }
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: "cachedLMModels")
        }
    }

    /// Discovers local models without invoking `lms` CLI, ensuring LM Studio is NEVER woken up or launched.
    func scanDiskModelsWithoutCLI() -> [LMModelInfo] {
        // 1. Check cached models in UserDefaults
        if let data = UserDefaults.standard.data(forKey: "cachedLMModels"),
           let cached = try? JSONDecoder().decode([LMModelInfo].self, from: data),
           !cached.isEmpty {
            return cached
        }

        // 2. Scan ~/.lmstudio/hub/models and ~/.lmstudio/models directly using FileManager
        var found: [LMModelInfo] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let searchDirs = [
            "\(home)/.lmstudio/hub/models",
            "\(home)/.lmstudio/models",
            "\(home)/.cache/lm-studio/models"
        ]

        for baseDir in searchDirs where fm.fileExists(atPath: baseDir) {
            guard let publishers = try? fm.contentsOfDirectory(atPath: baseDir) else { continue }
            for pub in publishers where !pub.hasPrefix(".") {
                let pubPath = "\(baseDir)/\(pub)"
                guard let modelDirs = try? fm.contentsOfDirectory(atPath: pubPath) else { continue }
                for modelName in modelDirs where !modelName.hasPrefix(".") {
                    let modelKey = "\(pub)/\(modelName)"
                    if !found.contains(where: { $0.id == modelKey }) {
                        found.append(LMModelInfo(id: modelKey, isLoaded: false, contextLength: nil))
                    }
                }
            }
        }

        if !found.isEmpty {
            saveCachedModels(found)
            return found
        }

        // 3. Fallback known defaults
        let defaults = [
            LMModelInfo(id: "google/gemma-4-e2b", isLoaded: false, contextLength: 131072),
            LMModelInfo(id: "google/gemma-4-12b", isLoaded: false, contextLength: 262144),
            LMModelInfo(id: "mradermacher/Qwen2.5-14B-Instruct-abliterated-v2-GGUF", isLoaded: false, contextLength: 32768)
        ]
        saveCachedModels(defaults)
        return defaults
    }

    /// Discovers local models. Never invokes `lms ls` when offline so LM Studio is never woken up.
    func listDiskModels() async -> [LMModelInfo] {
        return scanDiskModelsWithoutCLI()
    }

    /// Discovers all models currently loaded in memory via `lms ps --json`.
    func listLoadedModels() async -> [LMModelInfo] {
        guard let lms = lmsPath else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: lms)
                process.arguments = ["ps", "--json"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    guard let rawString = String(data: data, encoding: .utf8),
                          let jsonStart = rawString.range(of: "["),
                          let jsonEnd = rawString.range(of: "]", options: .backwards) else {
                        continuation.resume(returning: [])
                        return
                    }

                    let cleanJson = String(rawString[jsonStart.lowerBound...jsonEnd.upperBound])
                    guard let jsonData = cleanJson.data(using: .utf8),
                          let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                        continuation.resume(returning: [])
                        return
                    }

                    let models: [LMModelInfo] = array.compactMap { item in
                        guard let id = (item["identifier"] as? String) ?? (item["modelKey"] as? String) else {
                            return nil
                        }
                        let ctx = (item["contextLength"] as? Int) ?? (item["maxContextLength"] as? Int)
                        return LMModelInfo(id: id, isLoaded: true, contextLength: ctx)
                    }

                    continuation.resume(returning: models)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Unloads a specific model from memory.
    func unloadModel(modelKey: String) async {
        guard let lms = lmsPath else { return }
        _ = try? await runCLI(executable: lms, arguments: ["unload", modelKey])
    }

    /// Boots the local LM Studio server.
    func startServer(mode: String = "headless") async throws {
        guard !isShuttingDown else { return }

        // If server is already running, return
        if await isServerRunning() {
            return
        }

        await MainActor.run {
            self.didJarvisLaunchServer = true
        }

        await MainActor.run {
            self.serverState = .startingServer
            self.statusMessage = "Starting LM Studio local server..."
            self.loadProgress = 0.1
        }

        if mode == "app" {
            // Launch the desktop GUI app
            let appURL = URL(fileURLWithPath: "/Applications/LM Studio.app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } else if let lms = lmsPath {
                try await runCLI(executable: lms, arguments: ["server", "start"])
            }
        } else {
            // Fast headless daemon via lms CLI
            guard let lms = lmsPath else {
                throw NSError(domain: "LMStudioService", code: 404, userInfo: [NSLocalizedDescriptionKey: "lms CLI tool not found. Please ensure LM Studio is installed."])
            }
            try await runCLI(executable: lms, arguments: ["server", "start"])
        }

        // Wait for server to become responsive
        var attempts = 0
        while attempts < 25 {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
            if await isServerRunning() {
                // Allow internal worker threads (system resources observer, llm worker) to complete startup handshake
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run {
                    self.loadProgress = 0.3
                    self.statusMessage = "Server connected on port 1234."
                }
                return
            }
            attempts += 1
        }

        throw NSError(domain: "LMStudioService", code: 408, userInfo: [NSLocalizedDescriptionKey: "Server start timed out after 15 seconds."])
    }

    /// Loads a model into unified memory with real-time percentage progress updates and automatic daemon recovery.
    func loadModel(
        modelKey: String,
        onProgress: @escaping (Double, String) -> Void
    ) async throws {
        guard !isShuttingDown else { return }

        await MainActor.run {
            self.isModelLoading = true
            self.serverState = .loadingModel(name: modelKey, progress: 0.0)
            self.statusMessage = "Loading \(modelKey)..."
            self.loadProgress = 0.0
            onProgress(0.0, "Initiating model load: \(modelKey)")
        }

        do {
            _ = try await executeLoadProcess(modelKey: modelKey, onProgress: onProgress)
            await MainActor.run {
                self.loadProgress = 1.0
                self.serverState = .ready
                self.isModelLoading = false
                onProgress(1.0, "Ready")
            }
        } catch {
            guard !isShuttingDown else { return }
            let errorText = error.localizedDescription
            // Detect LM Studio daemon resource observer crash / zombie worker error
            let isObserverCrash = errorText.contains("observer shutdown requested") ||
                                  errorText.contains("system resources observer") ||
                                  errorText.contains("Attempt to pull a snapshot of system resources failed")

            if isObserverCrash && !isShuttingDown {
                await MainActor.run {
                    self.statusMessage = "LM Studio daemon worker initializing..."
                    self.loadProgress = 0.15
                    onProgress(0.15, "Recovering LM Studio daemon workers...")
                }

                // Recover daemon by restarting server
                if let lms = lmsPath, !isShuttingDown {
                    _ = try? await runCLI(executable: lms, arguments: ["server", "start"])
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s recovery wait
                }

                // Retry load once
                do {
                    _ = try await executeLoadProcess(modelKey: modelKey, onProgress: onProgress)
                    await MainActor.run {
                        self.loadProgress = 1.0
                        self.serverState = .ready
                        self.isModelLoading = false
                        onProgress(1.0, "Ready")
                    }
                    return
                } catch {
                    // Fallthrough to report final error
                }
            }

            await MainActor.run {
                self.isModelLoading = false
                self.serverState = .error(error.localizedDescription)
            }
            throw error
        }
    }

    /// Executes the `lms load` CLI process and captures accumulated text for progress and error diagnosing.
    private func executeLoadProcess(
        modelKey: String,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String {
        guard let lms = lmsPath else {
            throw NSError(domain: "LMStudioService", code: 404, userInfo: [NSLocalizedDescriptionKey: "lms CLI not found."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: lms)
                // Use default optimal offload ratio determined by LM Studio for Apple Silicon.
                // Avoid forcing `--gpu max` which can fail guardrails when memory is tight.
                process.arguments = ["load", modelKey, "-y"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                var accumulatedText = ""
                let lock = NSLock()

                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

                    lock.lock()
                    accumulatedText += text
                    lock.unlock()

                    // Parse percentage patterns like "45%"
                    if let regex = try? NSRegularExpression(pattern: #"(\d{1,3})%"#) {
                        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
                        if let lastMatch = matches.last,
                           let range = Range(lastMatch.range(at: 1), in: text),
                           let percent = Double(text[range]) {
                            let progress = min(1.0, max(0.0, percent / 100.0))
                            DispatchQueue.main.async {
                                self.loadProgress = progress
                                let msg = "Loading \(modelKey)..."
                                self.statusMessage = msg
                                self.serverState = .loadingModel(name: modelKey, progress: progress)
                                onProgress(progress, msg)
                            }
                        }
                    }

                    if text.contains("Model loaded successfully") || text.contains("loaded successfully") {
                        DispatchQueue.main.async {
                            self.loadProgress = 1.0
                            let msg = "Model loaded successfully!"
                            self.statusMessage = msg
                            self.serverState = .ready
                            onProgress(1.0, msg)
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    handle.readabilityHandler = nil

                    lock.lock()
                    let finalOutput = accumulatedText
                    lock.unlock()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: finalOutput)
                    } else {
                        let cleanErr = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let msg = cleanErr.isEmpty ? "Process exited with code \(process.terminationStatus)" : cleanErr
                        let err = NSError(domain: "LMStudioService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
                        continuation.resume(throwing: err)
                    }
                } catch {
                    handle.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Stops the local LM Studio server if running.
    func stopServer() async throws {
        guard let lms = lmsPath else { return }
        try await runCLI(executable: lms, arguments: ["server", "stop"])
        await MainActor.run {
            self.serverState = .offline
            self.statusMessage = "Server stopped."
        }
    }

    /// Executes a quick CLI command and returns its output.
    @discardableResult
    private func runCLI(executable: String, arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let err = NSError(domain: "LMStudioService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Process exited with code \(process.terminationStatus)" : output])
                        continuation.resume(throwing: err)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Instantly and unconditionally kills LM Studio and its background processes using SIGKILL.
    /// Runs in ~40ms and prevents Electron crashpad or service helpers from restarting the application.
    func killLMStudioImmediately() {
        isShuttingDown = true
        let script = """
        killall -9 "LM Studio" 2>/dev/null
        /usr/bin/pkill -9 -f "LM Studio" 2>/dev/null
        /usr/bin/pkill -9 -f "lmlink-connector" 2>/dev/null
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        process.waitUntilExit()
    }

    /// Shuts down the LM Studio server non-blockingly during application quit.
    func stopServerDetached() {
        killLMStudioImmediately()
    }

    /// Backward-compatible quit cleanup that delegates to non-blocking detached stop.
    func cleanupOnQuitSync() {
        killLMStudioImmediately()
    }
}
