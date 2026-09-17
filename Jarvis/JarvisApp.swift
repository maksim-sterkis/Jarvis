//
//  JarvisApp.swift
//  Jarvis
//
//  Created by Maksim Sterkis on 9/11/26.
//

import SwiftUI

@main
struct JarvisApp: App {
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = true

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

        Settings {
            SettingsView()
                .preferredColorScheme(appTheme.colorScheme)
        }

        MenuBarExtra("Jarvis", image: "MenuBarIcon", isInserted: $showMenuBarExtra) {
            Button("Quit Jarvis") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
