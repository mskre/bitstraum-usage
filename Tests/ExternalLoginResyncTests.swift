import Foundation

private actor DelayedCredentialSource<T> {
    private var value: T?

    func update(_ newValue: T) {
        value = newValue
    }

    func read() -> T? {
        value
    }
}

@main
struct ExternalLoginResyncTests {
    static func main() async throws {
        try await returnsFreshCredentialsAfterDelayedUpdate()
        try await stopsPollingPromptlyWhenCancelled()
        try await returnsNilAfterTimeoutWhenCredentialsNeverAppear()
        try await doesNotSleepPastTimeout()
    }

    private static func returnsFreshCredentialsAfterDelayedUpdate() async throws {
        let source = DelayedCredentialSource<String>()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await source.update("fresh-credentials")
        }

        let credentials = await KeychainHelper.waitForExternalCredentials(
            timeout: 0.3,
            interval: 0.01,
            read: {
                await source.read()
            }
        )

        guard credentials == "fresh-credentials" else {
            fatalError("Expected polling helper to return updated external credentials")
        }
    }

    private static func stopsPollingPromptlyWhenCancelled() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        let task = Task {
            await KeychainHelper.waitForExternalCredentials(
                timeout: 1.0,
                interval: 0,
                read: { nil as String? }
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let credentials = await task.value
        let elapsed = start.duration(to: clock.now)

        guard credentials == nil else {
            fatalError("Expected cancelled polling to return no credentials")
        }

        guard elapsed < .milliseconds(500) else {
            fatalError("Expected cancellation to stop polling promptly, elapsed: \(elapsed)")
        }
    }

    private static func doesNotSleepPastTimeout() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        let credentials = await KeychainHelper.waitForExternalCredentials(
            timeout: 0.05,
            interval: 0.2,
            read: { nil as String? }
        )
        let elapsed = start.duration(to: clock.now)

        guard credentials == nil else {
            fatalError("Expected timeout polling to return no credentials")
        }

        guard elapsed < .milliseconds(150) else {
            fatalError("Expected polling timeout to clamp sleep to the remaining time, elapsed: \(elapsed)")
        }
    }

    private static func returnsNilAfterTimeoutWhenCredentialsNeverAppear() async throws {
        let missing = await KeychainHelper.waitForExternalCredentials(
            timeout: 0.1,
            interval: 0.05,
            read: { nil as KeychainHelper.ClaudeCredentials? }
        )

        guard missing == nil else {
            fatalError("Expected wait helper to return nil after timeout")
        }
    }
}
