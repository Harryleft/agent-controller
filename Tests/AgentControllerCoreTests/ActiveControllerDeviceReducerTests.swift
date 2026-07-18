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

    func testInventoryReconciliationMissedDisconnectFailsClosedBeforeReplacement() {
        var reducer = ActiveControllerDeviceReducer<String>()
        XCTAssertEqual(
            reducer.reconcile(availableDeviceIDs: ["xbox-a"]),
            .activate("xbox-a")
        )

        // This is the path used when `GCController.controllers()` no longer
        // contains the active device but no disconnect notification arrived.
        // The platform must publish its disconnected snapshot for this first
        // reduction before calling reconcile again to attach xbox-b.
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
