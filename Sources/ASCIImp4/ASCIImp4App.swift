import SwiftUI
import AppKit

@main
struct ASCIImp4App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ASCIImp4", id: "main") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 680)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.post(name: .openFileRequest, object: nil)
                }
                .keyboardShortcut("o")

                Button("Save Frame as PNG…") {
                    NotificationCenter.default.post(name: .exportFrameRequest, object: nil)
                }
                .keyboardShortcut("e")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
