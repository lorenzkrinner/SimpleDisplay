import AppKit
import SwiftUI

/// Owns one native popover, with no second SwiftUI window around its content.
@MainActor
final class MenuBarPopoverController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(viewModel: DisplayManagerViewModel) {
        super.init()
        let locale = LocaleManager()
        viewModel.locale = locale
        let content = MenuBarContentView()
            .environment(viewModel)
            .environment(locale)
        let hosting = NSHostingController(rootView: content)
        // The popover supplies its own chrome. Its SwiftUI content needs no window insets.
        hosting.safeAreaRegions = []
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false
        if let button = statusItem.button {
            button.image = BrandAssets.menuBarIcon
            button.toolTip = "SimpleDisplay"
            button.target = self
            button.action = #selector(togglePopover)
        }
        viewModel.dismissPopover = { [weak self] in self?.popover.performClose(nil) }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
