import XCTest
@testable import AgentControllerCore

final class ControllerObservationContinuityTrackerTests: XCTestCase {
    func testOnlyRealSnapshotObservationsRefreshContinuity() {
        var tracker = ControllerObservationContinuityTracker(timeout: 60)
        let connected = ControllerSnapshot(isConnected: true)

        tracker.observe(connected, at: 10)
        XCTAssertTrue(tracker.isContinuous(at: 70))

        // A periodic timer only queries. It must not extend the observation
        // window for a cached, potentially sleeping wireless controller.
        XCTAssertFalse(tracker.isContinuous(at: 70.001))
        XCTAssertFalse(tracker.isContinuous(at: 120))
    }

    func testDisconnectClearsAndReconnectNeedsFreshObservation() {
        var tracker = ControllerObservationContinuityTracker(timeout: 60)
        let connected = ControllerSnapshot(isConnected: true)

        tracker.observe(connected, at: 10)
        XCTAssertTrue(tracker.isContinuous(at: 20))

        tracker.observe(.disconnected, at: 21)
        XCTAssertFalse(tracker.isContinuous(at: 21))

        // Merely knowing a controller is connected again is insufficient;
        // the platform must deliver a fresh snapshot first.
        XCTAssertFalse(tracker.isContinuous(at: 22))
        tracker.observe(connected, at: 22)
        XCTAssertTrue(tracker.isContinuous(at: 22))
        XCTAssertTrue(tracker.isContinuous(at: 82))
        XCTAssertFalse(tracker.isContinuous(at: 82.001))
    }

    func testNonFiniteOrBackwardsTimeFailsClosed() {
        var tracker = ControllerObservationContinuityTracker(timeout: 60)
        let connected = ControllerSnapshot(isConnected: true)

        tracker.observe(connected, at: 10)
        XCTAssertFalse(tracker.isContinuous(at: 9))
        tracker.observe(connected, at: .infinity)
        XCTAssertFalse(tracker.isContinuous(at: 10))
    }
}
