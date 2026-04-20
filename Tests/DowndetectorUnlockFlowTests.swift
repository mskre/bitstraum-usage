import Foundation
import WebKit

@main
struct DowndetectorUnlockFlowTests {
    static func main() {
        let challengeHTML = "<html><body>Just a moment</body></html>"
        guard DowndetectorService.classifyHTML(challengeHTML) == .blocked else {
            fatalError("Expected challenge page to classify as blocked")
        }

        guard DowndetectorService.canPresentUnlockFlow(for: .blocked) else {
            fatalError("Expected blocked fetch state to allow unlock flow")
        }

        let unavailableHTML = "<html><body>No report data</body></html>"
        guard DowndetectorService.classifyHTML(unavailableHTML) == .unavailable else {
            fatalError("Expected non-report HTML to classify as unavailable")
        }

        guard !DowndetectorService.canPresentUnlockFlow(for: .unavailable) else {
            fatalError("Expected unavailable fetch state to skip unlock flow")
        }
    }
}
