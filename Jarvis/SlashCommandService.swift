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
}

struct SlashCommand: Identifiable, Equatable {
    let name: String
    let syntax: String
    let description: String
    let icon: String
    let category: SlashCommandCategory
    var id: String { name }
}

struct CommandSuggestion: Identifiable, Equatable {
    let id: String
    let displayText: String
    let syntax: String?
    let subtitle: String?
    let badge: String?
    let icon: String
    let completionText: String
    let isExecutable: Bool
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
            description: "Switch to, boot server, and load local model into memory",
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
            description: "View and inspect ~/.jarvis/instructions.md in-app",
            icon: "doc.text",
            category: .tools
        ),
        SlashCommand(
            name: "playbooks",
            syntax: "/playbooks [name]",
            description: "View and inspect playbooks in-app (e.g. /playbooks coding_and_testing)",
            icon: "book.pages",
            category: .tools
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

    /// Provides dynamic contextual suggestions for root commands, subcommands, and arguments.
    func suggestions(for input: String, availableModels: [String] = []) -> [CommandSuggestion] {
        guard input.hasPrefix("/") else { return [] }

        // Scenario 1: User is typing root command without a space (e.g. "/", "/p", "/play")
        if !input.contains(" ") {
            let query = String(input.dropFirst()).lowercased().trimmingCharacters(in: .whitespaces)
            let matches = query.isEmpty ? availableCommands : availableCommands.filter {
                $0.name.lowercased().hasPrefix(query) || $0.syntax.lowercased().contains(query)
            }

            return matches.map { cmd in
                let hasArgs = cmd.syntax.contains("[")
                return CommandSuggestion(
                    id: cmd.id,
                    displayText: "/" + cmd.name,
                    syntax: cmd.syntax,
                    subtitle: cmd.description,
                    badge: cmd.category.rawValue,
                    icon: cmd.icon,
                    completionText: hasArgs ? "/" + cmd.name + " " : "/" + cmd.name,
                    isExecutable: !hasArgs || cmd.name == "playbooks" || cmd.name == "compress" || cmd.name == "think" || cmd.name == "model"
                )
            }
        }

        // Scenario 2: User has typed a command followed by space (e.g. "/playbooks ", "/compress ", "/think ")
        let components = input.components(separatedBy: " ")
        let rawCmd = components.first ?? ""
        let cmdName = (rawCmd.hasPrefix("/") ? String(rawCmd.dropFirst()) : rawCmd).lowercased()
        let argQuery = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces).lowercased()

        switch cmdName {
        case "playbooks":
            let allPlaybooks = PlaybookService.shared.listPlaybooks()
            let filtered = argQuery.isEmpty ? allPlaybooks : allPlaybooks.filter {
                $0.id.lowercased().contains(argQuery) ||
                $0.title.lowercased().contains(argQuery)
            }

            return filtered.map { pb in
                let cleanName = pb.id.replacingOccurrences(of: ".md", with: "")
                return CommandSuggestion(
                    id: "playbook-\(pb.id)",
                    displayText: cleanName,
                    syntax: "/playbooks \(cleanName)",
                    subtitle: pb.summary,
                    badge: "Playbook",
                    icon: "book.pages",
                    completionText: "/playbooks \(cleanName)",
                    isExecutable: true
                )
            }

        case "compress", "compression":
            let levels: [(id: String, title: String, desc: String)] = [
                ("low", "Low", "Light summarization, preserves high conversational detail"),
                ("med", "Medium", "Balanced snapshot, ideal for standard multi-turn workflows"),
                ("high", "High", "Maximum compression, extracts key facts and decisions only")
            ]
            let filtered = argQuery.isEmpty ? levels : levels.filter {
                $0.id.lowercased().hasPrefix(argQuery) || $0.title.lowercased().hasPrefix(argQuery)
            }

            return filtered.map { item in
                CommandSuggestion(
                    id: "compress-\(item.id)",
                    displayText: item.id,
                    syntax: "/compress \(item.id)",
                    subtitle: item.desc,
                    badge: "Level",
                    icon: "arrow.triangle.2.circlepath",
                    completionText: "/compress \(item.id)",
                    isExecutable: true
                )
            }

        case "think":
            let presets: [(id: String, title: String, desc: String, icon: String)] = [
                ("low", "Low", "~1,024 tokens reasoning budget", "brain"),
                ("med", "Medium", "~2,048 tokens reasoning budget", "brain"),
                ("high", "High", "~4,096 tokens reasoning budget", "brain"),
                ("max", "Max", "~8,192 tokens reasoning budget (deep reasoning)", "brain.head.profile"),
                ("off", "Off", "Disable reasoning completely (direct immediate responses)", "brain.slash")
            ]
            let filtered = argQuery.isEmpty ? presets : presets.filter {
                $0.id.lowercased().hasPrefix(argQuery) || $0.title.lowercased().hasPrefix(argQuery)
            }

            return filtered.map { item in
                CommandSuggestion(
                    id: "think-\(item.id)",
                    displayText: item.id,
                    syntax: "/think \(item.id)",
                    subtitle: item.desc,
                    badge: "Preset",
                    icon: item.icon,
                    completionText: "/think \(item.id)",
                    isExecutable: true
                )
            }

        case "model":
            let filtered = argQuery.isEmpty ? availableModels : availableModels.filter {
                $0.lowercased().contains(argQuery)
            }

            return filtered.map { modelId in
                CommandSuggestion(
                    id: "model-\(modelId)",
                    displayText: modelId,
                    syntax: "/model \(modelId)",
                    subtitle: "Switch to and load \(modelId) into memory",
                    badge: "Model",
                    icon: "cpu",
                    completionText: "/model \(modelId)",
                    isExecutable: true
                )
            }

        case "dir":
            let dirOptions: [(id: String, text: String, desc: String, icon: String)] = [
                ("~", "~", "Set active directory to user home (~)", "house"),
                ("pick", "Browse...", "Open folder selection panel", "folder.badge.plus")
            ]
            let filtered = argQuery.isEmpty ? dirOptions : dirOptions.filter {
                $0.id.lowercased().contains(argQuery) || $0.text.lowercased().contains(argQuery)
            }

            return filtered.map { opt in
                CommandSuggestion(
                    id: "dir-\(opt.id)",
                    displayText: opt.text,
                    syntax: opt.id == "pick" ? "/dir" : "/dir \(opt.id)",
                    subtitle: opt.desc,
                    badge: "Directory",
                    icon: opt.icon,
                    completionText: opt.id == "pick" ? "/dir" : "/dir \(opt.id)",
                    isExecutable: true
                )
            }

        default:
            return []
        }
    }
}

