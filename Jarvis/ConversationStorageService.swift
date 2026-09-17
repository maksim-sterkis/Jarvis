//
//  ConversationStorageService.swift
//  Jarvis
//

import Foundation

final class ConversationStorageService {
    static let shared = ConversationStorageService()

    private let storageDirectory: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageDirectory = appSupport.appendingPathComponent("Jarvis/conversations", isDirectory: true)

        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    private var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .prettyPrinted
        return enc
    }

    private var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    /// Saves a single conversation to disk. Empty conversations with no messages are skipped.
    func saveConversation(_ conversation: ChatConversation) {
        guard !conversation.messages.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async {
            let fileURL = self.storageDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
            do {
                let data = try self.encoder.encode(conversation)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("Failed to save conversation \(conversation.id): \(error.localizedDescription)")
            }
        }
    }

    /// Loads all saved conversations from disk, sorted by updatedAt descending.
    func loadAllConversations() -> [ChatConversation] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var loaded: [ChatConversation] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let conversation = try? decoder.decode(ChatConversation.self, from: data) {
                loaded.append(conversation)
            }
        }

        return loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Deletes a conversation's JSON file from disk.
    func deleteConversation(id: UUID) {
        DispatchQueue.global(qos: .utility).async {
            let fileURL = self.storageDirectory.appendingPathComponent("\(id.uuidString).json")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
