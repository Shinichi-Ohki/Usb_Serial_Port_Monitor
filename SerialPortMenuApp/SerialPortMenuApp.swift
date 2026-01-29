import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App did finish launching")

        // Disable sudden termination to prevent app from quitting when windows close
        ProcessInfo.processInfo.disableSuddenTermination()

        // Hide Dock icon and run as menu bar only app
        NSApp.setActivationPolicy(.accessory)

        menuBarManager = MenuBarManager()
        print("MenuBarManager created")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Don't quit when last window closes
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false  // Don't create new windows on reopen
    }
}
