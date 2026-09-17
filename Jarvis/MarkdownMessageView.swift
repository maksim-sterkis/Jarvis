//
//  MarkdownMessageView.swift
//  Jarvis
//

import SwiftUI
import AppKit

enum MarkdownBlockType {
    case heading(Int)
    case paragraph
    case code(String)
}

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let type: MarkdownBlockType
    let text: String
}

struct MarkdownMessageView: View {
    let content: String

    var body: some View {
        let blocks = parseBlocks(from: content)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.type {
                case .heading(let level):
                    Text(LocalizedStringKey(block.text.trimmingCharacters(in: .whitespaces)))
                        .font(level == 1 ? .system(size: 18, weight: .bold) : (level == 2 ? .system(size: 16, weight: .bold) : .system(size: 14, weight: .semibold)))
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                        .textSelection(.enabled)

                case .paragraph:
                    Text(LocalizedStringKey(block.text))
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                case .code(let language):
                    CodeBlockView(language: language, code: block.text)
                }
            }
        }
    }

    private func parseBlocks(from markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var currentCodeLanguage = ""
        var currentCodeLines: [String] = []
        var currentTextLines: [String] = []

        func flushCurrentText() {
            guard !currentTextLines.isEmpty else { return }
            let combined = currentTextLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty {
                if combined.hasPrefix("### ") {
                    blocks.append(MarkdownBlock(type: .heading(3), text: String(combined.dropFirst(4))))
                } else if combined.hasPrefix("## ") {
                    blocks.append(MarkdownBlock(type: .heading(2), text: String(combined.dropFirst(3))))
                } else if combined.hasPrefix("# ") {
                    blocks.append(MarkdownBlock(type: .heading(1), text: String(combined.dropFirst(2))))
                } else {
                    blocks.append(MarkdownBlock(type: .paragraph, text: combined))
                }
            }
            currentTextLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(MarkdownBlock(
                        type: .code(currentCodeLanguage),
                        text: currentCodeLines.joined(separator: "\n")
                    ))
                    currentCodeLines.removeAll()
                    currentCodeLanguage = ""
                    inCodeBlock = false
                } else {
                    flushCurrentText()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    currentCodeLanguage = lang.isEmpty ? "code" : lang
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                currentCodeLines.append(line)
            } else {
                if trimmed.hasPrefix("#") {
                    flushCurrentText()
                    if trimmed.hasPrefix("### ") {
                        blocks.append(MarkdownBlock(type: .heading(3), text: String(trimmed.dropFirst(4))))
                    } else if trimmed.hasPrefix("## ") {
                        blocks.append(MarkdownBlock(type: .heading(2), text: String(trimmed.dropFirst(3))))
                    } else if trimmed.hasPrefix("# ") {
                        blocks.append(MarkdownBlock(type: .heading(1), text: String(trimmed.dropFirst(2))))
                    } else {
                        currentTextLines.append(line)
                    }
                } else if trimmed.isEmpty {
                    flushCurrentText()
                } else {
                    currentTextLines.append(line)
                }
            }
        }

        flushCurrentText()
        if inCodeBlock && !currentCodeLines.isEmpty {
            blocks.append(MarkdownBlock(
                type: .code(currentCodeLanguage),
                text: currentCodeLines.joined(separator: "\n")
            ))
        }

        return blocks
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text(language.lowercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isCopied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isCopied ? "Copied" : "Copy code")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.18))

            Divider()
                .opacity(0.3)

            // Code Content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}
