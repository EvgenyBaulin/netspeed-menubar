import AppKit
import SwiftUI

/// Hosts SwiftUI content inside the status item button while letting all
/// mouse events fall through to the button itself.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = NetMonitor()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor.start()
        setUpStatusItem()
        setUpPopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }

        let hosting = PassthroughHostingView(rootView: StatusItemView(monitor: monitor))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setUpPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(monitor: monitor))
        self.popover = popover
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            repositionBelowMenuBar(popover: popover, button: button)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    /// The system can anchor a status-item popover so that it overlaps the
    /// menu bar itself; move its window down so it sits fully below the bar.
    private func repositionBelowMenuBar(popover: NSPopover, button: NSStatusBarButton) {
        guard let popoverWindow = popover.contentViewController?.view.window,
              let statusWindow = button.window
        else { return }
        let menuBarBottom = statusWindow.frame.minY
        var frame = popoverWindow.frame
        guard frame.maxY > menuBarBottom else { return }
        frame.origin.y = menuBarBottom - frame.height
        popoverWindow.setFrame(frame, display: true)
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit NetSpeed",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        // Assigning the menu and clicking is the supported way to show a
        // status-item menu on demand without hijacking left clicks.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
