import AppKit

@MainActor
final class MacInfoAppDelegate:
    NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}
