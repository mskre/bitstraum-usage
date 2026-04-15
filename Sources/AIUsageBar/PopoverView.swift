import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            ForEach(store.cards) { card in
                ProviderCardView(card: card, signInAction: {
                    // Dismiss the dropdown before opening the sign-in window
                    NSApp.keyWindow?.orderOut(nil)
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

            Divider().opacity(0.3)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .padding(.vertical, 4)
        .frame(width: 310)
        .onReceive(timer) { self.now = $0 }
    }

    private var header: some View {
        HStack {
            Text("Bitstraum Usage")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
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
    let signInAction: () -> Void
    let signOutAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(Color(nsColor: card.id.accentColor))
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
                        .foregroundStyle(Color(nsColor: card.id.accentColor))
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
                LimitRowView(limit: limit, color: Color(nsColor: card.id.accentColor))
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
