import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var windowControllers: [MainWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.registerServicesMenuSendTypes([.fileURL, .string], returnTypes: [])

        let wc = createWindowController()
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @discardableResult
    func createWindowController() -> MainWindowController {
        let wc = MainWindowController()
        windowControllers.append(wc)
        return wc
    }

    @IBAction func newWindow(_ sender: Any?) {
        let wc = createWindowController()
        wc.window?.tabbingMode = .disallowed
        wc.window?.makeKeyAndOrderFront(nil)
    }

    @IBAction func newTab(_ sender: Any?) {
        guard let currentWindow = NSApp.keyWindow else { return }
        let wc = createWindowController()
        guard let newWindow = wc.window else { return }
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }
}
