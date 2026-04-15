import AppKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var colorSettings: ColorSettings
    @EnvironmentObject private var popoverController: PopoverController
    @State private var now = Date()
    @State private var showSettings = false
    @State private var dismissWork: DispatchWorkItem?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            if showSettings {
                ColorSettingsView()
                    .environmentObject(colorSettings)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.cards) { card in
                    ProviderCardView(card: card, color: colorSettings.swiftUIColor(for: card.id), signInAction: {
                        popoverController.dismiss()
                        store.signIn(to: card.id)
                    }, signOutAction: {
                        Task { await store.signOut(from: card.id) }
                    })
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if card.id != store.cards.last?.id {
                        Divider().opacity(0.2).padding(.horizontal, 14)
                    }
                }
            }

            Divider().opacity(0.3)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .padding(.vertical, 4)
        .frame(width: showSettings ? 360 : 310)
        .onReceive(timer) { self.now = $0 }
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
            if showSettings {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showSettings = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Bitstraum Usage")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text("Settings")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text("Bitstraum Usage")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSettings.toggle()
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(card.id.shortTitle)
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

            if let email = card.email {
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if card.limits.isEmpty && card.state != .unauthenticated {
                if card.state == .loading {
                    Text("Fetching usage data...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
}

// MARK: - Limit row

struct LimitRowView: View {
    let limit: UsageLimit
    let color: Color

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

            if let reset = limit.resetLabel, !reset.isEmpty {
                Text(reset)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Color settings

struct ColorSettingsView: View {
    @EnvironmentObject private var colorSettings: ColorSettings
    @State private var expandedProvider: ProviderID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bar Colors")
                .font(.system(size: 12, weight: .semibold))

            ForEach(ProviderID.allCases) { provider in
                HexColorRow(provider: provider, expandedProvider: $expandedProvider)
            }

            Divider().opacity(0.2).padding(.vertical, 4)

            Toggle(isOn: $colorSettings.dismissOnMouseExit) {
                Text("Hide on mouse exit")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack {
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
    @Binding var expandedProvider: ProviderID?
    @EnvironmentObject private var colorSettings: ColorSettings
    @State private var hexText = ""
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 1
    @State private var isInteracting = false

    private var isExpanded: Bool { expandedProvider == provider }
    private var previewColor: NSColor {
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedProvider = isExpanded ? nil : provider
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: previewColor))
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.borderless)

                Text(provider.title)
                    .font(.system(size: 12))

                Spacer()

                Text("#\(hexText)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    CircularColorPicker(
                        hue: $hue,
                        saturation: $saturation,
                        brightness: brightness,
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
            let filtered = String(hexText.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(6))
            if filtered != hexText {
                hexText = filtered
                return
            }
            guard filtered.count == 6, let color = NSColor.fromHex(filtered) else { return }
            apply(color)
        }
        .onChange(of: hue) { syncHexFromPreview() }
        .onChange(of: saturation) { syncHexFromPreview() }
        .onChange(of: brightness) { syncHexFromPreview() }
    }

    private func syncFromSettings() {
        let color = colorSettings.color(for: provider).hsbComponents
        hue = color.hue
        saturation = color.saturation
        brightness = color.brightness
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
        if hexText != nextHex { hexText = nextHex }
    }

    private func handleInteraction(_ editing: Bool) {
        isInteracting = editing
        if !editing {
            colorSettings.setColor(previewColor, for: provider)
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

            Slider(value: $value, in: 0...1, onEditingChanged: onEditingChanged)
                .tint(Color(nsColor: NSColor(calibratedHue: hue, saturation: saturation, brightness: max(value, 0.15), alpha: 1.0)))
        }
    }
}

enum ColorWheelImageCache {
    private static var images: [String: NSImage] = [:]

    static func image(diameter: Int, brightness: Double) -> NSImage {
        let key = "\(diameter)-\(Int((brightness * 1000).rounded()))"
        if let cached = images[key] { return cached }

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: diameter,
            pixelsHigh: diameter,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let radius = Double(diameter) / 2
        let center = radius
        for y in 0..<diameter {
            for x in 0..<diameter {
                let dx = Double(x) + 0.5 - center
                let dy = Double(y) + 0.5 - center
                let distance = sqrt(dx * dx + dy * dy)
                if distance > radius {
                    rep.setColor(.clear, atX: x, y: y)
                    continue
                }

                let saturation = distance / radius
                var angle = atan2(dy, dx) + (.pi / 2)
                if angle < 0 { angle += .pi * 2 }
                let hue = angle / (.pi * 2)
                let color = NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
                rep.setColor(color, atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.addRepresentation(rep)
        images[key] = image
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

private extension NSColor {
    var srgbComponents: (red: Double, green: Double, blue: Double) {
        let color = usingColorSpace(.sRGB) ?? self
        return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
    }

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
