import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Optional local viewer. It never creates a display or forwards input.
@MainActor
final class AgentPreviewController: NSObject, NSWindowDelegate, SCStreamDelegate {
    private var window: NSWindow?
    private var previewView: AgentPreviewView?
    private var stream: SCStream?
    private var frameOutput: AgentPreviewFrameOutput?
    private var captureTask: Task<Void, Never>?
    private var generation = UUID()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateDockVisibility),
                                               name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        DispatchQueue.main.async { [weak self] in self?.updateDockVisibility() }
    }

    func show() {
        if window == nil { makeWindow() }
        guard let window else { return }
        positionWindow(window)
        updateDockVisibility()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if stream == nil && captureTask == nil { startPreview() }
    }

    func close() {
        window?.performClose(nil)
    }

    @objc func updateDockVisibility() {
        let hideWhenClosed = UserDefaults.standard.object(forKey: "hideDockIconWhenWindowsClosed") as? Bool ?? true
        NSApp.setActivationPolicy(window != nil || !hideWhenClosed ? .regular : .accessory)
    }

    @objc private func retryPreview() {
        startPreview()
    }

    private func makeWindow() {
        let view = AgentPreviewView()
        view.openSettings = {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
            NSWorkspace.shared.open(url)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SimpleDisplay (Agent)"
        window.contentView = view
        window.contentMinSize = NSSize(width: 480, height: 270)
        window.contentAspectRatio = previewAspectRatio
        window.isReleasedWhenClosed = false
        window.delegate = self
        let retry = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Retry")!,
                             target: self, action: #selector(retryPreview))
        retry.isBordered = false
        retry.toolTip = "Retry"
        retry.setAccessibilityLabel("Retry")
        retry.frame = NSRect(x: 4, y: 0, width: 28, height: 28)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 28))
        accessory.view.addSubview(retry)
        window.addTitlebarAccessoryViewController(accessory)
        window.setFrameAutosaveName("AgentPreview")
        positionWindow(window)
        previewView = view
        self.window = window
    }

    private var previewAspectRatio: NSSize {
        NSScreen.screens.first(where: { $0.localizedName == "Agent" })?.frame.size ?? NSSize(width: 16, height: 9)
    }

    private func positionWindow(_ window: NSWindow) {
        // Keep the viewer off Agent when a physical screen becomes available.
        guard let screen = NSScreen.screens.first(where: { $0.localizedName != "Agent" }) else {
            if window.screen == nil { window.center() }
            return
        }
        let visible = screen.visibleFrame
        if window.screen != screen || !visible.contains(window.frame) {
            let size = NSSize(width: min(window.frame.width, visible.width * 0.9),
                              height: min(window.frame.height, visible.height * 0.9))
            window.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
    }

    @objc private func displaysChanged() {
        guard let window, window.isVisible else { return }
        window.contentAspectRatio = previewAspectRatio
        positionWindow(window)
        startPreview()
    }

    private func startPreview() {
        stopPreview()
        let token = generation
        previewView?.showMessage("Starting Agent preview…", needsPermission: false)
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token { self.captureTask = nil }
            }
            do {
                let agentScreens = NSScreen.screens.filter { $0.localizedName == "Agent" }
                guard agentScreens.count == 1,
                      let number = agentScreens[0].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    self.previewView?.showMessage("Start exactly one virtual display named “Agent”, then click Retry.", needsPermission: false)
                    return
                }
                guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                    self.previewView?.showMessage(
                        "Allow SimpleDisplay in System Settings → Privacy & Security → Screen Recording, then click Retry. macOS may require reopening the app after granting access.",
                        needsPermission: true
                    )
                    return
                }
                guard !Task.isCancelled, self.generation == token else { return }
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard !Task.isCancelled, self.generation == token else { return }
                guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                    self.previewView?.showMessage("The Agent display is no longer available. Start it and click Retry.", needsPermission: false)
                    return
                }
                let ownApplication = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                guard !ownApplication.isEmpty else {
                    self.previewView?.showMessage("Cannot safely exclude this preview from capture. Close and reopen the preview to retry.", needsPermission: false)
                    return
                }
                // Exclude all our windows, including this viewer, even if it is on Agent.
                let filter = SCContentFilter(display: display, excludingApplications: ownApplication, exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = min(display.width, 1280)
                configuration.height = max(1, Int(Double(configuration.width) * Double(display.height) / Double(display.width)))
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
                configuration.queueDepth = 3
                configuration.capturesAudio = false
                configuration.showsCursor = true
                let output = AgentPreviewFrameOutput { [weak self] image in
                    guard let self, self.generation == token else { return }
                    self.previewView?.display(image)
                }
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                self.stream = stream
                self.frameOutput = output
                try await stream.startCapture()
                guard !Task.isCancelled, self.generation == token else {
                    try? await stream.stopCapture()
                    return
                }
            } catch {
                guard self.generation == token else { return }
                self.stopPreview()
                self.previewView?.showMessage("Cannot preview Agent: \(error.localizedDescription)\nCheck Screen Recording permission, then click Retry.", needsPermission: true)
            }
        }
    }

    private func stopPreview() {
        generation = UUID()
        captureTask?.cancel()
        captureTask = nil
        let oldStream = stream
        let oldOutput = frameOutput
        oldOutput?.invalidate()
        stream = nil
        frameOutput = nil
        previewView?.clearImage()
        if let oldStream {
            Task {
                try? await oldStream.stopCapture()
                if let oldOutput { try? oldStream.removeStreamOutput(oldOutput, type: .screen) }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        stopPreview()
        // Recreate the content next time so closing releases the last captured frame.
        window?.contentView = nil
        previewView = nil
        window = nil
        updateDockVisibility()
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.stopPreview()
            self.previewView?.showMessage("Agent preview stopped: \(error.localizedDescription)\nClick Retry to reconnect.", needsPermission: false)
        }
    }
}

private final class AgentPreviewFrameOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "app.simpledisplay.agent-preview", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let receive: @MainActor (CGImage) -> Void
    private let lock = NSLock()
    private var pendingFrame: CGImage?
    private var deliveryScheduled = false
    private var active = true

    init(receive: @escaping @MainActor (CGImage) -> Void) {
        self.receive = receive
    }

    func invalidate() {
        lock.lock()
        active = false
        pendingFrame = nil
        lock.unlock()
    }

    @MainActor private func deliverPendingFrame() {
        lock.lock()
        let image = active ? pendingFrame : nil
        pendingFrame = nil
        deliveryScheduled = false
        lock.unlock()
        if let image { receive(image) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        lock.lock()
        let shouldRender = active
        lock.unlock()
        guard shouldRender else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let frame = context.createCGImage(image, from: image.extent) else { return }
        lock.lock()
        guard active else { lock.unlock(); return }
        pendingFrame = frame
        let shouldSchedule = !deliveryScheduled
        deliveryScheduled = true
        lock.unlock()
        // One queued UI update holds only the latest frame if the main thread stalls.
        if shouldSchedule {
            Task { @MainActor [weak self] in self?.deliverPendingFrame() }
        }
    }
}

@MainActor
private final class AgentPreviewView: NSView {
    var openSettings: (() -> Void)?
    private let canvas = NSView()
    private let message = NSTextField(wrappingLabelWithString: "Starting Agent preview…")
    private let settingsButton = NSButton(title: "Screen Recording Settings…", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.black.cgColor
        canvas.layer?.contentsGravity = .resizeAspect
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 0
        settingsButton.target = self
        settingsButton.action = #selector(settingsPressed)
        settingsButton.isHidden = true
        canvas.translatesAutoresizingMaskIntoConstraints = false
        message.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvas)
        canvas.addSubview(message)
        canvas.addSubview(settingsButton)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
            message.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            message.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 30),
            message.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -30),
            settingsButton.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            settingsButton.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 16)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func display(_ image: CGImage) {
        canvas.layer?.contents = image
        message.isHidden = true
        settingsButton.isHidden = true
    }

    func clearImage() {
        canvas.layer?.contents = nil
    }

    func showMessage(_ text: String, needsPermission: Bool) {
        clearImage()
        message.stringValue = text
        message.isHidden = false
        settingsButton.isHidden = !needsPermission
    }

    @objc private func settingsPressed() { openSettings?() }
}
