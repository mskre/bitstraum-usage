import AppKit

final class StatusBarPreviewView: NSView {
    var cards: [ProviderUsageCard] = [] {
        didSet { updateIcon() }
    }
    var isRefreshing: Bool = false {
        didSet { updateIcon() }
    }

    private weak var button: NSStatusBarButton?

    func attach(to button: NSStatusBarButton) {
        self.button = button
        updateIcon()
    }

    private func updateIcon() {
        guard let button else { return }

        let providers = ProviderID.allCases

        // Battery-style bars stacked vertically
        let barW: CGFloat = 16
        let barH: CGFloat = 5
        let gap: CGFloat = 2
        let pad: CGFloat = 2
        let lineW: CGFloat = 1.0

        let totalH = CGFloat(providers.count) * barH + CGFloat(providers.count - 1) * gap
        let imgW = barW + pad * 2
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
                let outerRect = NSRect(x: pad, y: y, width: barW, height: barH)
                let radius = barH / 2

                // Outline
                let outline = NSBezierPath(roundedRect: outerRect.insetBy(dx: lineW / 2, dy: lineW / 2),
                                           xRadius: radius, yRadius: radius)
                NSColor.black.withAlphaComponent(isAuthed ? 0.9 : 0.35).setStroke()
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
                    NSColor.black.setFill()
                    NSBezierPath(rect: fillRect).fill()

                    NSGraphicsContext.restoreGraphicsState()
                }
            }

            return true
        }

        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
    }

    private func sessionFraction(card: ProviderUsageCard?) -> CGFloat {
        guard let card, card.authenticated else { return 0 }
        if isRefreshing && card.state == .loading { return 0.5 }

        if let first = card.limits.first, let f = first.fraction {
            return CGFloat(f.bounded(to: 0...1))
        }

        if let f = card.bestFraction {
            return CGFloat(f.bounded(to: 0...1))
        }

        switch card.state {
        case .ready: return 0.0
        case .loading: return 0.5
        default: return 0
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 0, height: NSView.noIntrinsicMetric)
    }
}
