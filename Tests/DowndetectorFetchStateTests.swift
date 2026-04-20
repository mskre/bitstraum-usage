import Foundation
import WebKit

@main
struct DowndetectorFetchStateTests {
    static func main() {
        let challengeHTML = "<html><body><h1>Just a moment</h1></body></html>"
        guard DowndetectorService.classifyHTML(challengeHTML) == .blocked else {
            fatalError("Expected challenge HTML to classify as blocked")
        }

        let unavailableHTML = "<html><body><h1>No report data</h1></body></html>"
        guard DowndetectorService.classifyHTML(unavailableHTML) == .unavailable else {
            fatalError("Expected non-report HTML to classify as unavailable")
        }

        guard DowndetectorService.tabState(hasReportData: false, blockedSlug: "openai") == .blocked(slug: "openai") else {
            fatalError("Expected blocked tab state when fetch is blocked and no report data is available")
        }

        guard DowndetectorService.tabState(hasReportData: false, blockedSlug: nil) == .unavailable else {
            fatalError("Expected unavailable tab state when no report data or blocked slug is available")
        }

        guard DowndetectorService.tabState(hasReportData: true, blockedSlug: "openai") == .blocked(slug: "openai") else {
            fatalError("Expected blocked tab state to win when the latest fetch is blocked, even if cached report data exists")
        }
    }
}
