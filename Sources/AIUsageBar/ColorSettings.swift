import AppKit
import SwiftUI

@MainActor
final class ColorSettings: ObservableObject {
    static let shared = ColorSettings()

    @Published private(set) var providerColors: [ProviderID: NSColor]

    @Published var dismissOnMouseExit: Bool {
        didSet { defaults.set(dismissOnMouseExit, forKey: dismissKey) }
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "providerColors"
    private let dismissKey = "dismissOnMouseExit"

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
        save()
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
