import Foundation

@MainActor
final class PopoverController: ObservableObject {
    var close: () -> Void = {}
    @Published private(set) var closeCount = 0

    func dismiss() {
        close()
    }

    func didClose() {
        closeCount += 1
    }
}
