import AppKit

final class StatusBarPreviewView: NSView {
    var cards: [ProviderUsageCard] = [] {
        didSet {
            // Cache fractions from non-loading states so the icon doesn't flicker
            for card in cards where card.state != .loading {
                lastKnownFractions[card.id] = sessionFraction(card: card, useCache: false)
            }
            updateIcon()
        }
    }
    var isRefreshing: Bool = false {
        didSet { updateIcon() }
    }
    var providerColors: [ProviderID: NSColor] = [:] {
        didSet { updateIcon() }
    }
    var colorizeIcon = false {
        didSet { updateIcon() }
    }
    var downdetectorData: [ProviderID: DowndetectorReport] = [:] {
        didSet { updateIcon() }
    }
    var ddRecencyByProvider: [ProviderID: Double] = [:] {
        didSet { updateIcon() }
    }
    var ddBaselineByProvider: [ProviderID: Double] = [:] {
        didSet { updateIcon() }
    }
    var showDowndetector: Bool = true {
        didSet { updateIcon() }
    }
    var showAlertDot: Bool = true {
        didSet { updateIcon() }
    }
    var enabledProviders: [ProviderID: Bool] = [:] {
        didSet { updateIcon() }
    }
    var showProviderLabels: Bool = false {
        didSet { updateIcon() }
    }
    /// Usage fraction above which the red alert dot appears (e.g. 0.9 = 90% used).
    var alertUsageThreshold: CGFloat = 0.9
    private var lastKnownFractions: [ProviderID: CGFloat] = [:]

    private weak var button: NSStatusBarButton?

    func attach(to button: NSStatusBarButton) {
        self.button = button
        updateIcon()
    }

    /// Returns the alert color for a specific provider, or nil if no alert.
    private func alertColor(for provider: ProviderID) -> NSColor? {
        // Check low usage
        if let card = cards.first(where: { $0.id == provider }), card.authenticated,
           let frac = card.bestFraction, CGFloat(frac) >= alertUsageThreshold {
            return .red
        }
        // Check Downdetector
        if showDowndetector, let report = downdetectorData[provider] {
            let status = report.effectiveStatus(
                recencyMinutes: ddRecencyByProvider[provider] ?? 30,
                baselinePercent: ddBaselineByProvider[provider] ?? 200
            )
            switch status {
            case .danger: return .red
            case .warning: return .orange
            default: break
            }
        }
        return nil
    }

    private var hasAnyAlert: Bool {
        ProviderID.allCases.contains { alertColor(for: $0) != nil }
    }

    private func updateIcon() {
        guard let button else { return }

        let providers = ProviderID.allCases.filter { enabledProviders[$0] ?? true }
        guard !providers.isEmpty else {
            button.image = nil
            return
        }
        let alert = showAlertDot && hasAnyAlert

        // Battery-style bars stacked vertically
        let barW: CGFloat = 16
        let barH: CGFloat = 5
        let gap: CGFloat = 2
        let pad: CGFloat = 2
        let lineW: CGFloat = 1.0
        let dotSize: CGFloat = 5

        // Use fixed dimensions based on ALL providers to prevent icon bouncing
        let allCount = CGFloat(ProviderID.allCases.count)
        let totalH = allCount * barH + (allCount - 1) * gap
        let labelW: CGFloat = showProviderLabels ? 10 : 0
        let imgW = labelW + barW + pad * 2 + dotSize + 1
        let imgH: CGFloat = 18
        let size = NSSize(width: imgW, height: imgH)

        let image = NSImage(size: size, flipped: false) { rect in
            let originY = (rect.height - totalH) / 2

            for (i, provider) in providers.enumerated() {
                let card = self.cards.first { $0.id == provider }
                let frac = self.sessionFraction(card: card)
                let isAuthed = card?.authenticated == true

                // Top provider first (index 0 at top)
                let y = originY + CGFloat(providers.count - 1 - i) * (barH + gap)
                let barX = pad + labelW
                let outerRect = NSRect(x: barX, y: y, width: barW, height: barH)

                // Provider letter label
                if self.showProviderLabels {
                    let isTemplate = !self.colorizeIcon && !alert
                    let labelColor: NSColor = isTemplate
                        ? NSColor.black.withAlphaComponent(0.85)  // Template: alpha channel is what matters
                        : NSColor.white.withAlphaComponent(0.85)  // Non-template: need visible color
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                        .foregroundColor: labelColor
                    ]
                    let letter = NSAttributedString(string: provider.iconLetter, attributes: attrs)
                    let letterSize = letter.size()
                    let letterX = pad + (labelW - letterSize.width) / 2 - 1
                    let letterY = y + (barH - letterSize.height) / 2
                    letter.draw(at: NSPoint(x: letterX, y: letterY))
                }
                let radius = barH / 2

                // Outline
                let outline = NSBezierPath(roundedRect: outerRect.insetBy(dx: lineW / 2, dy: lineW / 2),
                                           xRadius: radius, yRadius: radius)
                let providerColor = self.providerColors[provider] ?? provider.defaultAccentColor
                let strokeColor = self.colorizeIcon ? NSColor.white.withAlphaComponent(isAuthed ? 0.95 : 0.35) : NSColor.black.withAlphaComponent(isAuthed ? 0.9 : 0.35)
                strokeColor.setStroke()
                outline.lineWidth = lineW
                outline.stroke()

                // Fill from left
                if frac > 0 && isAuthed {
                    let inset = outerRect.insetBy(dx: lineW + 0.5, dy: lineW + 0.5)
                    let fillW = max(inset.height, inset.width * frac)

                    NSGraphicsContext.saveGraphicsState()
                    let clipPath = NSBezierPath(roundedRect: inset, xRadius: radius - lineW, yRadius: radius - lineW)
                    clipPath.addClip()

                    let fillRect = NSRect(x: inset.minX, y: inset.minY, width: min(fillW, inset.width), height: inset.height)
                    let fillColor = self.colorizeIcon ? providerColor : NSColor.black
                    fillColor.setFill()
                    NSBezierPath(rect: fillRect).fill()

                    NSGraphicsContext.restoreGraphicsState()
                }
            }

            // Per-provider alert dots to the right of each bar
            if self.showAlertDot {
                for (i, provider) in providers.enumerated() {
                    if let color = self.alertColor(for: provider) {
                        let y = originY + CGFloat(providers.count - 1 - i) * (barH + gap)
                        let dotX = pad + labelW + barW + 2
                        let dotY = y + (barH - dotSize) / 2
                        let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                        color.setFill()
                        NSBezierPath(ovalIn: dotRect).fill()
                    }
                }
            }

            return true
        }

        image.isTemplate = !colorizeIcon && !alert
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func sessionFraction(card: ProviderUsageCard?, useCache: Bool = true) -> CGFloat {
        guard let card, card.authenticated else { return 0 }

        // During loading, keep the last known fraction so the icon doesn't flicker
        if card.state == .loading, useCache, let cached = lastKnownFractions[card.id] {
            return cached
        }

        if let first = card.limits.first, let f = first.fraction {
            return CGFloat(f.bounded(to: 0...1))
        }

        if let f = card.bestFraction {
            return CGFloat(f.bounded(to: 0...1))
        }

        switch card.state {
        case .ready: return 0.0
        case .loading: return lastKnownFractions[card.id] ?? 0
        default: return 0
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 0, height: NSView.noIntrinsicMetric)
    }
}
