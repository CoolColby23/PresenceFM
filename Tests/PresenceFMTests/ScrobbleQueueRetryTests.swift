import XCTest

@testable import PresenceFM

final class ScrobbleQueueRetryTests: XCTestCase {
    func testBackoffMonotonic() async {
        let policy = await MainActor.run { ScrobbleRetryPolicy.shared }
        var last: TimeInterval = 0
        for attempt in 0..<10 {
            let d = await MainActor.run { policy.nextDelaySeconds(attempt: attempt) }
            XCTAssertGreaterThanOrEqual(d, last)
            last = d
        }
    }
}
