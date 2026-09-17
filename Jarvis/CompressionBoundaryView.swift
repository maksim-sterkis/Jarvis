//
//  CompressionBoundaryView.swift
//  Jarvis
//

import SwiftUI
import AppKit

struct CompressionBoundaryView: View {
    let snapshot: String
    var tokenSavingsPercent: Int = 80
    var compressionLevel: String? = nil
    var tokensBefore: Int? = nil
    var tokensAfter: Int? = nil
    @State private var isExpanded: Bool = false
    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false

    private var savingsTooltip: String {
        if let before = tokensBefore, let after = tokensAfter {
            return "\(before) tokens → \(after) tokens (\(tokenSavingsPercent)% reduction)"
        }
        return "~\(tokenSavingsPercent)% reduction in AI context tokens"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Horizontal divider with central card
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accentColor)

                    Text("Context Compressed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    if let level = compressionLevel, !level.isEmpty {
                        Text(level.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    }

                    Text("~\(tokenSavingsPercent)% Saved")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                        .help(savingsTooltip)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(14)

                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.vertical, 4)

            // Info & Expandable Drawer Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Historical messages above are preserved visually. The AI now receives a dense memory snapshot + new messages.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(isExpanded ? "Hide Snapshot" : "View AI Snapshot")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("AI Memory Snapshot")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(snapshot, forType: .string)
                                isCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isCopied = false
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    Text(isCopied ? "Copied" : "Copy")
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        ScrollView(.vertical, showsIndicators: true) {
                            Text(snapshot)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .padding(.vertical, 6)
    }
}
