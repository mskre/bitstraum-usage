import AppKit
import Combine
import SwiftUI

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
@main
final class AIUsageBarMain: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var previewView: StatusBarPreviewView?
    private var panel: KeyablePanel?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let application = NSApplication.shared
        let delegate = AIUsageBarMain()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureStatusItem()
        configurePanel()
        bindStore()
        startEventMonitor()
        store.start()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit AI Usage Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
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
        self.previewView = preview
    }

    private func bindStore() {
        store.$cards
            .sink { [weak self] cards in self?.previewView?.cards = cards }
            .store(in: &cancellables)
        store.$isRefreshing
            .sink { [weak self] refreshing in self?.previewView?.isRefreshing = refreshing }
            .store(in: &cancellables)
    }

    // MARK: - Liquid Glass Panel

    private func configurePanel() {
        let hostingView = NSHostingView(rootView: PopoverView().environmentObject(store))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 10),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.isMovableByWindowBackground = false

        // Use NSVisualEffectView for native translucent menu-like background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .menu
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        p.contentView = visualEffect

        self.panel = p
    }

    @objc
    private func togglePanel(_ sender: AnyObject?) {
        guard let panel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
            return
        }

        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 400)
        let x = buttonFrame.midX - panelSize.width / 2
        let y = buttonFrame.minY - panelSize.height - 4

        panel.setContentSize(panelSize)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Event monitor

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.panel?.orderOut(nil) }
        }
    }
}
