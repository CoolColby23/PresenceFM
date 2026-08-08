import Foundation

/// Minimal scrobble retry/backoff helper.
/// Integrate with existing ScrobbleQueue persistence and submission pipeline.
@MainActor
final class ScrobbleRetryPolicy {
    static let shared = ScrobbleRetryPolicy()

    private init() {}

    /// Compute next retry delay (seconds) given attempt count.
    /// Uses capped exponential backoff with jitter.
    func nextDelaySeconds(attempt: Int) -> TimeInterval {
        let base: Double = 2.0
        let maxDelay: Double = 60 * 10 // 10 minutes
        let expo = pow(base, Double(min(attempt, 10)))
        let jitter = Double.random(in: 0.5...1.0)
        return min(expo * jitter, maxDelay)
    }

    /// Determine if we should retry based on error and attempt count.
    func shouldRetry(error: Error, attempt: Int) -> Bool {
        if attempt >= 10 { return false }
        return true
    }
}
