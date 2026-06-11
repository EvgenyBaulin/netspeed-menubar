import AppKit
import SwiftUI

/// Hosts SwiftUI content inside the status item button while letting all
/// mouse events fall through to the button itself.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var monitor = NetMonitor(settings: settings)
    private let appTraffic = AppTrafficMonitor()
    private let speedTester = SpeedTester()
    private let windowState = WindowState()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor.start()
        speedTester.monitor = monitor
        speedTester.applyAutoInterval(settings.speedTestInterval)
        setUpStatusItem()
        setUpPopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        speedTester.stopAuto()
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

        let hosting = PassthroughHostingView(
            rootView: StatusItemView(monitor: monitor, settings: settings, speedTester: speedTester)
        )
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
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                monitor: monitor,
                settings: settings,
                speedTester: speedTester,
                onOpenSettings: { [weak self] in self?.openAppWindow(at: .settings) },
                onOpenDetails: { [weak self] in self?.openAppWindow(at: .network) }
            )
        )
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

        let detailsItem = NSMenuItem(
            title: L("Details…"),
            action: #selector(openDetailsFromMenu),
            keyEquivalent: "d"
        )
        detailsItem.target = self
        menu.addItem(detailsItem)

        let settingsItem = NSMenuItem(
            title: L("Settings…"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: L("Quit NetSpeed"),
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

    @objc private func openSettingsFromMenu() {
        openAppWindow(at: .settings)
    }

    @objc private func openDetailsFromMenu() {
        openAppWindow(at: .network)
    }

    // MARK: - Application window

    private func openAppWindow(at section: AppSection) {
        popover?.performClose(nil)
        windowState.section = section
        if let window = appWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let hosting = NSHostingController(
            rootView: AppWindowView(
                monitor: monitor,
                settings: settings,
                state: windowState,
                appTraffic: appTraffic,
                speedTester: speedTester
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "NetSpeed"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("NetSpeedAppWindow")
        appWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
