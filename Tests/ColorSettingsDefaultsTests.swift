import AppKit
import Foundation

@main
struct ColorSettingsDefaultsTests {
    static func main() {
        legacyPrivacySettingsMapToExplicitMode()
        providerColorCustomizationRoundTripsForOpenAIAndClaude()
        hiddenLegacySettingsDoNotLeakIntoSimplifiedUIDefaults()
        resetToDefaultsRestoresOpinionatedSettings()
    }

    @MainActor
    private static func legacyPrivacySettingsMapToExplicitMode() {
        let suiteName = "ColorSettingsDefaultsTests.PrivacyMode"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Expected test defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "showSensitiveInfo")
        var settings = ColorSettings(defaults: defaults)
        guard settings.privacyMode == .hidden else {
            fatalError("Expected hidden mode when showSensitiveInfo is false")
        }

        defaults.set(true, forKey: "showSensitiveInfo")
        defaults.set(false, forKey: "maskSensitiveData")
        settings = ColorSettings(defaults: defaults)
        guard settings.privacyMode == .visible else {
            fatalError("Expected visible mode when info is shown and masking is off")
        }

        defaults.set(true, forKey: "maskSensitiveData")
        settings = ColorSettings(defaults: defaults)
        guard settings.privacyMode == .masked else {
            fatalError("Expected masked mode when info is shown and masking is on")
        }
    }

    @MainActor
    private static func providerColorCustomizationRoundTripsForOpenAIAndClaude() {
        let suiteName = "ColorSettingsDefaultsTests.ProviderColors"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Expected test defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ColorSettings(defaults: defaults)
        let openAIColor = NSColor.systemPurple
        let claudeColor = NSColor.systemOrange

        settings.setColor(openAIColor, for: .chatgpt)
        settings.setColor(claudeColor, for: .claude)

        let reloaded = ColorSettings(defaults: defaults)

        guard reloaded.color(for: .chatgpt).toHex() == openAIColor.toHex() else {
            fatalError("Expected OpenAI color customization to persist")
        }
        guard reloaded.color(for: .claude).toHex() == claudeColor.toHex() else {
            fatalError("Expected Claude color customization to persist")
        }
    }

    @MainActor
    private static func hiddenLegacySettingsDoNotLeakIntoSimplifiedUIDefaults() {
        let suiteName = "ColorSettingsDefaultsTests.Legacy"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Expected test defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "dismissOnMouseExit")
        defaults.set(true, forKey: "rememberLastView")
        defaults.set("settings", forKey: "lastOpenView")
        defaults.set(false, forKey: "maskSensitiveData")
        defaults.set(0.15, forKey: "maskPercentage")
        defaults.set(true, forKey: "maskDomainOnly")
        defaults.set(true, forKey: "pinDowndetector")
        defaults.set(3000.0, forKey: "downdetectorBaselinePercent")
        defaults.set(24.0, forKey: "ddChartHours")

        let settings = ColorSettings(defaults: defaults)

        guard settings.dismissOnMouseExit else {
            fatalError("Expected simplified defaults to force hide-on-exit on")
        }
        guard !settings.rememberLastView, settings.lastOpenView == "main" else {
            fatalError("Expected simplified defaults to force the main view as startup state")
        }
        guard !settings.maskSensitiveData, settings.maskPercentage == 0.6, !settings.maskDomainOnly else {
            fatalError("Expected simplified defaults to force visible account info behavior")
        }
        guard !settings.pinDowndetector, settings.ddBaselinePercent == 2000, settings.ddChartHours == 6 else {
            fatalError("Expected simplified defaults to ignore legacy Downdetector tuning")
        }
    }

    @MainActor
    private static func resetToDefaultsRestoresOpinionatedSettings() {
        let suiteName = "ColorSettingsDefaultsTests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Expected test defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ColorSettings(defaults: defaults)
        settings.lastOpenView = "settings"
        settings.refreshIntervalMinutes = 17
        settings.showSensitiveInfo = false
        settings.maskSensitiveData = false
        settings.maskPercentage = 0.15
        settings.showDowndetector = false
        settings.sendNotifications = false
        settings.showAlertDot = false
        settings.colorizeStatusIcon = false
        settings.ddBaselinePercent = 3000
        settings.ddChartHours = 24
        settings.pinDowndetector = true
        settings.setAppBackgroundColor(NSColor.black)
        settings.setColor(NSColor.systemBlue, for: ProviderID.chatgpt)
        settings.enabledProviders[ProviderID.claude] = false

        settings.resetToDefaults()

        guard settings.lastOpenView == "main" else {
            fatalError("Expected reset to return the popover to the main view")
        }
        guard settings.refreshIntervalMinutes == 5 else {
            fatalError("Expected reset to restore a 5 minute refresh interval")
        }
        guard settings.showSensitiveInfo else {
            fatalError("Expected reset to show sensitive info by default")
        }
        guard !settings.maskSensitiveData else {
            fatalError("Expected reset to restore visible account info")
        }
        guard settings.maskPercentage == 0.6 else {
            fatalError("Expected reset to restore the default email masking amount")
        }
        guard settings.showDowndetector else {
            fatalError("Expected reset to enable Downdetector")
        }
        guard settings.sendNotifications else {
            fatalError("Expected reset to enable notifications")
        }
        guard settings.showAlertDot else {
            fatalError("Expected reset to enable the alert dot")
        }
        guard settings.colorizeStatusIcon else {
            fatalError("Expected reset to restore the default colored status icon")
        }
        guard settings.ddBaselinePercent == 2000 else {
            fatalError("Expected reset to restore the automatic Downdetector baseline")
        }
        guard settings.ddChartHours == 6 else {
            fatalError("Expected reset to restore the default Downdetector chart range")
        }
        guard !settings.pinDowndetector else {
            fatalError("Expected reset to disable pinned Downdetector status")
        }
        guard settings.enabledProviders.values.allSatisfy({ $0 }) else {
            fatalError("Expected reset to re-enable all providers")
        }
        guard settings.color(for: ProviderID.chatgpt).toHex() == ProviderID.chatgpt.defaultAccentColor.toHex() else {
            fatalError("Expected reset to restore the provider accent colors")
        }
        guard settings.appBackgroundColor.toHex() == NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1.0).toHex() else {
            fatalError("Expected reset to restore the app background color")
        }
    }
}
