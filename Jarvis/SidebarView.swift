//
//  SidebarView.swift
//  Jarvis
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // New Chat Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.startNewChat()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New Chat")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("⌘N")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command])
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Conversation list
            List(selection: $viewModel.selectedConversationId) {
                Section(header: Text("Chats").font(.caption).foregroundColor(.secondary)) {
                    ForEach(viewModel.conversations) { conv in
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            Text(conv.title)
                                .font(.system(size: 13))
                                .lineLimit(1)

                            Spacer()
                        }
                        .tag(conv.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteConversation(id: conv.id)
                            } label: {
                                Label("Delete Chat", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Footer (Settings & Status)
            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jarvis")
                        .font(.system(size: 12, weight: .semibold))
                    Text(viewModel.isConnected ? "Local Model Ready" : "Offline")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    openSettings()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
    }
}
