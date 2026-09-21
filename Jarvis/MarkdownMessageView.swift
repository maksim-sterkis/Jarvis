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
    case table(headers: [String], rows: [[String]])
    case divider
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
                    let fontSize: CGFloat = {
                        switch level {
                        case 1: return 18
                        case 2: return 16
                        case 3: return 14.5
                        case 4: return 13.5
                        case 5: return 12.5
                        default: return 12
                        }
                    }()
                    let fontWeight: Font.Weight = {
                        switch level {
                        case 1, 2: return .bold
                        case 3, 4: return .semibold
                        default: return .medium
                        }
                    }()
                    Text(LocalizedStringKey(block.text.trimmingCharacters(in: .whitespaces)))
                        .font(.system(size: fontSize, weight: fontWeight))
                        .foregroundColor(.primary)
                        .padding(.top, level <= 2 ? 6 : 3)
                        .textSelection(.enabled)

                case .paragraph:
                    Text(LocalizedStringKey(block.text))
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                case .code(let language):
                    CodeBlockView(language: language, code: block.text)

                case .table(let headers, let rows):
                    MarkdownTableView(headers: headers, rows: rows)

                case .divider:
                    Divider().padding(.vertical, 4)
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
                if let heading = extractHeading(from: combined) {
                    blocks.append(heading)
                } else {
                    blocks.append(MarkdownBlock(type: .paragraph, text: combined))
                }
            }
            currentTextLines.removeAll()
        }

        func extractHeading(from text: String) -> MarkdownBlock? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("###### ") {
                return MarkdownBlock(type: .heading(6), text: String(trimmed.dropFirst(7)))
            } else if trimmed.hasPrefix("##### ") {
                return MarkdownBlock(type: .heading(5), text: String(trimmed.dropFirst(6)))
            } else if trimmed.hasPrefix("#### ") {
                return MarkdownBlock(type: .heading(4), text: String(trimmed.dropFirst(5)))
            } else if trimmed.hasPrefix("### ") {
                return MarkdownBlock(type: .heading(3), text: String(trimmed.dropFirst(4)))
            } else if trimmed.hasPrefix("## ") {
                return MarkdownBlock(type: .heading(2), text: String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("# ") {
                return MarkdownBlock(type: .heading(1), text: String(trimmed.dropFirst(2)))
            }
            return nil
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
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
                i += 1
                continue
            }

            if inCodeBlock {
                currentCodeLines.append(line)
                i += 1
                continue
            }

            // Check for Markdown Horizontal Rule (---, ***, ___)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushCurrentText()
                blocks.append(MarkdownBlock(type: .divider, text: ""))
                i += 1
                continue
            }

            // Check for Markdown Table (line starts and ends with |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|") {
                // Check if next line looks like a separator (e.g. |---|---|)
                if i + 1 < lines.count {
                    let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    let isSeparator = nextTrimmed.hasPrefix("|") && nextTrimmed.contains("-")
                    if isSeparator {
                        flushCurrentText()
                        let headers = parseTableRow(trimmed)
                        var tableRows: [[String]] = []
                        i += 2 // skip header and separator

                        while i < lines.count {
                            let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                            if rowLine.hasPrefix("|") && rowLine.hasSuffix("|") {
                                tableRows.append(parseTableRow(rowLine))
                                i += 1
                            } else {
                                break
                            }
                        }

                        blocks.append(MarkdownBlock(type: .table(headers: headers, rows: tableRows), text: ""))
                        continue
                    }
                }
            }

            // Check for Heading (#, ##, ###, ####, #####, ######)
            if trimmed.hasPrefix("#") {
                flushCurrentText()
                if let heading = extractHeading(from: trimmed) {
                    blocks.append(heading)
                } else {
                    currentTextLines.append(line)
                }
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushCurrentText()
            } else {
                currentTextLines.append(line)
            }
            i += 1
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

    private func parseTableRow(_ line: String) -> [String] {
        let raw = line.trimmingCharacters(in: .whitespaces)
        guard raw.hasPrefix("|") && raw.hasSuffix("|") else { return [] }
        let inner = String(raw.dropFirst().dropLast())
        return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    ForEach(0..<headers.count, id: \.self) { colIndex in
                        Text(LocalizedStringKey(headers[colIndex]))
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minWidth: 130, alignment: .leading)
                            .textSelection(.enabled)
                        if colIndex < headers.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.secondary.opacity(0.12))

                Divider()

                // Data Rows
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    HStack(spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { colIndex in
                            let cellText = colIndex < row.count ? row[colIndex] : ""
                            Text(LocalizedStringKey(cellText))
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .frame(minWidth: 130, alignment: .leading)
                                .textSelection(.enabled)
                            if colIndex < headers.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(rowIndex % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)

                    if rowIndex < rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.vertical, 6)
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
