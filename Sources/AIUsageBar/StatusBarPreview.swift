import AppKit

final class StatusBarPreviewView: NSView {
    var cards: [ProviderUsageCard] = [] {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    var isRefreshing: Bool = false {
        didSet { needsDisplay = true }
    }

    // Bar geometry
    private let barW: CGFloat = 14
    private let barH: CGFloat = 4
    private let gap: CGFloat = 3
    private let pad: CGFloat = 4

    override var intrinsicContentSize: NSSize {
        let n = CGFloat(ProviderID.allCases.count)
        let w = pad + n * barW + (n - 1) * gap + pad
        return NSSize(width: w, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let midY = bounds.midY

        for (i, provider) in ProviderID.allCases.enumerated() {
            let card = cards.first { $0.id == provider }
            let x = pad + CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: midY - barH / 2, width: barW, height: barH)

            // Track
            let track = NSBezierPath(roundedRect: rect, xRadius: barH / 2, yRadius: barH / 2)
            NSColor.white.withAlphaComponent(0.15).setFill()
            track.fill()

            // Fill
            let frac = fillFraction(card: card)
            let fillW = max(barH, rect.width * frac)
            let fillRect = NSRect(x: rect.minX, y: rect.minY,
                                  width: min(fillW, rect.width), height: rect.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: barH / 2, yRadius: barH / 2)
            provider.accentColor.withAlphaComponent(frac > 0 ? 0.9 : 0.25).setFill()
            fill.fill()
        }
    }

    private func fillFraction(card: ProviderUsageCard?) -> CGFloat {
        guard let card else { return 0 }
        if !card.authenticated { return 0 }
        if isRefreshing && card.state == .loading { return 0.5 }
        if let f = card.bestFraction { return CGFloat(f.bounded(to: 0...1)) }
        switch card.state {
        case .ready: return 0.5
        case .loading: return 0.5
        default: return 0
        }
    }
}
