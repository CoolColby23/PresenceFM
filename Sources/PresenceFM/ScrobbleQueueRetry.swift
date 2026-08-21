import Foundation

/// Minimal scrobble retry/backoff helper.
/// Integrate with existing ScrobbleQueue persistence and submission pipeline.
@MainActor
final class ScrobbleRetryPolicy {
    static let shared = ScrobbleRetryPolicy()

    private init() {}

    /// Compute next retry delay (seconds) given attempt count.
    /// Compute next retry delay (seconds) given attempt count.
    /// Uses the deterministic capped exponential backoff previously used by `retryDate`.
    func nextDelaySeconds(attempt: Int) -> TimeInterval {
        let delay = min(IntegrationPolicy.scrobbleRetryMaximum, pow(2, Double(min(max(attempt, 1), 11))) * 5)
        return delay
    }

    /// Determine if we should retry based on error and attempt count.
    func shouldRetry(error: Error, attempt: Int) -> Bool {
        if attempt >= 10 { return false }
        return true
    }
}
