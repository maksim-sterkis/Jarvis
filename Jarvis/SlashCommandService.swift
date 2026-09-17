//
//  SlashCommandService.swift
//  Jarvis
//

import Foundation
import AppKit

enum SlashCommandCategory: String, CaseIterable {
    case context = "Context"
    case model = "Model"
    case session = "Session"
    case tools = "Tools"
    case help = "Help"
}

struct SlashCommand: Identifiable, Equatable {
    let name: String
    let syntax: String
    let description: String
    let icon: String
    let category: SlashCommandCategory
    var id: String { name }
}

final class SlashCommandService {
    static let shared = SlashCommandService()

    private init() {}

    let availableCommands: [SlashCommand] = [
        SlashCommand(
            name: "compress",
            syntax: "/compress [low|med|high]",
            description: "Condenses prior chat into AI memory snapshot (defaults to med; preserves visual history)",
            icon: "arrow.triangle.2.circlepath",
            category: .context
        ),
        SlashCommand(
            name: "compression",
            syntax: "/compression [low|med|high]",
            description: "Alias for /compress [low|med|high] (defaults to med)",
            icon: "arrow.triangle.2.circlepath",
            category: .context
        ),
        SlashCommand(
            name: "clear",
            syntax: "/clear",
            description: "Clears all messages in the current conversation",
            icon: "trash",
            category: .session
        ),
        SlashCommand(
            name: "think",
            syntax: "/think [low|med|high|max|off]",
            description: "Quickly set reasoning budget or toggle thinking off",
            icon: "brain",
            category: .model
        ),
        SlashCommand(
            name: "dir",
            syntax: "/dir [path]",
            description: "Set active working directory for tools (or opens folder picker)",
            icon: "folder",
            category: .tools
        ),
        SlashCommand(
            name: "model",
            syntax: "/model [name]",
            description: "Switch to a specific local model or list loaded models",
            icon: "cpu",
            category: .model
        ),
        SlashCommand(
            name: "export",
            syntax: "/export",
            description: "Copy full conversation formatted as Markdown to clipboard",
            icon: "square.and.arrow.up",
            category: .session
        ),
        SlashCommand(
            name: "instructions",
            syntax: "/instructions",
            description: "Open ~/.jarvis/instructions.md in default editor",
            icon: "doc.text",
            category: .tools
        ),
        SlashCommand(
            name: "help",
            syntax: "/help",
            description: "Display reference list of all available slash commands",
            icon: "questionmark.circle",
            category: .help
        )
    ]

    /// Filters commands matching user typing query e.g. "/com" or "com"
    func matchingCommands(for input: String) -> [SlashCommand] {
        guard input.hasPrefix("/") else { return [] }
        let query = String(input.dropFirst()).lowercased().trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return availableCommands
        }
        return availableCommands.filter {
            $0.name.lowercased().hasPrefix(query) || $0.syntax.lowercased().contains(query)
        }
    }
}
