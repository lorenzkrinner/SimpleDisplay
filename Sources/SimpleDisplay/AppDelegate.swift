import AppKit
import os
import SimpleDisplayCore

private let logger = Logger(subsystem: "app.simpledisplay", category: "URLScheme")

/// Owns the shared `DisplayManagerViewModel` so both the SwiftUI menu-bar
/// scene and the `simpledisplay://` URL handler reach the same instance.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = DisplayManagerViewModel()
    private var quitRequestedFromPopover = false
    private var menuBarController: MenuBarPopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarPopoverController(viewModel: viewModel)
        viewModel.requestQuitFromPopover = { [weak self] in
            guard let self else { return }
            self.quitRequestedFromPopover = true
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitRequestedFromPopover { return .terminateNow }
        // Preserve macOS logout/restart/shutdown while treating ordinary Quit as Close.
        if let reason = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue,
           [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut].contains(reason) {
            return .terminateNow
        }
        viewModel.closePreview()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // remotedesk: dedupe entre application(_:open:) y el handler GURL de Apple Events.
    private var lastHandled: (url: String, time: Date)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // remotedesk fix: en apps de barra de menú, application(_:open:) NO se dispara
        // de forma fiable cuando la app ya corre. Registramos el handler GURL de bajo
        // nivel (Apple Events), que sí recibe simpledisplay:// en todos los casos.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(0x4755524C), // 'GURL'
            andEventID: AEEventID(0x4755524C))        // 'GURL'
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event
                .paramDescriptor(forKeyword: AEKeyword(0x2D2D2D2D))? // '----'
                .stringValue,
              let url = URL(string: urlString) else { return }
        handle(url)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        let now = Date()
        if let last = lastHandled,
           last.url == url.absoluteString,
           now.timeIntervalSince(last.time) < 1.0 {
            return // ya procesada por el otro camino hace <1s
        }
        lastHandled = (url.absoluteString, now)

        switch URLCommandParser.parse(url) {
        case .success(let command):
            logger.info("URL command: \(String(describing: command))")
            viewModel.execute(urlCommand: command)
        case .failure(let error):
            logger.warning("Ignoring malformed simpledisplay URL \(url.absoluteString, privacy: .public): \(error.description, privacy: .public)")
            viewModel.errorMessage = "Ignored URL: \(error.description)"
        }
    }
}
