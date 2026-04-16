import AppKit
import SwiftUI

private struct PopoverContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PopoverView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var colorSettings: ColorSettings
    @EnvironmentObject private var popoverController: PopoverController
    @State private var now = Date()
    @State private var dismissWork: DispatchWorkItem?
    @State private var measuredContentHeight: CGFloat = 0
    private var showSettings: Bool {
        get { popoverController.showSettings }
        nonmutating set {
            popoverController.showSettings = newValue
            if newValue { popoverController.showDowndetector = false }
        }
    }
    private var showDowndetector: Bool {
        get { popoverController.showDowndetector }
        nonmutating set {
            popoverController.showDowndetector = newValue
            if newValue { popoverController.showSettings = false }
        }
    }
    private var isSubView: Bool { showSettings || showDowndetector }
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentViewName: String {
        if showSettings { return "settings" }
        if showDowndetector { return "downdetector" }
        return "main"
    }

    private func goHome() {
        showSettings = false
        showDowndetector = false
    }

    private var popoverWidth: CGFloat {
        if showSettings { return 360 }
        if showDowndetector { return 360 }
        return 310
    }

    private var maxContentHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        // Leave room for the menu bar anchor, header, footer, and shadow.
        return max(300, visible - 160)
    }

    private var preferredPopoverHeight: CGFloat {
        // Header, dividers, footer, outer padding.
        let chromeHeight: CGFloat = 86
        return chromeHeight + min(maxContentHeight, measuredContentHeight)
    }

    @ViewBuilder
    private var contentBody: some View {
        if showSettings {
            ColorSettingsView()
                .environmentObject(colorSettings)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .id("settings")
        } else if showDowndetector {
            DowndetectorTabView()
                .environmentObject(store)
                .environmentObject(colorSettings)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .id("downdetector")
        } else {
            VStack(spacing: 0) {
                let visibleCards = store.cards.filter { colorSettings.isProviderEnabled($0.id) }
                ForEach(visibleCards) { card in
                    ProviderCardView(card: card, color: colorSettings.swiftUIColor(for: card.id), signInAction: {
                        store.signIn(to: card.id)
                    }, signOutAction: {
                        Task { await store.signOut(from: card.id) }
                    })
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if card.id != visibleCards.last?.id {
                        Divider().opacity(0.2).padding(.horizontal, 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("main")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            ScrollView(.vertical, showsIndicators: true) {
                contentBody
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: PopoverContentHeightKey.self, value: proxy.size.height)
                        }
                    )
                    
            }
            .frame(maxHeight: maxContentHeight)

            Divider().opacity(0.3)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .padding(.vertical, 4)
        .frame(width: popoverWidth)
        .background(Color(nsColor: colorSettings.appBackgroundColor))
        .onAppear {
            popoverController.preferredSize = CGSize(width: popoverWidth, height: preferredPopoverHeight)
            if colorSettings.rememberLastView {
                switch colorSettings.lastOpenView {
                case "settings": showSettings = true
                case "downdetector": showDowndetector = true
                default: break
                }
            }
        }
        .onReceive(timer) { self.now = $0 }
        .onPreferenceChange(PopoverContentHeightKey.self) { newValue in
            let delta = abs(newValue - measuredContentHeight)
            guard delta > 5 else { return }
            measuredContentHeight = newValue
            popoverController.preferredSize = CGSize(width: popoverWidth, height: preferredPopoverHeight)
        }
        .onChange(of: popoverController.showSettings) {
            popoverController.preferredSize = CGSize(width: popoverWidth, height: preferredPopoverHeight)
            if colorSettings.rememberLastView {
                colorSettings.lastOpenView = currentViewName
            }
        }
        .onChange(of: popoverController.showDowndetector) {
            popoverController.preferredSize = CGSize(width: popoverWidth, height: preferredPopoverHeight)
            if colorSettings.rememberLastView {
                colorSettings.lastOpenView = currentViewName
            }
        }
        .onChange(of: colorSettings.rememberLastView) {
            if !colorSettings.rememberLastView {
                goHome()
                colorSettings.lastOpenView = "main"
            }
        }
        .onChange(of: popoverController.closeCount) {
            if !colorSettings.rememberLastView {
                goHome()
                colorSettings.lastOpenView = "main"
            }
        }
        .onDisappear {
            if !colorSettings.rememberLastView {
                goHome()
                colorSettings.lastOpenView = "main"
            }
        }
        .onHover { hovering in
            guard colorSettings.dismissOnMouseExit else { return }
            if hovering {
                dismissWork?.cancel()
                dismissWork = nil
            } else {
                let work = DispatchWorkItem {
                    popoverController.dismiss()
                }
                dismissWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        }
    }

    private var header: some View {
        HStack {
            if isSubView {
                Button {
                    goHome()
                } label: {
                    HStack(spacing: 4) {
                        Text("Bitstraum Usage")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(showSettings ? "Settings" : "Downdetector")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text("Bitstraum Usage")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            if colorSettings.showDowndetector {
                Button {
                    if showDowndetector { goHome() } else { showDowndetector = true }
                } label: {
                    Image(systemName: showDowndetector ? "xmark" : "chart.bar.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderless)
            }

            Button {
                if showSettings { goHome() } else { showSettings = true }
            } label: {
                Image(systemName: showSettings ? "xmark" : "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)

            Button {
                Task { await store.refreshAll() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var footer: some View {
        HStack {
            Text(lastUpdatedText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var lastUpdatedText: String {
        guard let d = store.lastRefresh else { return "Not refreshed yet" }
        let seconds = Int(now.timeIntervalSince(d))
        if seconds < 5 { return "Last updated just now" }
        if seconds < 60 { return "Last updated \(seconds) seconds ago" }
        let minutes = seconds / 60
        if minutes == 1 { return "Last updated 1 minute ago" }
        return "Last updated \(minutes) minutes ago"
    }
}

// MARK: - Provider section

struct ProviderCardView: View {
    let card: ProviderUsageCard
    let color: Color
    let signInAction: () -> Void
    let signOutAction: () -> Void
    @EnvironmentObject private var colorSettings: ColorSettings
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(card.id.title)
                    .font(.system(size: 13, weight: .semibold))

                Text(card.planName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                if card.state == .unauthenticated || card.state == .error {
                    Button("Sign In") { signInAction() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                } else {
                    statusLabel
                }
            }

            if colorSettings.showSensitiveInfo, let email = card.email {
                Text(displayEmail(email))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if card.limits.isEmpty && card.state != .unauthenticated {
                if card.state == .loading {
                    Text("Fetching usage data...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if card.state == .ready && card.statusMessage.contains("Sign in") {
                    Button(card.statusMessage) { signInAction() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(color)
                } else if card.state == .ready {
                    Text(card.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            ForEach(card.limits) { limit in
                LimitRowView(limit: limit, color: color)
            }

            // Downdetector status: show when pinned, or auto-show on recent problems
            if colorSettings.showDowndetector, let report = store.downdetectorData[card.id],
               colorSettings.pinDowndetector || report.effectiveStatus(recencyMinutes: colorSettings.recencyMinutes(for: card.id), baselinePercent: colorSettings.baselinePercent(for: card.id)).hasProblems {
                DowndetectorStatusView(report: report, providerSlug: card.id.downdetectorSlug ?? "", recencyMinutes: colorSettings.recencyMinutes(for: card.id), baselinePercent: colorSettings.baselinePercent(for: card.id), chartHours: colorSettings.chartHours(for: card.id), use24HourTime: colorSettings.use24HourTime)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch card.state {
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
        case .ready:
            Button("Sign Out") { signOutAction() }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private func displayEmail(_ email: String) -> String {
        guard colorSettings.maskSensitiveData else { return email }
        return maskEmail(email, percentage: colorSettings.maskPercentage, domainOnly: colorSettings.maskDomainOnly)
    }
}

// MARK: - Limit row

struct LimitRowView: View {
    let limit: UsageLimit
    let color: Color
    @EnvironmentObject private var colorSettings: ColorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(limit.label)
                    .font(.system(size: 11, weight: .medium))

                Spacer()

                if let f = limit.fraction {
                    Text("\(Int((f * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if let f = limit.fraction {
                        Capsule()
                            .fill(color)
                            .frame(width: max(geo.size.width * f.bounded(to: 0...1), 4))
                    }
                }
            }
            .frame(height: 5)

            if colorSettings.showResetLabels, let reset = limit.resetLabel, !reset.isEmpty {
                Text(reset)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Color settings

enum ExpandedPicker: Equatable {
    case background
    case provider(ProviderID)
}

struct ColorSettingsView: View {
    @EnvironmentObject private var colorSettings: ColorSettings
    @EnvironmentObject private var store: UsageStore
    @State private var expandedPicker: ExpandedPicker?

    private var sampleEmail: String {
        store.cards.compactMap(\.email).first ?? "name@example.com"
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            content()
        }
        .padding(.vertical, 2)
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.vertical, 1)
    }

    private var previewEmailText: String {
        guard colorSettings.showSensitiveInfo else { return "Hidden" }
        return colorSettings.maskSensitiveData ? maskEmail(sampleEmail, percentage: colorSettings.maskPercentage, domainOnly: colorSettings.maskDomainOnly) : sampleEmail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bar Colors")
                .font(.system(size: 12, weight: .semibold))

            BackgroundColorRow(expandedPicker: $expandedPicker)

            ForEach(ProviderID.allCases) { provider in
                HexColorRow(provider: provider, expandedPicker: $expandedPicker)
            }

            // MARK: Providers
            settingsSection("Providers") {
                let enabledCount = colorSettings.enabledProviders.filter(\.value).count
                ForEach(ProviderID.allCases) { provider in
                    let isLast = enabledCount <= 1 && colorSettings.isProviderEnabled(provider)
                    settingsToggle(provider.title, isOn: Binding(
                        get: { colorSettings.isProviderEnabled(provider) },
                        set: { colorSettings.enabledProviders[provider] = $0 }
                    ))
                    .disabled(isLast)
                }
                if enabledCount <= 1 {
                    Text("At least one provider must be enabled")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // MARK: General
            settingsSection("General") {
                settingsToggle("Hide on mouse exit", isOn: $colorSettings.dismissOnMouseExit)
                settingsToggle("Remember last open view", isOn: $colorSettings.rememberLastView)
                settingsToggle("Show reset labels", isOn: $colorSettings.showResetLabels)
                settingsToggle("Provider labels in menu bar", isOn: $colorSettings.showProviderLabels)
                settingsToggle("24-hour time format", isOn: $colorSettings.use24HourTime)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Refresh interval")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(Int(colorSettings.refreshIntervalMinutes.rounded())) min")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $colorSettings.refreshIntervalMinutes, in: 1...30, step: 1)
                        .controlSize(.mini)
                }
            }

            // MARK: Notifications
            settingsSection("Alerts") {
                settingsToggle("Alert dot on menu bar", isOn: $colorSettings.showAlertDot)
                settingsToggle("Send notifications", isOn: $colorSettings.sendNotifications)
            }

            // MARK: Privacy
            settingsSection("Privacy") {
                settingsToggle("Show emails / sensitive info", isOn: $colorSettings.showSensitiveInfo)
                settingsToggle("Mask emails", isOn: $colorSettings.maskSensitiveData)

                if colorSettings.maskSensitiveData {
                    settingsToggle("Only mask domain after @", isOn: $colorSettings.maskDomainOnly)
                        .disabled(!colorSettings.showSensitiveInfo)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Mask amount")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(Int((colorSettings.maskPercentage * 100).rounded()))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $colorSettings.maskPercentage, in: 0...1, step: 0.05)
                            .controlSize(.mini)
                            .disabled(!colorSettings.showSensitiveInfo)
                        HStack(spacing: 6) {
                            Text("Preview")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(previewEmailText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            // MARK: Downdetector
            settingsSection("Downdetector") {
                settingsToggle("Show Downdetector status", isOn: $colorSettings.showDowndetector)
                settingsToggle("Always show on main view", isOn: $colorSettings.pinDowndetector)
                    .disabled(!colorSettings.showDowndetector)

                ForEach(ProviderID.allCases) { provider in
                    DowndetectorProviderSettings(
                        provider: provider,
                        colorSettings: colorSettings,
                        baseline: store.downdetectorData[provider]?.dataPoints.last?.baseline
                    )
                }
                .disabled(!colorSettings.showDowndetector)
            }

            HStack {
                Button("Quit Bitstraum Usage") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.red.opacity(0.7))

                Spacer()

                Button("Reset to Defaults") {
                    colorSettings.resetToDefaults()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct HexColorRow: View {
    let provider: ProviderID
    @Binding var expandedPicker: ExpandedPicker?
    @EnvironmentObject private var colorSettings: ColorSettings
    @State private var hexText = ""
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 1
    @State private var isInteracting = false
    @State private var isSyncingHexFromPreview = false

    private var isExpanded: Bool { expandedPicker == .provider(provider) }
    private var previewColor: NSColor {
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }

    private func toggleExpanded() {
        expandedPicker = isExpanded ? nil : .provider(provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleExpanded()
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: previewColor))
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        )

                    Text(provider.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text("#\(hexText)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    CircularColorPicker(
                        hue: $hue,
                        saturation: $saturation,
                        brightness: 1,
                        onInteractionChanged: handleInteraction
                    )
                        .frame(width: 190, height: 190)

                    HStack(spacing: 6) {
                        Text("Hex")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        HStack(spacing: 2) {
                            Text("#")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)

                            HexTextField(text: $hexText)
                                .frame(width: 64, height: 16)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                    }

                    BrightnessSliderRow(value: $brightness, hue: hue, saturation: saturation, onEditingChanged: handleInteraction)
                }
                .padding(.leading, 28)
            }
        }
        .onAppear { syncFromSettings() }
        .onChange(of: colorSettings.providerColors) {
            if !isInteracting { syncFromSettings() }
        }
        .onChange(of: hexText) {
            if isSyncingHexFromPreview {
                isSyncingHexFromPreview = false
                return
            }
            let filtered = String(hexText.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(6))
            if filtered != hexText {
                hexText = filtered
                return
            }
            guard filtered.count == 6, let color = NSColor.fromHex(filtered) else { return }
            apply(color)
        }
        .onChange(of: hue) { if !isInteracting { syncHexFromPreview() } }
        .onChange(of: saturation) { if !isInteracting { syncHexFromPreview() } }
        .onChange(of: brightness) { if !isInteracting { syncHexFromPreview() } }
    }

    private func syncFromSettings() {
        let color = colorSettings.color(for: provider).hsbComponents
        hue = color.hue
        saturation = color.saturation
        brightness = color.brightness
        isSyncingHexFromPreview = true
        hexText = colorSettings.color(for: provider).toHex().replacingOccurrences(of: "#", with: "")
    }

    private func apply(_ color: NSColor) {
        colorSettings.setColor(color, for: provider)
        let components = color.hsbComponents
        hue = components.hue
        saturation = components.saturation
        brightness = components.brightness
        let nextHex = color.toHex().replacingOccurrences(of: "#", with: "")
        if hexText != nextHex {
            hexText = nextHex
        }
    }

    private func syncHexFromPreview() {
        let nextHex = previewColor.toHex().replacingOccurrences(of: "#", with: "")
        if hexText != nextHex {
            isSyncingHexFromPreview = true
            hexText = nextHex
        }
    }

    private func handleInteraction(_ editing: Bool) {
        isInteracting = editing
        if !editing {
            syncHexFromPreview()
            colorSettings.setColor(previewColor, for: provider)
        }
    }
}

struct BackgroundColorRow: View {
    @Binding var expandedPicker: ExpandedPicker?
    @EnvironmentObject private var colorSettings: ColorSettings
    @State private var hexText = ""
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 1
    @State private var isInteracting = false
    @State private var isSyncingHexFromPreview = false

    private var previewColor: NSColor {
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }

    private var isExpanded: Bool {
        expandedPicker == .background
    }

    private func toggleExpanded() {
        expandedPicker = isExpanded ? nil : .background
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleExpanded()
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: previewColor))
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        )

                    Text("Background")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text("#\(hexText)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    CircularColorPicker(hue: $hue, saturation: $saturation, brightness: 1, onInteractionChanged: handleInteraction)
                        .frame(width: 190, height: 190)

                    HStack(spacing: 6) {
                        Text("Hex")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        HStack(spacing: 2) {
                            Text("#")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)

                            HexTextField(text: $hexText)
                                .frame(width: 64, height: 16)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                    }

                    BrightnessSliderRow(value: $brightness, hue: hue, saturation: saturation, onEditingChanged: handleInteraction)
                }
                .padding(.leading, 28)
            }
        }
        .onAppear { syncFromSettings() }
        .onChange(of: colorSettings.appBackgroundColor) {
            if !isInteracting { syncFromSettings() }
        }
        .onChange(of: hexText) {
            if isSyncingHexFromPreview {
                isSyncingHexFromPreview = false
                return
            }
            let filtered = String(hexText.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(6))
            if filtered != hexText {
                hexText = filtered
                return
            }
            guard filtered.count == 6, let color = NSColor.fromHex(filtered) else { return }
            apply(color)
        }
        .onChange(of: hue) { if !isInteracting { syncHexFromPreview() } }
        .onChange(of: saturation) { if !isInteracting { syncHexFromPreview() } }
        .onChange(of: brightness) { if !isInteracting { syncHexFromPreview() } }
    }

    private func syncFromSettings() {
        let color = colorSettings.appBackgroundColor.hsbComponents
        hue = color.hue
        saturation = color.saturation
        brightness = color.brightness
        isSyncingHexFromPreview = true
        hexText = colorSettings.appBackgroundColor.toHex().replacingOccurrences(of: "#", with: "")
    }

    private func apply(_ color: NSColor) {
        colorSettings.setAppBackgroundColor(color)
        let components = color.hsbComponents
        hue = components.hue
        saturation = components.saturation
        brightness = components.brightness
        let nextHex = color.toHex().replacingOccurrences(of: "#", with: "")
        if hexText != nextHex { hexText = nextHex }
    }

    private func syncHexFromPreview() {
        let nextHex = previewColor.toHex().replacingOccurrences(of: "#", with: "")
        if hexText != nextHex {
            isSyncingHexFromPreview = true
            hexText = nextHex
        }
    }

    private func handleInteraction(_ editing: Bool) {
        isInteracting = editing
        if !editing {
            syncHexFromPreview()
            colorSettings.setAppBackgroundColor(previewColor)
        }
    }
}

struct CircularColorPicker: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    let brightness: Double
    let onInteractionChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let indicator = point(for: center, radius: radius)

            ZStack {
                Image(nsImage: ColorWheelImageCache.image(diameter: Int(size), brightness: brightness))
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: size, height: size)

                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .position(indicator)
                    .shadow(color: .black.opacity(0.35), radius: 2)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onInteractionChanged(true) }
                    .onChanged { value in
                        updateSelection(at: value.location, center: center, radius: radius)
                    }
                    .onEnded { _ in onInteractionChanged(false) }
            )
        }
    }

    private func point(for center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (hue * .pi * 2) - (.pi / 2)
        let distance = saturation * radius
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * distance,
            y: center.y + CGFloat(sin(angle)) * distance
        )
    }

    private func updateSelection(at location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = min(sqrt(dx * dx + dy * dy), radius)
        let angle = atan2(dy, dx) + (.pi / 2)
        let normalizedHue = angle < 0 ? angle + (.pi * 2) : angle
        hue = normalizedHue / (.pi * 2)
        saturation = distance / radius
    }
}

struct BrightnessSliderRow: View {
    @Binding var value: Double
    let hue: Double
    let saturation: Double
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Brightness")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            CustomBrightnessSlider(value: $value, hue: hue, saturation: saturation, onEditingChanged: onEditingChanged)
                .frame(height: 22)
        }
    }
}

struct CustomBrightnessSlider: View {
    @Binding var value: Double
    let hue: Double
    let saturation: Double
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let knobSize: CGFloat = 18
            let usableWidth = max(geo.size.width - knobSize, 1)
            let knobX = knobSize / 2 + usableWidth * value

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black,
                                Color(nsColor: NSColor(calibratedHue: hue, saturation: saturation, brightness: 1.0, alpha: 1.0))
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)

                Circle()
                    .fill(Color(nsColor: NSColor(calibratedHue: hue, saturation: saturation, brightness: max(value, 0.05), alpha: 1.0)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                    .frame(width: knobSize, height: knobSize)
                    .position(x: knobX, y: geo.size.height / 2)
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onEditingChanged(true)
                        let x = min(max(gesture.location.x - knobSize / 2, 0), usableWidth)
                        value = x / usableWidth
                    }
                    .onEnded { _ in
                        onEditingChanged(false)
                    }
            )
        }
    }
}

enum ColorWheelImageCache {
    private static var images: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func image(diameter: Int, brightness: Double) -> NSImage {
        let scale = max(2, Int((NSScreen.main?.backingScaleFactor ?? 2).rounded()) * 2)
        let pixelDiameter = diameter * scale
        let key = "\(pixelDiameter)-\(Int((brightness * 1000).rounded()))"
        lock.lock()
        if let cached = images[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelDiameter,
            pixelsHigh: pixelDiameter,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let radius = Double(pixelDiameter) / 2
        let center = radius
        for y in 0..<pixelDiameter {
            for x in 0..<pixelDiameter {
                let dx = Double(x) + 0.5 - center
                let dy = Double(y) + 0.5 - center
                let distance = sqrt(dx * dx + dy * dy)
                if distance > radius + 1 {
                    rep.setColor(.clear, atX: x, y: y)
                    continue
                }

                let saturation = distance / radius
                var angle = atan2(dy, dx) + (.pi / 2)
                if angle < 0 { angle += .pi * 2 }
                let hue = angle / (.pi * 2)
                let alpha = max(0, min(1, radius + 0.5 - distance))
                let color = NSColor(calibratedHue: hue, saturation: min(saturation, 1), brightness: brightness, alpha: alpha)
                rep.setColor(color, atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.addRepresentation(rep)
        lock.lock()
        images[key] = image
        lock.unlock()
        return image
    }
}

struct HexTextField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.textColor = .white
        field.placeholderString = "FFFFFF"
        field.alignment = .left
        field.delegate = context.coordinator
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

// MARK: - Downdetector per-provider settings

struct DowndetectorProviderSettings: View {
    let provider: ProviderID
    @ObservedObject var colorSettings: ColorSettings
    let baseline: Int?

    @State private var isExpanded = false

    private var recencyBinding: Binding<Double> {
        Binding(
            get: { colorSettings.recencyMinutes(for: provider) },
            set: { colorSettings.setRecencyMinutes($0, for: provider) }
        )
    }

    private var baselineBinding: Binding<Double> {
        Binding(
            get: { colorSettings.baselinePercent(for: provider) },
            set: { colorSettings.setBaselinePercent($0, for: provider) }
        )
    }

    private var chartHoursBinding: Binding<Double> {
        Binding(
            get: { colorSettings.chartHours(for: provider) },
            set: { colorSettings.setChartHours($0, for: provider) }
        )
    }

    private var thresholdReports: String {
        guard let b = baseline, b > 0 else { return "" }
        let pct = colorSettings.baselinePercent(for: provider)
        let reports = Int((Double(b) * pct / 100).rounded())
        return "≈ \(reports) reports"
    }

    private var chartHoursLabel: String {
        let h = Int(colorSettings.chartHours(for: provider))
        return h == 24 ? "24h" : "\(h)h"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable header
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Text(provider.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Chart range")
                            .font(.system(size: 11))
                        Spacer()
                        Text(chartHoursLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    Slider(value: chartHoursBinding, in: 1...24, step: 1)
                        .controlSize(.mini)

                    HStack {
                        Text("Recency")
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(Int(colorSettings.recencyMinutes(for: provider))) min")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    Slider(value: recencyBinding, in: 15...240, step: 15)
                        .controlSize(.mini)

                    HStack {
                        Text("Baseline")
                            .font(.system(size: 11))
                        Spacer()
                        Text(thresholdReports)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .trailing)
                        Text("\(Int(colorSettings.baselinePercent(for: provider)))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                    Slider(value: baselineBinding, in: 50...2000, step: 50)
                        .controlSize(.mini)
                }
                .padding(.top, 4)
                .padding(.leading, 14)
            }
        }
    }
}

// MARK: - Downdetector tab

struct DowndetectorTabView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var colorSettings: ColorSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(ProviderID.allCases) { provider in
                    if let report = store.downdetectorData[provider] {
                        DowndetectorProviderSection(
                            provider: provider,
                            report: report,
                            color: colorSettings.swiftUIColor(for: provider),
                            recencyMinutes: colorSettings.recencyMinutes(for: provider),
                            baselinePercent: colorSettings.baselinePercent(for: provider),
                            chartHours: colorSettings.chartHours(for: provider),
                            use24HourTime: colorSettings.use24HourTime
                        )
                        .padding(.vertical, 8)

                        if provider != ProviderID.allCases.last {
                            Divider().opacity(0.2)
                        }
                    }
                }

                if store.downdetectorData.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No data yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Downdetector status will appear after the next refresh.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .frame(maxHeight: 500)
    }
}

struct DowndetectorProviderSection: View {
    let provider: ProviderID
    let report: DowndetectorReport
    let color: Color
    let recencyMinutes: Double
    var baselinePercent: Double = 200
    var chartHours: Double = 24
    var use24HourTime: Bool = true

    @State private var hoveredIndex: Int? = nil

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24HourTime ? "MMM d, HH:mm" : "MMM d, h:mm a"
        return f.string(from: date)
    }

    private var filteredDataPoints: [DowndetectorDataPoint] {
        guard chartHours < 24 else { return report.dataPoints }
        let cutoff = Date().addingTimeInterval(-chartHours * 3600)
        return report.dataPoints.filter { $0.timestamp >= cutoff }
    }

    private var filteredMax: Int {
        guard chartHours < 24 else { return report.reportsMax }
        let localMax = filteredDataPoints.map(\.reports).max() ?? 0
        return max(localMax, 1)
    }

    private var effectiveStatus: DowndetectorStatusLevel {
        report.effectiveStatus(recencyMinutes: recencyMinutes, baselinePercent: baselinePercent)
    }

    private var statusColor: Color {
        switch effectiveStatus {
        case .success: return .green
        case .warning: return .orange
        case .danger: return .red
        case .unknown: return .gray
        }
    }

    private var chartLabel: String {
        let h = Int(chartHours)
        return h == 24 ? "24h report history" : "\(h)h report history"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: provider name + status
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(provider.title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(effectiveStatus.label)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
            }

            // Sparkline chart
            VStack(alignment: .leading, spacing: 2) {
                SparklineChart(
                    dataPoints: filteredDataPoints,
                    maxReports: filteredMax,
                    color: statusColor,
                    hoveredIndex: $hoveredIndex
                )
                .frame(height: 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let slug = provider.downdetectorSlug,
                       let url = URL(string: "https://downdetector.com/status/\(slug)/") {
                        NSWorkspace.shared.open(url)
                    }
                }

                // Info row: shows hover data when hovering, default stats otherwise
                HStack {
                    if let idx = hoveredIndex, idx < filteredDataPoints.count {
                        let point = filteredDataPoints[idx]
                        Text(formatTime(point.timestamp))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Baseline: \(point.baseline)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("Reports: \(formatReportCount(point.reports))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(statusColor)
                    } else {
                        Text(chartLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if let latest = report.dataPoints.last {
                            Text("Baseline: \(latest.baseline)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text("Now: \(formatReportCount(latest.reports))")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        Text("Peak: \(formatReportCount(filteredMax))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Indicator rings — "Most reported problems"
            if !report.indicators.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Most reported problems")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    let topIndicators = Array(report.indicators.prefix(4))
                    HStack(spacing: 0) {
                        ForEach(0..<topIndicators.count, id: \.self) { i in
                            IndicatorRingView(
                                indicator: topIndicators[i],
                                color: statusColor
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func formatReportCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

struct IndicatorRingView: View {
    let indicator: DowndetectorIndicator
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Track
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 5)

                // Fill arc
                Circle()
                    .trim(from: 0, to: indicator.percentage / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Percentage label
                Text("\(Int(indicator.percentage.rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 52, height: 52)

            Text(indicator.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Downdetector inline status (provider cards)

struct DowndetectorStatusView: View {
    let report: DowndetectorReport
    let providerSlug: String
    let recencyMinutes: Double
    var baselinePercent: Double = 200
    var chartHours: Double = 24
    var use24HourTime: Bool = true

    @State private var hoveredIndex: Int? = nil

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24HourTime ? "MMM d, HH:mm" : "MMM d, h:mm a"
        return f.string(from: date)
    }

    private var filteredDataPoints: [DowndetectorDataPoint] {
        guard chartHours < 24 else { return report.dataPoints }
        let cutoff = Date().addingTimeInterval(-chartHours * 3600)
        return report.dataPoints.filter { $0.timestamp >= cutoff }
    }

    private var filteredMax: Int {
        guard chartHours < 24 else { return report.reportsMax }
        let localMax = filteredDataPoints.map(\.reports).max() ?? 0
        return max(localMax, 1)
    }

    private var effectiveStatus: DowndetectorStatusLevel {
        report.effectiveStatus(recencyMinutes: recencyMinutes, baselinePercent: baselinePercent)
    }

    private var statusColor: Color {
        switch effectiveStatus {
        case .success: return .green
        case .warning: return .orange
        case .danger: return .red
        case .unknown: return .gray
        }
    }

    private var chartLabel: String {
        let h = Int(chartHours)
        return h == 24 ? "24h report history" : "\(h)h report history"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)

                Text(effectiveStatus.label)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)

                Spacer()

                Text("Peak: \(formatReportCount(filteredMax))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            SparklineChart(
                dataPoints: filteredDataPoints,
                maxReports: filteredMax,
                color: statusColor,
                hoveredIndex: $hoveredIndex
            )
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Info row: hover data or default stats
            HStack {
                if let idx = hoveredIndex, idx < filteredDataPoints.count {
                    let point = filteredDataPoints[idx]
                    Text(formatTime(point.timestamp))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Baseline: \(point.baseline)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("Reports: \(formatReportCount(point.reports))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(statusColor)
                } else {
                    Text(chartLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let latest = report.dataPoints.last {
                        Text("Baseline: \(latest.baseline)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("Now: \(formatReportCount(latest.reports))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text("Peak: \(formatReportCount(filteredMax))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: "https://downdetector.com/status/\(providerSlug)/") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func formatReportCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

struct SparklineChart: View {
    let dataPoints: [DowndetectorDataPoint]
    let maxReports: Int
    let color: Color
    var interactive: Bool = true
    @Binding var hoveredIndex: Int?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let count = dataPoints.count
                guard count > 0 else { return }

                let maxY = max(CGFloat(maxReports), 1)
                let barWidth = size.width / CGFloat(count)
                let gap: CGFloat = max(barWidth * 0.15, 0.5)

                for (i, point) in dataPoints.enumerated() {
                    let fraction = CGFloat(point.reports) / maxY
                    let barHeight = max(fraction * size.height, fraction > 0 ? 1 : 0)
                    let x = CGFloat(i) * barWidth
                    let y = size.height - barHeight

                    let rect = CGRect(
                        x: x + gap / 2,
                        y: y,
                        width: max(barWidth - gap, 0.5),
                        height: barHeight
                    )
                    let isHovered = hoveredIndex == i
                    let opacity = isHovered ? 1.0 : (fraction > 0.02 ? 0.7 : 0.15)
                    context.fill(Path(rect), with: .color(color.opacity(opacity)))
                }

                // Highlight line for hovered bar
                if let idx = hoveredIndex, idx < count {
                    let barWidth = size.width / CGFloat(count)
                    let x = CGFloat(idx) * barWidth + barWidth / 2
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
                }

                // Baseline indicator
                let avgBaseline = dataPoints.map { CGFloat($0.baseline) }.reduce(0, +) / CGFloat(count)
                let baselineY = size.height - (avgBaseline / maxY) * size.height
                if baselineY > 1 && baselineY < size.height - 1 {
                    var baselinePath = Path()
                    baselinePath.move(to: CGPoint(x: 0, y: baselineY))
                    baselinePath.addLine(to: CGPoint(x: size.width, y: baselineY))
                    context.stroke(
                        baselinePath,
                        with: .color(.white.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )

                        
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard interactive else { return }
                switch phase {
                case .active(let location):
                    let count = dataPoints.count
                    guard count > 0 else { return }
                    let barWidth = geo.size.width / CGFloat(count)
                    let idx = Int(location.x / barWidth)
                    if idx >= 0 && idx < count {
                        hoveredIndex = idx
                    }
                case .ended:
                    hoveredIndex = nil
                @unknown default:
                    hoveredIndex = nil
                }
            }
        }
    }
}

private extension NSColor {
    var hsbComponents: (hue: Double, saturation: Double, brightness: Double) {
        let color = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (Double(hue), Double(saturation), Double(brightness))
    }
}

private func maskEmail(_ email: String, percentage: Double, domainOnly: Bool) -> String {
    let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return email }

    let local = parts[0]
    let domain = parts[1]
    let domainParts = domain.split(separator: ".", maxSplits: 1).map(String.init)

    let maskedLocal = domainOnly ? local : maskSegment(local, percentage: percentage)
    let maskedDomainName = domainParts.isEmpty ? maskSegment(domain, percentage: percentage) : maskSegment(domainParts[0], percentage: percentage)
    let suffix = domainParts.count == 2 ? ".\(domainParts[1])" : ""
    return "\(maskedLocal)@\(maskedDomainName)\(suffix)"
}

private func maskSegment(_ segment: String, percentage: Double) -> String {
    guard !segment.isEmpty else { return segment }
    let chars = Array(segment)
    let count = chars.count
    let maskCount = min(max(Int((Double(count) * percentage).rounded()), 0), max(0, count - 1))
    let visibleCount = max(1, count - maskCount)
    let prefixCount = max(1, visibleCount / 2)
    let suffixCount = max(0, visibleCount - prefixCount)

    let prefix = String(chars.prefix(prefixCount))
    let suffix = suffixCount > 0 ? String(chars.suffix(suffixCount)) : ""
    let middleCount = max(0, count - prefixCount - suffixCount)
    return prefix + String(repeating: "*", count: middleCount) + suffix
}
