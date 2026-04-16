import Foundation

extension Notification.Name {
    static let signInCompleted = Notification.Name("signInCompleted")
}

extension Comparable {
    func bounded(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        switch self {
        case .some(let value):
            return value.trimmedNonEmpty
        default:
            return nil
        }
    }
}

@MainActor
enum UsagePersistence {
    private static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("BitstraumUsage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("usage-state.json")
    }

    static func load() -> [ProviderUsageCard]? {
        guard let data = try? Data(contentsOf: storageURL) else {
            return nil
        }

        return try? JSONDecoder().decode(PersistedUsageState.self, from: data).cards
    }

    static func save(_ cards: [ProviderUsageCard]) {
        let state = PersistedUsageState(cards: cards)
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        try? data.write(to: storageURL, options: Data.WritingOptions.atomic)
    }
}
