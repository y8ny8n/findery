import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 서비스 메뉴에 파일 URL과 문자열 타입 등록
        NSApp.registerServicesMenuSendTypes([.fileURL, .string], returnTypes: [])

        mainWindowController = MainWindowController()
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
