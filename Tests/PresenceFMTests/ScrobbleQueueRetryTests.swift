import XCTest
@testable import PresenceFM

final class ScrobbleQueueRetryTests: XCTestCase {
    func testBackoffMonotonic() {
        let policy = ScrobbleRetryPolicy.shared
        var last: TimeInterval = 0
        for attempt in 0..<10 {
            let d = policy.nextDelaySeconds(attempt: attempt)
            XCTAssertGreaterThanOrEqual(d, last)
            last = d
        }
    }
}
