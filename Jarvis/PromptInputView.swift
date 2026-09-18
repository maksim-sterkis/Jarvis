//
//  PromptInputView.swift
//  Jarvis
//

import SwiftUI

struct PromptInputView: View {
    @Binding var text: String
    var isGenerating: Bool
    var contextUsed: Int = 0
    var contextTotal: Int = 8192
    var isFocused: FocusState<Bool>.Binding
    var onSend: () -> Void
    var onStop: () -> Void

    @State private var hoveredCommandId: String? = nil
    @State private var selectedCommandIndex: Int = 0
    @State private var isMenuDismissed: Bool = false
    @State private var lastLoadedCommand: String? = nil
    @AppStorage("autoScrollSlashMenuOnHover") private var autoScrollSlashMenuOnHover: Bool = false

    private var isSlashCommandActive: Bool {
        text.hasPrefix("/") && !text.contains(" ") && isFocused.wrappedValue && !isMenuDismissed
    }

    private var matchingCommands: [SlashCommand] {
        SlashCommandService.shared.matchingCommands(for: text)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Floating Slash Command Autocomplete Card
            if isSlashCommandActive && !matchingCommands.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "command")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text("Commands")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("↑↓ Navigate • ⇥ Tab to choose")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                        Button(action: {
                            isMenuDismissed = true
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss suggestions (Esc)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                    Divider().opacity(0.3)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 2) {
                                ForEach(Array(matchingCommands.enumerated()), id: \.element.id) { index, cmd in
                                    let isSelected = (index == selectedCommandIndex)
                                    Button(action: {
                                        selectedCommandIndex = index
                                        loadCommandIntoPrompt(cmd)
                                    }) {
                                        HStack(spacing: 10) {
                                            Image(systemName: cmd.icon)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(isSelected ? .white : .accentColor)
                                                .frame(width: 22, height: 22)
                                                .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                                                .cornerRadius(5)

                                            VStack(alignment: .leading, spacing: 1) {
                                                HStack(spacing: 6) {
                                                    Text(cmd.syntax)
                                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                        .foregroundColor(.primary)

                                                    Text(cmd.category.rawValue)
                                                        .font(.system(size: 9, weight: .medium))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                                                        .foregroundColor(isSelected ? .primary : .secondary)
                                                        .cornerRadius(3)
                                                }

                                                Text(cmd.description)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(isSelected ? .primary.opacity(0.85) : .secondary)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            if isSelected {
                                                Text("⇥ Tab")
                                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(.accentColor)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.accentColor.opacity(0.12))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.accentColor.opacity(0.15) : (hoveredCommandId == cmd.id ? Color.secondary.opacity(0.08) : Color.clear))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                                        )
                                        .cornerRadius(8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(cmd.id)
                                    .onHover { hovering in
                                        if hovering {
                                            hoveredCommandId = cmd.id
                                            if autoScrollSlashMenuOnHover {
                                                selectedCommandIndex = index
                                            }
                                        } else if hoveredCommandId == cmd.id {
                                            hoveredCommandId = nil
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: 210)
                        .onChange(of: selectedCommandIndex) { newIndex in
                            if newIndex >= 0 && newIndex < matchingCommands.count {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    proxy.scrollTo(matchingCommands[newIndex].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 3)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Attachment / Plus icon (ChatGPT style)
                Button(action: {
                    // Attachment action placeholder
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("Add attachment or tool")

                // Text input area
                TextField("Message Jarvis... (or type / for commands)", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused(isFocused)
                    .onKeyPress(.downArrow) {
                        if isSlashCommandActive && !matchingCommands.isEmpty {
                            selectedCommandIndex = (selectedCommandIndex + 1) % matchingCommands.count
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if isSlashCommandActive && !matchingCommands.isEmpty {
                            selectedCommandIndex = (selectedCommandIndex - 1 + matchingCommands.count) % matchingCommands.count
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.tab) {
                        if isSlashCommandActive && !matchingCommands.isEmpty {
                            let safeIndex = min(max(0, selectedCommandIndex), matchingCommands.count - 1)
                            loadCommandIntoPrompt(matchingCommands[safeIndex])
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if isSlashCommandActive {
                            isMenuDismissed = true
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.return) {
                        if isSlashCommandActive && !matchingCommands.isEmpty {
                            let safeIndex = min(max(0, selectedCommandIndex), matchingCommands.count - 1)
                            let selected = matchingCommands[safeIndex]
                            if selected.syntax.contains("[") {
                                loadCommandIntoPrompt(selected)
                            } else {
                                text = "/" + selected.name
                                lastLoadedCommand = "/" + selected.name
                                isMenuDismissed = true
                                onSend()
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    .onSubmit {
                        if !isGenerating {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                if isSlashCommandActive && !matchingCommands.isEmpty {
                                    let safeIndex = min(max(0, selectedCommandIndex), matchingCommands.count - 1)
                                    let selected = matchingCommands[safeIndex]
                                    if selected.syntax.contains("[") {
                                        loadCommandIntoPrompt(selected)
                                    } else {
                                        text = "/" + selected.name
                                        lastLoadedCommand = "/" + selected.name
                                        isMenuDismissed = true
                                        onSend()
                                    }
                                } else {
                                    onSend()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)

                // Send or Stop button
                Button(action: {
                    if isGenerating {
                        onStop()
                    } else {
                        onSend()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(isGenerating || canSend ? Color.primary : Color.secondary.opacity(0.2))
                            .frame(width: 32, height: 32)

                        if isGenerating {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(nsColor: .windowBackgroundColor))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(canSend ? Color(nsColor: .windowBackgroundColor) : .secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .disabled(!canSend && !isGenerating)
                .keyboardShortcut(.return, modifiers: [.command])
                .help(isGenerating ? "Stop generating" : "Send message (⌘⏎)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onTapGesture {
                        if !isFocused.wrappedValue {
                            isFocused.wrappedValue = true
                        } else {
                            isFocused.wrappedValue = false
                            DispatchQueue.main.async {
                                isFocused.wrappedValue = true
                            }
                        }
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isFocused.wrappedValue ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 1.2)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)

            // Footer Bar: Disclaimer & Context Usage Meter
            HStack(alignment: .center) {
                Text("Jarvis runs locally on your Mac.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10))

                    Text(contextUsageLabel)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(contextUsageColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(5)
                .help("Context Window: \(formatNumber(contextUsed)) tokens used out of \(formatNumber(contextTotal)) max allowed (\(String(format: "%.1f", contextPercentage))%)")
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onAppear {
            DispatchQueue.main.async {
                isFocused.wrappedValue = true
            }
        }
        .onChange(of: text) { newText in
            if newText != lastLoadedCommand {
                isMenuDismissed = false
                selectedCommandIndex = 0
            }
        }
        .onChange(of: matchingCommands.count) { count in
            if count > 0 {
                selectedCommandIndex = min(selectedCommandIndex, count - 1)
            } else {
                selectedCommandIndex = 0
            }
        }
    }

    private func loadCommandIntoPrompt(_ cmd: SlashCommand) {
        let newPromptText: String
        if cmd.syntax.contains("[") {
            newPromptText = "/" + cmd.name + " "
        } else {
            newPromptText = "/" + cmd.name
        }
        text = newPromptText
        lastLoadedCommand = newPromptText
        isMenuDismissed = true
        if !isFocused.wrappedValue {
            isFocused.wrappedValue = true
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var contextPercentage: Double {
        guard contextTotal > 0 else { return 0 }
        return min(100.0, (Double(contextUsed) / Double(contextTotal)) * 100.0)
    }

    private var contextUsageLabel: String {
        let usedStr = formatTokens(contextUsed)
        let totalStr = formatTokens(contextTotal)
        let pct = String(format: "%.1f%%", contextPercentage)
        return "\(usedStr) / \(totalStr) tokens (\(pct))"
    }

    private var contextUsageColor: Color {
        if contextPercentage > 85 {
            return .red
        } else if contextPercentage > 70 {
            return .orange
        } else {
            return .secondary
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return k >= 10 ? String(format: "%.0fk", k) : String(format: "%.1fk", k)
        }
        return "\(count)"
    }

    private func formatNumber(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
