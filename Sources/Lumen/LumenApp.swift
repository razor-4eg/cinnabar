import AppKit
import SwiftUI

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(DockDelegate.self) private var dock

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Find video") {
                    Task { await AppModel.shared.resolve() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Download") {
                    AppModel.shared.download()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(AppModel.shared)
        }
        .defaultSize(width: 680, height: 520)
    }
}

final class DockDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        for window in application.windows where window.canBecomeMain {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        if application.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            application.activate()
            return true
        }
        if let item = application.mainMenu?.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask.contains(.command) }),
           let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
            application.activate()
            return true
        }
        return false
    }
}
