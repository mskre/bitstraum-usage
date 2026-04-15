import Foundation

@MainActor
final class PopoverController: ObservableObject {
    var close: () -> Void = {}

    func dismiss() {
        close()
    }
}
