import AppKit
import SwiftUI

@MainActor
final class ColorSettings: ObservableObject {
    static let shared = ColorSettings()

    @Published private(set) var providerColors: [ProviderID: NSColor]

    @Published var dismissOnMouseExit: Bool {
        didSet { defaults.set(dismissOnMouseExit, forKey: dismissKey) }
    }

    @Published var colorizeStatusIcon: Bool {
        didSet { defaults.set(colorizeStatusIcon, forKey: colorizeIconKey) }
    }

    @Published var rememberLastView: Bool {
        didSet { defaults.set(rememberLastView, forKey: rememberViewKey) }
    }

    @Published var lastOpenView: String {
        didSet {
            guard rememberLastView else { return }
            defaults.set(lastOpenView, forKey: lastOpenViewKey)
        }
    }

    @Published var refreshIntervalMinutes: Double {
        didSet { defaults.set(refreshIntervalMinutes, forKey: refreshIntervalKey) }
    }

    @Published var maskSensitiveData: Bool {
        didSet { defaults.set(maskSensitiveData, forKey: maskSensitiveDataKey) }
    }

    @Published var showSensitiveInfo: Bool {
        didSet { defaults.set(showSensitiveInfo, forKey: showSensitiveInfoKey) }
    }

    @Published var maskPercentage: Double {
        didSet { defaults.set(maskPercentage, forKey: maskPercentageKey) }
    }

    @Published var maskDomainOnly: Bool {
        didSet { defaults.set(maskDomainOnly, forKey: maskDomainOnlyKey) }
    }

    @Published var showDowndetector: Bool {
        didSet { defaults.set(showDowndetector, forKey: showDowndetectorKey) }
    }

    /// When true, the inline Downdetector sparkline is always visible on the
    /// main view. When false (default), it only appears when there are problems.
    @Published var pinDowndetector: Bool {
        didSet { defaults.set(pinDowndetector, forKey: pinDowndetectorKey) }
    }

    @Published var ddBaselinePercent: Double {
        didSet { defaults.set(ddBaselinePercent, forKey: ddBaselinePercentKey) }
    }

    @Published var ddChartHours: Double {
        didSet { defaults.set(ddChartHours, forKey: ddChartHoursKey) }
    }

    @Published var showResetLabels: Bool {
        didSet { defaults.set(showResetLabels, forKey: showResetLabelsKey) }
    }

    /// Use 24-hour time format (default true).
    @Published var use24HourTime: Bool {
        didSet { defaults.set(use24HourTime, forKey: use24HourTimeKey) }
    }

    /// Show provider letter labels (O, A) next to bars in the menu bar icon.
    @Published var showProviderLabels: Bool {
        didSet { defaults.set(showProviderLabels, forKey: showProviderLabelsKey) }
    }

    /// Per-provider visibility in the tracker and menu bar icon.
    @Published var enabledProviders: [ProviderID: Bool] {
        didSet {
            var dict: [String: Bool] = [:]
            for (k, v) in enabledProviders { dict[k.rawValue] = v }
            defaults.set(dict, forKey: enabledProvidersKey)
        }
    }

    func isProviderEnabled(_ provider: ProviderID) -> Bool {
        enabledProviders[provider] ?? true
    }

    /// Show the colored alert dot on the menu bar icon.
    @Published var showAlertDot: Bool {
        didSet { defaults.set(showAlertDot, forKey: showAlertDotKey) }
    }

    /// Send macOS notifications when problems are detected or usage is low.
    @Published var sendNotifications: Bool {
        didSet { defaults.set(sendNotifications, forKey: sendNotificationsKey) }
    }

    @Published private(set) var appBackgroundColor: NSColor

    private let defaults = UserDefaults.standard
    private let storageKey = "providerColors"
    private let dismissKey = "dismissOnMouseExit"
    private let colorizeIconKey = "colorizeStatusIcon"
    private let rememberViewKey = "rememberLastView"
    private let lastOpenViewKey = "lastOpenView"
    private let refreshIntervalKey = "refreshIntervalMinutes"
    private let maskSensitiveDataKey = "maskSensitiveData"
    private let maskPercentageKey = "maskPercentage"
    private let showSensitiveInfoKey = "showSensitiveInfo"
    private let maskDomainOnlyKey = "maskDomainOnly"
    private let showDowndetectorKey = "showDowndetector"
    private let pinDowndetectorKey = "pinDowndetector"
    private let ddBaselinePercentKey = "downdetectorBaselinePercent"
    private let ddChartHoursKey = "ddChartHours"
    private let showResetLabelsKey = "showResetLabels"
    private let use24HourTimeKey = "use24HourTime"
    private let showProviderLabelsKey = "showProviderLabels"
    private let enabledProvidersKey = "enabledProviders"
    private let showAlertDotKey = "showAlertDot"
    private let sendNotificationsKey = "sendNotifications"
    private let backgroundColorKey = "appBackgroundColor"

    init() {
        var colors: [ProviderID: NSColor] = [:]
        if let dict = defaults.dictionary(forKey: storageKey) as? [String: String] {
            for provider in ProviderID.allCases {
                if let hex = dict[provider.rawValue], let c = NSColor.fromHex(hex) {
                    colors[provider] = c
                } else {
                    colors[provider] = provider.defaultAccentColor
                }
            }
        } else {
            for provider in ProviderID.allCases {
                colors[provider] = provider.defaultAccentColor
            }
        }
        self.providerColors = colors
        self.dismissOnMouseExit = defaults.object(forKey: dismissKey) as? Bool ?? false
        self.colorizeStatusIcon = defaults.object(forKey: colorizeIconKey) as? Bool ?? true
        self.rememberLastView = defaults.object(forKey: rememberViewKey) as? Bool ?? true
        self.lastOpenView = defaults.string(forKey: lastOpenViewKey) ?? "main"
        self.refreshIntervalMinutes = defaults.object(forKey: refreshIntervalKey) as? Double ?? 5
        self.maskSensitiveData = defaults.object(forKey: maskSensitiveDataKey) as? Bool ?? false
        self.showSensitiveInfo = defaults.object(forKey: showSensitiveInfoKey) as? Bool ?? true
        self.maskPercentage = defaults.object(forKey: maskPercentageKey) as? Double ?? 0.6
        self.maskDomainOnly = defaults.object(forKey: maskDomainOnlyKey) as? Bool ?? false
        self.showDowndetector = defaults.object(forKey: showDowndetectorKey) as? Bool ?? true
        self.pinDowndetector = defaults.object(forKey: pinDowndetectorKey) as? Bool ?? false
        self.ddBaselinePercent = defaults.object(forKey: ddBaselinePercentKey) as? Double ?? 500
        self.ddChartHours = defaults.object(forKey: ddChartHoursKey) as? Double ?? 6
        self.showResetLabels = defaults.object(forKey: showResetLabelsKey) as? Bool ?? true
        self.use24HourTime = defaults.object(forKey: use24HourTimeKey) as? Bool ?? true
        self.showProviderLabels = defaults.object(forKey: showProviderLabelsKey) as? Bool ?? false
        var ep: [ProviderID: Bool] = [:]
        if let dict = defaults.dictionary(forKey: enabledProvidersKey) as? [String: Bool] {
            for p in ProviderID.allCases { ep[p] = dict[p.rawValue] ?? true }
        } else {
            for p in ProviderID.allCases { ep[p] = true }
        }
        self.enabledProviders = ep
        self.showAlertDot = defaults.object(forKey: showAlertDotKey) as? Bool ?? true
        self.sendNotifications = defaults.object(forKey: sendNotificationsKey) as? Bool ?? true
        self.appBackgroundColor = NSColor.fromHex(defaults.string(forKey: backgroundColorKey) ?? "") ?? NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1.0)
    }

    func color(for provider: ProviderID) -> NSColor {
        providerColors[provider] ?? provider.defaultAccentColor
    }

    func swiftUIColor(for provider: ProviderID) -> Color {
        Color(nsColor: color(for: provider))
    }

    func setColor(_ color: NSColor, for provider: ProviderID) {
        let normalized = color.toHex()
        if providerColors[provider]?.toHex() == normalized { return }
        providerColors[provider] = color
        save()
    }

    func resetToDefaults() {
        for provider in ProviderID.allCases {
            providerColors[provider] = provider.defaultAccentColor
            enabledProviders[provider] = true
        }
        appBackgroundColor = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1.0)
        defaults.set(appBackgroundColor.toHex(), forKey: backgroundColorKey)
        save()
        dismissOnMouseExit = true
        rememberLastView = false
        showResetLabels = true
        showProviderLabels = false
        use24HourTime = true
        refreshIntervalMinutes = 5
        colorizeStatusIcon = false
        maskSensitiveData = true
        maskPercentage = 1.0
        maskDomainOnly = false
        showSensitiveInfo = true
        showDowndetector = true
        pinDowndetector = false
        ddBaselinePercent = 500
        ddChartHours = 6
        showAlertDot = true
        sendNotifications = true
    }

    func setAppBackgroundColor(_ color: NSColor) {
        let normalized = color.toHex()
        if appBackgroundColor.toHex() == normalized { return }
        appBackgroundColor = color
        defaults.set(normalized, forKey: backgroundColorKey)
    }

    private func save() {
        var dict: [String: String] = [:]
        for (provider, color) in providerColors {
            dict[provider.rawValue] = color.toHex()
        }
        defaults.set(dict, forKey: storageKey)
    }

}

// MARK: - NSColor hex helpers

extension NSColor {
    func toHex() -> String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func fromHex(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let val = UInt64(s, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255
        let g = CGFloat((val >> 8) & 0xFF) / 255
        let b = CGFloat(val & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
