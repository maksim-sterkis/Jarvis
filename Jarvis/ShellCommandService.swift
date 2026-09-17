//
//  ShellCommandService.swift
//  Jarvis
//

import Foundation

struct ShellExecutionResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let duration: TimeInterval
    let isTimedOut: Bool

    var combinedOutput: String {
        var output = ""
        if !stdout.isEmpty {
            output += stdout
        }
        if !stderr.isEmpty {
            if !output.isEmpty && !output.hasSuffix("\n") {
                output += "\n"
            }
            output += "[stderr]\n" + stderr
        }
        if isTimedOut {
            if !output.isEmpty && !output.hasSuffix("\n") {
                output += "\n"
            }
            output += "[Process timed out after reaching timeout limit]"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class ShellCommandService {
    static let shared = ShellCommandService()

    private init() {}

    /// Executes a command string in /bin/zsh
    func execute(
        command: String,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30.0
    ) async -> ShellExecutionResult {
        let startTime = Date()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")

                // -l for login shell, -c to pass command string
                process.arguments = ["-l", "-c", command]

                // Set working directory
                let resolvedCwd: String
                if let cwd = workingDirectory, !cwd.isEmpty {
                    resolvedCwd = (cwd as NSString).expandingTildeInPath
                } else {
                    resolvedCwd = NSHomeDirectory()
                }

                if FileManager.default.fileExists(atPath: resolvedCwd) {
                    process.currentDirectoryURL = URL(fileURLWithPath: resolvedCwd)
                } else {
                    process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
                }

                // Ensure standard macOS dev paths exist in PATH
                var environment = ProcessInfo.processInfo.environment
                let extraPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                if let currentPath = environment["PATH"] {
                    environment["PATH"] = "\(extraPaths):\(currentPath)"
                } else {
                    environment["PATH"] = extraPaths
                }
                environment["LANG"] = "en_US.UTF-8"
                environment["LC_ALL"] = "en_US.UTF-8"
                process.environment = environment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var timedOut = false
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning {
                        timedOut = true
                        process.terminate()
                    }
                }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

                    let duration = Date().timeIntervalSince(startTime)
                    let result = ShellExecutionResult(
                        exitCode: process.terminationStatus,
                        stdout: stdoutString,
                        stderr: stderrString,
                        duration: duration,
                        isTimedOut: timedOut
                    )
                    continuation.resume(returning: result)
                } catch {
                    timer.cancel()
                    let duration = Date().timeIntervalSince(startTime)
                    let result = ShellExecutionResult(
                        exitCode: -1,
                        stdout: "",
                        stderr: "Failed to launch process: \(error.localizedDescription)",
                        duration: duration,
                        isTimedOut: false
                    )
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
