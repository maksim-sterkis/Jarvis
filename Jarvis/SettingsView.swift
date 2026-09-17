//
//  SettingsView.swift
//  Jarvis
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true
    @AppStorage("snapToTopAfterGeneration") private var snapToTopAfterGeneration: Bool = true
    @AppStorage("autoCollapseToolOutput") private var autoCollapseToolOutput: Bool = true
    @AppStorage("agentSecurityMode") private var agentSecurityMode: AgentSecurityMode = .alwaysAsk
    @State private var autoApprovedTools: [String] = ToolAutoApprovalManager.getAutoApprovedTools()
    @State private var autoApprovedCommands: [String] = ToolAutoApprovalManager.getAutoApprovedCommands()

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Appearance Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline.bold())

                    HStack {
                        Text("Theme")
                            .font(.body)
                        Spacer()
                        Picker("Theme", selection: $appTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 270)
                        .onChange(of: appTheme) { newTheme in
                            newTheme.applyAppearance()
                        }
                    }

                    Text("Choose whether Jarvis follows your macOS system appearance or stays locked in Light or Dark mode.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Scrolling Behavior Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Scrolling Behavior", systemImage: "arrow.up.and.down.text.horizontal")
                        .font(.subheadline.bold())

                    Toggle(isOn: $snapToTopAfterGeneration) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-Scroll & Snap to Prompt")
                                .font(.body)
                            Text("Follows text while generating, then smoothly scrolls back to the prompt when finished. When disabled, the chat will not auto-scroll.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                Divider()

                // Menu Bar Integration Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                        .font(.subheadline.bold())

                    Toggle(isOn: $showMenuBarExtra) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Jarvis in macOS Menu Bar")
                                .font(.body)
                            Text("Keep a quick access icon in the top right status bar with options to quit or summon Jarvis.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                Divider()

                // Local Model (LM Studio) Section
                VStack(alignment: .leading, spacing: 10) {
                    Label("Local Inference Engine", systemImage: "cpu")
                        .font(.subheadline.bold())

                    HStack {
                        Text("LM Studio Server:")
                            .font(.body)
                        Spacer()
                        Text("http://127.0.0.1:1234/v1")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }

                    Text("Jarvis connects directly to your local model server on Apple Silicon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Agent & Terminal Capabilities Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Agent & Terminal Permissions", systemImage: "shield.checkered")
                        .font(.subheadline.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Action Approval Policy")
                                .font(.body)
                            Text(agentSecurityMode.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Picker("Action Approval Policy", selection: $agentSecurityMode) {
                            ForEach(AgentSecurityMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    // Always-Allowed Whitelist List
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Always-Allowed Whitelist:")
                                .font(.body.weight(.medium))
                            Spacer()
                            if !autoApprovedTools.isEmpty || !autoApprovedCommands.isEmpty {
                                Button("Revoke All") {
                                    ToolAutoApprovalManager.clearAll()
                                    autoApprovedTools = []
                                    autoApprovedCommands = []
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                            }
                        }

                        if autoApprovedTools.isEmpty && autoApprovedCommands.isEmpty {
                            Text("No tools or shell commands individually auto-approved. You can click \"Always Allow\" on any tool confirmation prompt or shell command to whitelist it.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            if !autoApprovedCommands.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Whitelisted Shell Commands:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    FlowLayout(spacing: 6) {
                                        ForEach(autoApprovedCommands, id: \.self) { cmd in
                                            HStack(spacing: 5) {
                                                Image(systemName: "terminal.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.green)
                                                Text("$ \(cmd)")
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .fontWeight(.medium)
                                                Button(action: {
                                                    ToolAutoApprovalManager.removeAutoApprovedCommand(cmd)
                                                    autoApprovedCommands = ToolAutoApprovalManager.getAutoApprovedCommands()
                                                }) {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                            )
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }

                            if !autoApprovedTools.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Whitelisted Native Tools:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    FlowLayout(spacing: 6) {
                                        ForEach(autoApprovedTools, id: \.self) { tool in
                                            HStack(spacing: 5) {
                                                Image(systemName: iconForTool(tool))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.green)
                                                Text(tool)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .fontWeight(.medium)
                                                Button(action: {
                                                    ToolAutoApprovalManager.removeAutoApprovedTool(tool)
                                                    autoApprovedTools = ToolAutoApprovalManager.getAutoApprovedTools()
                                                }) {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                            )
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent Instructions File")
                                .font(.body)
                            Text("The Markdown file controlling Jarvis's persona, tool schemas, and execution protocol.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Edit AgentInstructions.md") {
                            AgentPromptManager.shared.openInstructionsFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.top, 4)

                    Toggle(isOn: $autoCollapseToolOutput) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Collapse Command Output")
                                .font(.body)
                            Text("Automatically collapses the execution output drawer once Jarvis finishes generating.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
                }

                Divider()

                // About section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jarvis macOS v0.1.0")
                        .font(.caption.bold())
                    Text("Local-first, secure autonomous agent inspired by OpenClaw.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620)
        .frame(minHeight: 560, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            autoApprovedTools = ToolAutoApprovalManager.getAutoApprovedTools()
            autoApprovedCommands = ToolAutoApprovalManager.getAutoApprovedCommands()
        }
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "run_terminal_command": return "terminal.fill"
        case "write_file": return "square.and.pencil"
        case "read_file": return "doc.text.magnifyingglass"
        case "create_directory": return "folder.badge.plus"
        case "list_directory": return "list.bullet.rectangle.portrait"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// A simple flow layout that wraps its child views to the next row when horizontal bounds are exceeded
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += maxHeight + spacing
                maxHeight = 0
            }
            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }

        return CGSize(width: width, height: currentY + maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var maxHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += maxHeight + spacing
                maxHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
    }
}
