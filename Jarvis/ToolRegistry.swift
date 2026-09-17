//
//  ToolRegistry.swift
//  Jarvis
//

import Foundation

enum ToolCallStatus: String, Codable {
    case pendingApproval = "pending_approval"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case rejected = "rejected"
}

struct ToolCallRecord: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    var argumentsJSON: String
    var status: ToolCallStatus
    var stdout: String?
    var stderr: String?
    var exitCode: Int32?
    var duration: TimeInterval?
    var isFallback: Bool?

    init(
        id: String = UUID().uuidString,
        name: String,
        argumentsJSON: String,
        status: ToolCallStatus = .pendingApproval,
        stdout: String? = nil,
        stderr: String? = nil,
        exitCode: Int32? = nil,
        duration: TimeInterval? = nil,
        isFallback: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.duration = duration
        self.isFallback = isFallback
    }

    var parsedArguments: [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    var displaySummary: String {
        let args = parsedArguments
        switch name {
        case "run_terminal_command":
            return args["command"] as? String ?? argumentsJSON
        case "write_file":
            let path = args["path"] as? String ?? "file"
            return "Write to \(path)"
        case "read_file":
            if let paths = args["paths"] as? [String], !paths.isEmpty {
                return "Read \(paths.count) files"
            }
            let path = args["path"] as? String ?? "file"
            return "Read \(path)"
        case "read_multiple_files":
            let paths = args["paths"] as? [String] ?? []
            if paths.isEmpty {
                return "Read multiple files"
            }
            return "Read \(paths.count) files (\(paths.prefix(2).joined(separator: ", "))\(paths.count > 2 ? ", ..." : ""))"
        case "create_directory":
            let path = args["path"] as? String ?? "directory"
            return "Create folder \(path)"
        case "list_directory":
            let path = args["path"] as? String ?? "."
            return "List contents of \(path)"
        default:
            return "\(name): \(argumentsJSON)"
        }
    }
}

final class ToolRegistry {
    static let shared = ToolRegistry()

    private init() {}

    /// Returns OpenAI compatible tool schemas
    var openAIToolDefinitions: [[String: Any]] {
        return [
            [
                "type": "function",
                "function": [
                    "name": "run_terminal_command",
                    "description": "Execute a shell command via /bin/zsh on macOS. Captures stdout, stderr, and exit code. Requires explicit user approval in the UI.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "command": [
                                "type": "string",
                                "description": "The shell command to run (e.g. 'ls -la', 'git status', 'python3 script.py')"
                            ],
                            "working_directory": [
                                "type": "string",
                                "description": "Optional working directory path (defaults to current active directory)"
                            ]
                        ],
                        "required": ["command"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "read_file",
                    "description": "Read the text contents of a file on macOS.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Path to the file to read (supports ~ expansion)"
                            ],
                            "max_bytes": [
                                "type": "integer",
                                "description": "Maximum bytes to read (default: 102400)"
                            ]
                        ],
                        "required": ["path"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "read_multiple_files",
                    "description": "Read the text contents of multiple files in a single call. Much faster than reading files one-by-one. ALWAYS prefer this tool when inspecting 2 or more files.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "paths": [
                                "type": "array",
                                "items": [
                                    "type": "string"
                                ],
                                "description": "Array of file paths to read (e.g. ['SettingsView.swift', 'LMStudioClient.swift']). Supports ~ expansion and relative paths."
                            ],
                            "max_bytes_per_file": [
                                "type": "integer",
                                "description": "Maximum bytes to read per file (default: 12288)"
                            ]
                        ],
                        "required": ["paths"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "write_file",
                    "description": "Write text content to a file. Automatically creates intermediate folders if needed.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Destination file path (supports ~ expansion)"
                            ],
                            "content": [
                                "type": "string",
                                "description": "Text content to write into the file"
                            ],
                            "overwrite": [
                                "type": "boolean",
                                "description": "Whether to overwrite existing file (default: true)"
                            ]
                        ],
                        "required": ["path", "content"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "create_directory",
                    "description": "Create a new directory and any intermediate folders on macOS.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Folder path to create"
                            ]
                        ],
                        "required": ["path"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_directory",
                    "description": "List files, folders, and sizes in a directory.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "Path to directory to list"
                            ]
                        ],
                        "required": ["path"]
                    ]
                ]
            ]
        ]
    }

    /// Dispatches tool execution to the appropriate service
    func executeTool(
        name: String,
        argumentsJSON: String,
        workingDirectory: String
    ) async -> (stdout: String, stderr: String, exitCode: Int32, duration: TimeInterval) {
        let startTime = Date()

        guard let data = argumentsJSON.data(using: .utf8),
              let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ("", "Invalid JSON arguments: \(argumentsJSON)", 1, 0)
        }

        switch name {
        case "run_terminal_command":
            guard let command = args["command"] as? String else {
                return ("", "Missing 'command' argument", 1, 0)
            }
            let cwd = (args["working_directory"] as? String) ?? workingDirectory
            let result = await ShellCommandService.shared.execute(
                command: command,
                workingDirectory: cwd
            )
            return (result.stdout, result.stderr, result.exitCode, result.duration)

        case "read_file":
            if let paths = args["paths"] as? [String], !paths.isEmpty {
                let maxBytes = args["max_bytes_per_file"] as? Int ?? (args["max_bytes"] as? Int ?? 51200)
                let content = FileSystemService.shared.readMultipleFiles(
                    paths: paths,
                    baseDirectory: workingDirectory,
                    maxBytesPerFile: maxBytes
                )
                let duration = Date().timeIntervalSince(startTime)
                return (content, "", 0, duration)
            }
            guard let path = args["path"] as? String else {
                return ("", "Missing 'path' argument", 1, 0)
            }
            let maxBytes = args["max_bytes"] as? Int ?? 102400
            do {
                let content = try FileSystemService.shared.readFile(
                    path: path,
                    baseDirectory: workingDirectory,
                    maxBytes: maxBytes
                )
                let duration = Date().timeIntervalSince(startTime)
                return (content, "", 0, duration)
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                return ("", error.localizedDescription, 1, duration)
            }

        case "read_multiple_files":
            let paths: [String]
            if let pList = args["paths"] as? [String] {
                paths = pList
            } else if let single = args["path"] as? String {
                paths = [single]
            } else {
                return ("", "Missing 'paths' argument (expected array of file paths)", 1, 0)
            }
            let maxBytes = args["max_bytes_per_file"] as? Int ?? (args["max_bytes"] as? Int ?? 12288)
            let content = FileSystemService.shared.readMultipleFiles(
                paths: paths,
                baseDirectory: workingDirectory,
                maxBytesPerFile: maxBytes
            )
            let duration = Date().timeIntervalSince(startTime)
            return (content, "", 0, duration)

        case "write_file":
            guard let path = args["path"] as? String else {
                return ("", "Missing 'path' argument", 1, 0)
            }
            guard let content = args["content"] as? String else {
                return ("", "Missing 'content' argument", 1, 0)
            }
            let overwrite = args["overwrite"] as? Bool ?? true
            do {
                let message = try FileSystemService.shared.writeFile(
                    path: path,
                    content: content,
                    overwrite: overwrite,
                    baseDirectory: workingDirectory
                )
                let duration = Date().timeIntervalSince(startTime)
                return (message, "", 0, duration)
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                return ("", error.localizedDescription, 1, duration)
            }

        case "create_directory":
            guard let path = args["path"] as? String else {
                return ("", "Missing 'path' argument", 1, 0)
            }
            do {
                let message = try FileSystemService.shared.createDirectory(
                    path: path,
                    baseDirectory: workingDirectory
                )
                let duration = Date().timeIntervalSince(startTime)
                return (message, "", 0, duration)
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                return ("", error.localizedDescription, 1, duration)
            }

        case "list_directory":
            let path = (args["path"] as? String) ?? "."
            do {
                let listing = try FileSystemService.shared.listDirectory(
                    path: path,
                    baseDirectory: workingDirectory
                )
                let duration = Date().timeIntervalSince(startTime)
                return (listing, "", 0, duration)
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                return ("", error.localizedDescription, 1, duration)
            }

        default:
            return ("", "Unknown tool: \(name)", 1, 0)
        }
    }

    /// Fallback parser for extracting tool calls if emitted as markdown code blocks:
    /// ```tool_call
    /// { "name": "...", "arguments": { ... } }
    /// ```
    func parseFallbackToolCall(from text: String) -> (name: String, argumentsJSON: String)? {
        let pattern = "```(?:tool_call|tool|json)\\s*\\n(\\{[\\s\\S]*?\\})\\s*\\n```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in results {
            guard match.numberOfRanges > 1 else { continue }
            let jsonString = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = jsonString.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = obj["name"] as? String else {
                continue
            }

            let argsJSON: String
            if let argsDict = obj["arguments"] as? [String: Any],
               let argsData = try? JSONSerialization.data(withJSONObject: argsDict),
               let str = String(data: argsData, encoding: .utf8) {
                argsJSON = str
            } else if let argsStr = obj["arguments"] as? String {
                argsJSON = argsStr
            } else {
                argsJSON = "{}"
            }

            return (name, argsJSON)
        }
        return nil
    }
}
