import AppKit
import Combine
import SwiftUI

@MainActor
@main
final class AIUsageBarMain: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let colorSettings = ColorSettings.shared
    private let popoverController = PopoverController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var previewView: StatusBarPreviewView?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let application = NSApplication.shared
        let delegate = AIUsageBarMain()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureAppIcon()
        configureMainMenu()
        configureStatusItem()
        configurePanel()
        bindStore()
        store.start()
    }

    private func configureAppIcon() {
        let size: CGFloat = 256
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Background rounded rect
            let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 48, yRadius: 48)
            NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).setFill()
            bgPath.fill()

            // Draw three usage bars
            let barColors: [NSColor] = [
                NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.19, alpha: 1.0), // orange
                .white,
                NSColor(calibratedRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0), // gray
            ]
            let fills: [CGFloat] = [0.65, 0.40, 0.20]
            let barH: CGFloat = 28
            let barGap: CGFloat = 20
            let barInset: CGFloat = 44.0
            let totalBarsH = CGFloat(barColors.count) * barH + CGFloat(barColors.count - 1) * barGap
            let startY = (size - totalBarsH) / 2

            for (i, color) in barColors.enumerated() {
                let y = startY + CGFloat(barColors.count - 1 - i) * (barH + barGap)
                let barRect = NSRect(x: barInset, y: y, width: size - barInset * 2, height: barH)
                let radius = barH / 2

                // Track
                let track = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
                NSColor.white.withAlphaComponent(0.1).setFill()
                track.fill()

                // Fill
                let fillW = max(barH, barRect.width * fills[i])
                let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillW, height: barH)

                NSGraphicsContext.saveGraphicsState()
                let clip = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
                clip.addClip()
                color.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            return true
        }
        NSApp.applicationIconImage = image
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Bitstraum Usage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let preview = StatusBarPreviewView()
        preview.cards = store.cards
        preview.isRefreshing = store.isRefreshing
        preview.attach(to: button)

        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.previewView = preview
    }

    private func bindStore() {
        store.$cards
            .sink { [weak self] cards in self?.previewView?.cards = cards }
            .store(in: &cancellables)
        store.$isRefreshing
            .sink { [weak self] refreshing in self?.previewView?.isRefreshing = refreshing }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .signInCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Small delay to let the sign-in window fully close
                // and activation policy switch back to .accessory
                try? await Task.sleep(for: .milliseconds(500))
                self?.showPanel()
            }
        }
    }

    // MARK: - Popover

    private func configurePanel() {
        let rootView = PopoverView()
            .environmentObject(store)
            .environmentObject(colorSettings)
            .environmentObject(popoverController)
        let controller = NSHostingController(rootView: rootView)
        controller.view.frame.size = controller.view.fittingSize

        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popoverController.close = { [weak self] in
            self?.popover.performClose(nil)
        }
    }

    @objc
    private func togglePanel(_ sender: AnyObject?) {
        guard statusItem.button != nil else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
