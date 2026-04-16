import Foundation
import CoreGraphics

@MainActor
final class PopoverController: ObservableObject {
    var close: () -> Void = {}
    @Published private(set) var closeCount = 0
    @Published var showSettings = false
    @Published var showDowndetector = false
    @Published var preferredSize: CGSize = .zero

    func dismiss() {
        close()
    }

    func didClose() {
        closeCount += 1
    }
}
