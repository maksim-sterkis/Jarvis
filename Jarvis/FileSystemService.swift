//
//  FileSystemService.swift
//  Jarvis
//

import Foundation

struct FileItemInfo: Codable {
    let name: String
    let isDirectory: Bool
    let sizeBytes: Int64
    let modifiedDate: String
}

final class FileSystemService {
    static let shared = FileSystemService()

    private init() {}

    /// Resolves ~ and relative paths against the provided base directory, with smart subfolder resolution.
    func resolvePath(_ path: String, baseDirectory: String? = nil) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return (expanded as NSString).standardizingPath
        }

        let base: String
        if let baseDir = baseDirectory, !baseDir.isEmpty {
            base = (baseDir as NSString).expandingTildeInPath
        } else {
            base = NSHomeDirectory()
        }

        let candidate = ((base as NSString).appendingPathComponent(expanded) as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        // Smart fallback: check if file exists in project subfolders (e.g. Jarvis/Jarvis/filename or Jarvis/filename)
        let filename = (expanded as NSString).lastPathComponent
        let commonSubpaths = [
            "Jarvis/Jarvis/\(expanded)",
            "Jarvis/\(expanded)",
            "Jarvis/Jarvis/\(filename)",
            "Jarvis/\(filename)"
        ]
        for sub in commonSubpaths {
            let subCandidate = ((base as NSString).appendingPathComponent(sub) as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: subCandidate) {
                return subCandidate
            }
        }

        return candidate
    }

    /// Reads a file from disk up to maxBytes (default 100KB).
    func readFile(path: String, baseDirectory: String? = nil, maxBytes: Int = 102400) throws -> String {
        let fullPath = resolvePath(path, baseDirectory: baseDirectory)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: fullPath) else {
            throw NSError(domain: "FileSystemService", code: 404, userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(path)"])
        }

        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
            throw NSError(domain: "FileSystemService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Path is a directory, not a file: \(path). Use list_directory instead."])
        }

        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: fullPath))
        defer { try? fileHandle.close() }

        let data = fileHandle.readData(ofLength: maxBytes)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "FileSystemService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Could not decode file as UTF-8 text."])
        }

        return content
    }

    /// Reads multiple files in a single call, returning formatted output with clear demarcations.
    func readMultipleFiles(paths: [String], baseDirectory: String? = nil, maxBytesPerFile: Int = 12288) -> String {
        guard !paths.isEmpty else {
            return "No file paths provided to read."
        }

        var results: [String] = []
        for (index, path) in paths.enumerated() {
            let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanPath.isEmpty else { continue }
            do {
                let fullPath = resolvePath(cleanPath, baseDirectory: baseDirectory)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.size] as? NSNumber)?.intValue ?? 0
                let content = try readFile(path: cleanPath, baseDirectory: baseDirectory, maxBytes: maxBytesPerFile)
                var section = "=== File \(index + 1)/\(paths.count): \(cleanPath) ===\n\(content)"
                if fileSize > maxBytesPerFile {
                    section += "\n\n[... Truncated for summary brevity. Showing first \(maxBytesPerFile) bytes of \(fileSize) total bytes ...]"
                }
                results.append(section)
            } catch {
                results.append("=== File \(index + 1)/\(paths.count): \(cleanPath) (Error) ===\n\(error.localizedDescription)")
            }
        }

        return results.joined(separator: "\n\n")
    }

    /// Writes content to a file, creating parent directories if needed.
    func writeFile(path: String, content: String, overwrite: Bool = true, baseDirectory: String? = nil) throws -> String {
        let fullPath = resolvePath(path, baseDirectory: baseDirectory)
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: fullPath)

        if fileManager.fileExists(atPath: fullPath) && !overwrite {
            throw NSError(domain: "FileSystemService", code: 409, userInfo: [NSLocalizedDescriptionKey: "File already exists and overwrite is set to false: \(path)"])
        }

        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        guard let data = content.data(using: .utf8) else {
            throw NSError(domain: "FileSystemService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Failed to encode string content as UTF-8."])
        }

        try data.write(to: url, options: .atomic)
        return "Successfully wrote \(data.count) bytes to \(fullPath)"
    }

    /// Creates a directory and intermediate parent folders.
    func createDirectory(path: String, baseDirectory: String? = nil) throws -> String {
        let fullPath = resolvePath(path, baseDirectory: baseDirectory)
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: fullPath)

        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
            if isDir.boolValue {
                return "Directory already exists: \(fullPath)"
            } else {
                throw NSError(domain: "FileSystemService", code: 409, userInfo: [NSLocalizedDescriptionKey: "A file with this name already exists: \(fullPath)"])
            }
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return "Successfully created directory: \(fullPath)"
    }

    /// Lists files and subdirectories within a directory.
    func listDirectory(path: String, baseDirectory: String? = nil) throws -> String {
        let fullPath = resolvePath(path, baseDirectory: baseDirectory)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: fullPath) else {
            throw NSError(domain: "FileSystemService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Directory does not exist: \(path)"])
        }

        let contents = try fileManager.contentsOfDirectory(atPath: fullPath)
        let formatter = ISO8601DateFormatter()

        var items: [FileItemInfo] = []
        for name in contents.sorted() {
            guard !name.hasPrefix(".") || name == ".gitignore" || name == ".env" else { continue }
            let itemPath = (fullPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)

            let attributes = (try? fileManager.attributesOfItem(atPath: itemPath)) ?? [:]
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = (attributes[.modificationDate] as? Date) ?? Date()

            items.append(FileItemInfo(
                name: name,
                isDirectory: isDir.boolValue,
                sizeBytes: size,
                modifiedDate: formatter.string(from: modDate)
            ))
        }

        if items.isEmpty {
            return "Directory is empty: \(fullPath)"
        }

        var lines = ["Directory contents of \(fullPath) (\(items.count) items):"]
        for item in items {
            let typeIndicator = item.isDirectory ? "[DIR] " : "      "
            let sizeString = item.isDirectory ? "" : " (\(item.sizeBytes) bytes)"
            lines.append("\(typeIndicator) \(item.name)\(sizeString)")
        }

        return lines.joined(separator: "\n")
    }
}
