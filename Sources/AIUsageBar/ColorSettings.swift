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

    /// Per-provider recency minutes. Only treat Downdetector as "problems"
    /// if elevated reports occurred within the last N minutes for that provider.
    @Published var ddRecencyByProvider: [ProviderID: Double] {
        didSet { saveProviderDoubles(ddRecencyByProvider, key: ddRecencyByProviderKey) }
    }

    /// Per-provider baseline percentage. Minimum percentage of baseline that
    /// reports must reach to count as a problem for that provider.
    @Published var ddBaselineByProvider: [ProviderID: Double] {
        didSet { saveProviderDoubles(ddBaselineByProvider, key: ddBaselineByProviderKey) }
    }

    /// Per-provider chart time range in hours (how far back to show).
    @Published var ddChartHoursByProvider: [ProviderID: Double] {
        didSet { saveProviderDoubles(ddChartHoursByProvider, key: ddChartHoursKey) }
    }

    func recencyMinutes(for provider: ProviderID) -> Double {
        ddRecencyByProvider[provider] ?? 30
    }

    func baselinePercent(for provider: ProviderID) -> Double {
        ddBaselineByProvider[provider] ?? 200
    }

    func setRecencyMinutes(_ value: Double, for provider: ProviderID) {
        ddRecencyByProvider[provider] = value
    }

    func setBaselinePercent(_ value: Double, for provider: ProviderID) {
        ddBaselineByProvider[provider] = value
    }

    func chartHours(for provider: ProviderID) -> Double {
        ddChartHoursByProvider[provider] ?? 24
    }

    func setChartHours(_ value: Double, for provider: ProviderID) {
        ddChartHoursByProvider[provider] = value
    }

    @Published var showResetLabels: Bool {
        didSet { defaults.set(showResetLabels, forKey: showResetLabelsKey) }
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
    private let ddRecencyKey = "downdetectorRecencyMinutes" // legacy
    private let ddBaselinePercentKey = "downdetectorBaselinePercent" // legacy
    private let ddRecencyByProviderKey = "ddRecencyByProvider"
    private let ddBaselineByProviderKey = "ddBaselineByProvider"
    private let ddChartHoursKey = "ddChartHoursByProvider"
    private let showResetLabelsKey = "showResetLabels"
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
        // Per-provider Downdetector settings (migrate from legacy globals)
        let legacyRecency = defaults.object(forKey: ddRecencyKey) as? Double ?? 30
        let legacyBaseline = defaults.object(forKey: ddBaselinePercentKey) as? Double ?? 200
        self.ddRecencyByProvider = Self.loadProviderDoubles(from: defaults, key: ddRecencyByProviderKey, fallback: legacyRecency)
        self.ddBaselineByProvider = Self.loadProviderDoubles(from: defaults, key: ddBaselineByProviderKey, fallback: legacyBaseline)
        self.ddChartHoursByProvider = Self.loadProviderDoubles(from: defaults, key: ddChartHoursKey, fallback: 24)
        self.showResetLabels = defaults.object(forKey: showResetLabelsKey) as? Bool ?? true
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
        }
        appBackgroundColor = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1.0)
        defaults.set(appBackgroundColor.toHex(), forKey: backgroundColorKey)
        save()
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

    // MARK: - Per-provider double helpers

    private static func loadProviderDoubles(from defaults: UserDefaults, key: String, fallback: Double) -> [ProviderID: Double] {
        var result: [ProviderID: Double] = [:]
        if let dict = defaults.dictionary(forKey: key) as? [String: Double] {
            for provider in ProviderID.allCases {
                result[provider] = dict[provider.rawValue] ?? fallback
            }
        } else {
            for provider in ProviderID.allCases {
                result[provider] = fallback
            }
        }
        return result
    }

    private func saveProviderDoubles(_ values: [ProviderID: Double], key: String) {
        var dict: [String: Double] = [:]
        for (provider, val) in values {
            dict[provider.rawValue] = val
        }
        defaults.set(dict, forKey: key)
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
