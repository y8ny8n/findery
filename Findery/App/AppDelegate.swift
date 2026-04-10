import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var windowControllers: [MainWindowController] = []
    private lazy var preferencesWindowController = PreferencesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Services / Writing Tools 메뉴 비활성화
        NSApp.servicesMenu = nil

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
        let existingFrame = NSApp.keyWindow?.frame
        let wc = createWindowController()
        guard let window = wc.window else { return }
        window.tabbingMode = .disallowed
        if let frame = existingFrame {
            let offset: CGFloat = 26
            window.setFrameOrigin(NSPoint(x: frame.origin.x + offset, y: frame.origin.y - offset))
        }
        window.makeKeyAndOrderFront(nil)
    }

    @IBAction func newTab(_ sender: Any?) {
        guard let currentWindow = NSApp.keyWindow else { return }
        let wc = createWindowController()
        guard let newWindow = wc.window else { return }
        currentWindow.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
    }

    @objc func showPreferences(_ sender: Any?) {
        preferencesWindowController.showAndActivate()
    }
}
