import XCTest
@testable import AgentControllerCore

final class ActiveControllerDeviceReducerTests: XCTestCase {
    func testNonActiveDisconnectNeverTearsDownActiveDevice() {
        var reducer = ActiveControllerDeviceReducer<String>()
        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-a", "xbox-b"]),
            .activate("xbox-a")
        )

        XCTAssertEqual(
            reducer.disconnectNotified(for: "xbox-b"),
            .nonActiveDisconnectIgnored
        )
        XCTAssertEqual(reducer.activeDeviceID, "xbox-a")
        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-a"]),
            .unchanged
        )
    }

    func testActiveDisconnectAlwaysProducesDisconnectBeforeReplacement() {
        var reducer = ActiveControllerDeviceReducer<String>()
        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-a", "xbox-b"]),
            .activate("xbox-a")
        )

        XCTAssertEqual(
            reducer.disconnectNotified(for: "xbox-a"),
            .activeDisconnected
        )
        XCTAssertNil(reducer.activeDeviceID)
        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-b"]),
            .activate("xbox-b")
        )
    }

    func testMissingActiveDeviceIsFailClosedThenFreshCandidateActivates() {
        var reducer = ActiveControllerDeviceReducer<String>()
        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-a"]),
            .activate("xbox-a")
        )

        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-b"]),
            .activeDisconnected
        )
        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-b"]),
            .activate("xbox-b")
        )
    }
}
