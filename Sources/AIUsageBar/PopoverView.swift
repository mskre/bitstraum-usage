import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(spacing: 6) {
            header

            ForEach(store.cards) { card in
                ProviderCardView(card: card) {
                    store.signIn(to: card.id)
                }
            }

            footer
        }
        .padding(10)
        .frame(width: 310)
    }

    private var header: some View {
        HStack {
            Text("AI Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                Task { await store.refreshAll() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack {
            Text(lastUpdatedText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.40))
            Spacer()
        }
    }

    private var lastUpdatedText: String {
        guard let d = store.lastRefresh else { return "Not refreshed yet" }
        return "Updated \(RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date()))"
    }
}

struct ProviderCardView: View {
    let card: ProviderUsageCard
    let signInAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: card.id.accentColor))
                    .frame(width: 7, height: 7)

                Text(card.id.shortTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Text(card.planName)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                if card.state == .unauthenticated || card.state == .error {
                    Button("Sign In") { signInAction() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: card.id.accentColor))
                } else {
                    statusLabel
                }
            }

            if card.limits.isEmpty && card.state != .unauthenticated {
                Text(card.statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }

            ForEach(card.limits) { limit in
                LimitRowView(limit: limit, color: Color(nsColor: card.id.accentColor))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var statusLabel: some View {
        let text: String
        let color: Color
        switch card.state {
        case .idle: text = "Idle"; color = .white.opacity(0.5)
        case .loading: text = "..."; color = .white.opacity(0.5)
        case .ready: text = "Live"; color = Color(nsColor: card.id.accentColor)
        case .unauthenticated: text = ""; color = .clear
        case .error: text = "!"; color = .orange
        }
        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
    }
}

struct LimitRowView: View {
    let limit: UsageLimit
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(limit.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                if let r = limit.remaining, let t = limit.total, t > 0 {
                    Text("\(Int(r))/\(Int(t))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    if let f = limit.fraction {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [color.opacity(0.6), color],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(geo.size.width * f.bounded(to: 0...1), 4))
                    } else {
                        Capsule().fill(color.opacity(0.20)).frame(width: geo.size.width)
                    }
                }
            }
            .frame(height: 5)

            if let reset = limit.resetLabel, !reset.isEmpty {
                Text(reset)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}
