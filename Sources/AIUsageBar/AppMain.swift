import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
@main
final class AIUsageBarMain: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let colorSettings = ColorSettings.shared
    private let popoverController = PopoverController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var previewView: StatusBarPreviewView?
    private var panel: StatusPanel?
    private var cancellables = Set<AnyCancellable>()
    private var hasRequestedNotificationAuthorization = false
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

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
        setupNotifications()
        store.start()

        // Pre-generate the color wheel image in the background so
        // the color picker opens instantly on first click.
        DispatchQueue.global(qos: .utility).async {
            let _ = ColorWheelImageCache.image(diameter: 190, brightness: 1)
        }
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

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let closeWindowItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeWindowItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(closeWindowItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.windowsMenu = windowMenu

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
        preview.providerColors = colorSettings.providerColors
        preview.colorizeIcon = colorSettings.colorizeStatusIcon
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
        colorSettings.$providerColors
            .sink { [weak self] colors in self?.previewView?.providerColors = colors }
            .store(in: &cancellables)
        colorSettings.$colorizeStatusIcon
            .sink { [weak self] enabled in self?.previewView?.colorizeIcon = enabled }
            .store(in: &cancellables)
        store.$downdetectorData
            .sink { [weak self] data in self?.previewView?.downdetectorData = data }
            .store(in: &cancellables)
        colorSettings.$ddBaselinePercent
            .sink { [weak self] val in self?.previewView?.ddBaselinePercent = val }
            .store(in: &cancellables)
        colorSettings.$refreshIntervalMinutes
            .sink { [weak self] _ in
                self?.previewView?.ddFreshnessInterval = self?.colorSettings.downdetectorFreshnessInterval ?? 600
            }
            .store(in: &cancellables)
        colorSettings.$showDowndetector
            .sink { [weak self] val in self?.previewView?.showDowndetector = val }
            .store(in: &cancellables)
        colorSettings.$showAlertDot
            .sink { [weak self] val in self?.previewView?.showAlertDot = val }
            .store(in: &cancellables)
        colorSettings.$enabledProviders
            .sink { [weak self] val in self?.previewView?.enabledProviders = val }
            .store(in: &cancellables)
        colorSettings.$showProviderLabels
            .sink { [weak self] val in self?.previewView?.showProviderLabels = val }
            .store(in: &cancellables)
        popoverController.$preferredSize
            .sink { [weak self] size in
                guard let self, size.width > 0, size.height > 0, let panel = self.panel else { return }
                let current = panel.contentLayoutRect.size
                let dw = abs(size.width - current.width)
                let dh = abs(size.height - current.height)
                // Only resize/reposition if the size changed meaningfully
                // to prevent micro-shifts while dragging sliders
                guard dw > 5 || dh > 5 else { return }
                panel.setContentSize(NSSize(width: size.width, height: size.height))
                self.positionPanelRelativeToStatusItem()
            }
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

    // MARK: - Panel

    private func configurePanel() {
        let rootView = PopoverView()
            .environmentObject(store)
            .environmentObject(colorSettings)
            .environmentObject(popoverController)
        let controller = NSHostingController(rootView: rootView)
        let panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = controller
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.setContentSize(NSSize(width: 310, height: 420))
        self.panel = panel
        popoverController.close = { [weak self] in
            self?.closePanel()
        }
        installEventMonitors()
    }

    private func handleEscapeKey() -> Bool {
        if popoverController.showSettings {
            popoverController.showSettings = false
            return true
        }
        if popoverController.showDowndetector {
            popoverController.showDowndetector = false
            return true
        }
        closePanel()
        return true
    }

    private func closePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        popoverController.didClose()
    }

    @objc
    private func togglePanel(_ sender: AnyObject?) {
        guard statusItem.button != nil else { return }

        if panel?.isVisible == true {
            closePanel()
            return
        }

        showPanel()
    }

    private func showPanel() {
        guard panel != nil else { return }
        positionPanelRelativeToStatusItem()
        panel?.makeKeyAndOrderFront(nil)
    }

    private func positionPanelRelativeToStatusItem() {
        guard let button = statusItem.button, let panel else { return }

        var buttonFrame = button.convert(button.bounds, to: nil)
        if let window = button.window {
            buttonFrame = window.convertToScreen(buttonFrame)
        }

        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: buttonFrame.midX - panelSize.width / 2,
            y: buttonFrame.minY - panelSize.height
        )
        panel.setFrameOrigin(origin)
        clampPanelToVisibleScreen()
    }

    private func clampPanelToVisibleScreen() {
        guard let panel else { return }
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        guard !visible.isEmpty else { return }

        var frame = panel.frame

        if frame.width > visible.width {
            frame.size.width = visible.width - 20
        }
        if frame.height > visible.height {
            frame.size.height = visible.height - 20
        }

        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        if frame.maxX > visible.maxX {
            frame.origin.x = visible.maxX - frame.width
        }
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        if frame.maxY > visible.maxY {
            frame.origin.y = visible.maxY - frame.height
        }

        panel.setFrame(frame, display: true)
    }

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel, panel.isVisible else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                _ = self.handleEscapeKey()
                return nil
            }

            guard event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown else {
                return event
            }

            let location = NSEvent.mouseLocation
            if panel.frame.contains(location) || self.statusItemButtonFrameOnScreen()?.contains(location) == true {
                return event
            }

            self.closePanel()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, let panel, panel.isVisible else { return }
            let location = NSEvent.mouseLocation
            if panel.frame.contains(location) || self.statusItemButtonFrameOnScreen()?.contains(location) == true {
                return
            }
            self.closePanel()
        }
    }

    private func statusItemButtonFrameOnScreen() -> NSRect? {
        guard let button = statusItem.button else { return nil }
        var frame = button.convert(button.bounds, to: nil)
        guard let window = button.window else { return nil }
        frame = window.convertToScreen(frame)
        return frame
    }

    // MARK: - Notifications

    private var activeAlerts: Set<String> = []

    private func setupNotifications() {
        colorSettings.$sendNotifications
            .dropFirst()
            .sink { [weak self] enabled in
                guard enabled else { return }
                self?.requestNotificationAuthorizationIfNeeded()
            }
            .store(in: &cancellables)

        // Monitor downdetector changes
        store.$downdetectorData
            .sink { [weak self] data in
                guard let self else { return }
                self.checkForAlerts(cards: self.store.cards, downdetector: data)
            }
            .store(in: &cancellables)

        // Monitor usage changes
        store.$cards
            .sink { [weak self] cards in
                guard let self else { return }
                self.checkForAlerts(cards: cards, downdetector: self.store.downdetectorData)
            }
            .store(in: &cancellables)
    }

    private func checkForAlerts(cards: [ProviderUsageCard], downdetector: [ProviderID: DowndetectorReport]) {
        guard colorSettings.sendNotifications else {
            activeAlerts.removeAll()
            return
        }

        // Check low usage
        for card in cards where card.authenticated {
            let key = "usage-\(card.id.rawValue)"
            if let frac = card.bestFraction, frac >= 0.9 {
                if !activeAlerts.contains(key) {
                    activeAlerts.insert(key)
                    let pctLeft = Int(((1 - frac) * 100).rounded())
                    sendNotification(
                        title: "\(card.id.title) usage low",
                        body: "Only \(pctLeft)% remaining"
                    )
                }
            } else {
                activeAlerts.remove(key)
            }
        }

        // Check downdetector
        if colorSettings.showDowndetector {
            for provider in ProviderID.allCases {
                let key = "dd-\(provider.rawValue)"
                if let report = downdetector[provider] {
                    let status = report.alertStatus(
                        baselinePercent: colorSettings.ddBaselinePercent,
                        staleAfter: colorSettings.downdetectorFreshnessInterval
                    )
                    if status.hasProblems {
                        if !activeAlerts.contains(key) {
                            activeAlerts.insert(key)
                            sendNotification(
                                title: "\(provider.title): \(status.label)",
                                body: "Downdetector reports issues with \(provider.title)"
                            )
                        }
                    } else {
                        activeAlerts.remove(key)
                    }
                }
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        requestNotificationAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard !hasRequestedNotificationAuthorization else { return }
        hasRequestedNotificationAuthorization = true
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}
