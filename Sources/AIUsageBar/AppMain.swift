import AppKit
import Combine
import SwiftUI

/// NSPanel subclass that can become key so SwiftUI buttons inside it actually work.
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
        configureStatusItem()
        configurePanel()
        bindStore()
        startEventMonitor()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let preview = StatusBarPreviewView()
        preview.cards = store.cards
        preview.isRefreshing = store.isRefreshing
        preview.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            preview.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            preview.topAnchor.constraint(equalTo: button.topAnchor),
            preview.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        button.frame = NSRect(x: 0, y: 0, width: preview.intrinsicContentSize.width + 4, height: 22)
        button.target = self
        button.action = #selector(togglePanel(_:))

        self.previewView = preview
    }

    private func bindStore() {
        store.$cards
            .sink { [weak self] cards in
                self?.previewView?.cards = cards
            }
            .store(in: &cancellables)

        store.$isRefreshing
            .sink { [weak self] refreshing in
                self?.previewView?.isRefreshing = refreshing
            }
            .store(in: &cancellables)
    }

    // MARK: - Panel

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

        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 12
        wrapper.layer?.masksToBounds = true
        wrapper.layer?.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1).cgColor

        p.contentView = wrapper
        wrapper.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

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
            Task { @MainActor in
                self?.panel?.orderOut(nil)
            }
        }
    }
}
