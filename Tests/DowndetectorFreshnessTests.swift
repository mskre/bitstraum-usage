import Foundation

@main
struct DowndetectorFreshnessTests {
    static func main() {
        let report = DowndetectorReport(
            status: .danger,
            dataPoints: [
                DowndetectorDataPoint(
                    timestamp: Date(),
                    reports: 120,
                    baseline: 10
                )
            ],
            reportsMax: 120,
            indicators: [],
            fetchedAt: Date()
        )

        let freshStatus = report.alertStatus(
            baselinePercent: 400,
            staleAfter: 600,
            now: report.fetchedAt.addingTimeInterval(60)
        )
        guard freshStatus == .danger else {
            fatalError("Expected fresh report to stay dangerous")
        }

        let staleStatus = report.alertStatus(
            baselinePercent: 400,
            staleAfter: 600,
            now: report.fetchedAt.addingTimeInterval(601)
        )
        guard staleStatus == .unknown else {
            fatalError("Expected stale report to become unknown")
        }
    }
}
