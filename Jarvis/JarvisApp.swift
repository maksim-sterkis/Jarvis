//
//  JarvisApp.swift
//  Jarvis
//
//  Created by Maksim Sterkis on 9/11/26.
//

import SwiftUI

/// An NSViewRepresentable helper to access the hosting NSWindow for identification and configuration
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Helper to determine if a given NSWindow belongs to Settings or an auxiliary preferences panel
func isSettingsWindow(_ window: NSWindow) -> Bool {
    if let id = window.identifier?.rawValue {
        if id == "JarvisSettingsWindow" || id.localizedCaseInsensitiveContains("settings") {
            return true
        }
    }
    if window.title.localizedCaseInsensitiveContains("settings") {
        return true
    }
    return false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isQuitting = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.quitApplication()
        return .terminateNow
    }

    static func quitApplication() {
        guard !isQuitting else { return }
        isQuitting = true

        // 1. Cancel background timers and active tasks immediately
        ChatViewModel.stopAllTimers()

        // 2. Hide all windows immediately
        for window in NSApplication.shared.windows {
            window.orderOut(nil)
        }

        // 3. Stop LM Studio if autoStop is enabled AND Jarvis launched it
        let autoStop = UserDefaults.standard.object(forKey: "autoStopServerOnQuit") as? Bool ?? true
        if autoStop && LMStudioService.shared.didJarvisLaunchServer {
            LMStudioService.shared.killLMStudioImmediately()
        }

        // 4. Terminate process immediately (<0.01s)
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Observe window close notifications so closing the main chat window quits Jarvis cleanly,
        // while closing auxiliary windows (such as the Settings panel) does NOT quit the application.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            guard let window = notification.object as? NSWindow, window.canBecomeMain else { return }

            // Never terminate when the user closes the Settings window or auxiliary panels
            if isSettingsWindow(window) || window is NSPanel {
                return
            }

            // Check if closing this window leaves no other main content windows open
            let remainingMainWindows = NSApplication.shared.windows.filter { other in
                other !== window &&
                other.isVisible &&
                !isSettingsWindow(other) &&
                !(other is NSPanel) &&
                other.canBecomeMain
            }

            if remainingMainWindows.isEmpty {
                AppDelegate.quitApplication()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Only terminate if no main content windows remain open
        let openMainWindows = sender.windows.filter { window in
            window.isVisible &&
            !isSettingsWindow(window) &&
            !(window is NSPanel) &&
            window.canBecomeMain
        }
        return openMainWindows.isEmpty
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.quitApplication()
    }
}

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appTheme.colorScheme)
                .onAppear {
                    appTheme.applyAppearance()
                }
                .onChange(of: appTheme) { newTheme in
                    newTheme.applyAppearance()
                }
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Jarvis") {
                    AppDelegate.quitApplication()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appTheme.colorScheme)
        }

        MenuBarExtra("Jarvis", image: "MenuBarIcon", isInserted: $showMenuBarExtra) {
            Button("Quit Jarvis") {
                AppDelegate.quitApplication()
            }
        }
    }
}
