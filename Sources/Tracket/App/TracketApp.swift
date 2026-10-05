import AppKit
import SwiftUI

final class TracketAppDelegate: NSObject, NSApplicationDelegate {
    private var quitRequestedFromMenuBar = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Tracket menu-bar monitoring is active")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard quitRequestedFromMenuBar else {
            sender.windows.forEach { window in
                if window.isVisible && window.canBecomeMain { window.orderOut(nil) }
            }
            return .terminateCancel
        }
        return .terminateNow
    }

    func quitFromMenuBar() {
        quitRequestedFromMenuBar = true
        NSApplication.shared.terminate(nil)
    }
}

@main
struct TracketApp: App {
    @NSApplicationDelegateAdaptor(TracketAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        Window("Tracket", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1_080, minHeight: 720)
        }
        .defaultSize(width: 1_280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Track Project…") {
                    store.isAddingProject = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Image(systemName: store.monitoringEnabled ? "arrow.up.forward.circle.fill" : "pause.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
