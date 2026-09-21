//
//  MarkdownDocumentViewerSheet.swift
//  Jarvis
//

import SwiftUI
import AppKit

struct DocumentViewerState: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var filePath: String
    var content: String
    var isPlaybookCollection: Bool = false
    var selectedPlaybookId: String? = nil
    var playbooksList: [PlaybookInfo] = []

    static func == (lhs: DocumentViewerState, rhs: DocumentViewerState) -> Bool {
        lhs.id == rhs.id
    }
}

struct MarkdownDocumentViewerSheet: View {
    @Binding var documentState: DocumentViewerState?
    @State private var activePlaybookId: String = ""
    @State private var activeContent: String = ""
    @State private var activeTitle: String = ""
    @State private var activePath: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar / Title Bar
            HStack(spacing: 12) {
                Image(systemName: iconForDocument)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(activeTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(pathShortDescription)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }

                    HStack(spacing: 10) {
                        Text("\(wordCount) words")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("~" + "\(estimatedTokens) tokens")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("Rendered Markdown")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                // "Open in External Editor" action
                Button(action: {
                    openInExternalEditor()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                        Text("Open in Editor")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Open raw markdown file in default external editor")

                // "Done" / Close button
                Button(action: {
                    documentState = nil
                }) {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider().opacity(0.6)

            // Playbooks Selector Tab Bar (when viewing playbooks collection)
            if let doc = documentState, doc.isPlaybookCollection, !doc.playbooksList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(doc.playbooksList) { pb in
                            let isSelected = (pb.id == activePlaybookId)
                            Button(action: {
                                selectPlaybook(pb)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 10))
                                        .foregroundColor(isSelected ? .white : .accentColor)

                                    Text(pb.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? .white : .primary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.09))
                                .cornerRadius(7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                Divider().opacity(0.3)
            }

            // Scrollable Rendered Markdown Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    MarkdownMessageView(content: activeContent)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        }
        .frame(minWidth: 720, idealWidth: 840, maxWidth: 1000, minHeight: 520, idealHeight: 640, maxHeight: 850)
        .onAppear {
            setupInitialContent()
        }
    }

    private func setupInitialContent() {
        guard let doc = documentState else { return }

        if doc.isPlaybookCollection {
            let targetPb: PlaybookInfo?
            if let selectedId = doc.selectedPlaybookId,
               let match = doc.playbooksList.first(where: { $0.id == selectedId || $0.id.replacingOccurrences(of: ".md", with: "") == selectedId }) {
                targetPb = match
            } else {
                targetPb = doc.playbooksList.first
            }

            if let pb = targetPb {
                selectPlaybook(pb)
            } else {
                activeTitle = doc.title
                activePath = doc.filePath
                activeContent = doc.content
            }
        } else {
            activeTitle = doc.title
            activePath = doc.filePath
            activeContent = doc.content
        }
    }

    private func selectPlaybook(_ pb: PlaybookInfo) {
        activePlaybookId = pb.id
        activeTitle = "Playbook: \(pb.title)"
        activePath = pb.path
        if let content = PlaybookService.shared.loadPlaybookContent(info: pb) {
            activeContent = content
        } else {
            activeContent = "# \(pb.title)\n\n\(pb.summary)"
        }
    }

    private func openInExternalEditor() {
        let expanded = (activePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    private var iconForDocument: String {
        if documentState?.isPlaybookCollection == true || activePath.contains("playbook") {
            return "book.pages"
        }
        return "doc.text"
    }

    private var pathShortDescription: String {
        if activePath.hasPrefix(NSHomeDirectory()) {
            return activePath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return activePath
    }

    private var wordCount: Int {
        let words = activeContent.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    private var estimatedTokens: Int {
        max(1, Int(Double(activeContent.count) / 3.8))
    }
}
