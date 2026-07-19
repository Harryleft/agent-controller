import XCTest
@testable import AgentControllerPlatform

final class CodexComposerSubmitAccessibilityTests: XCTestCase {
    private let verifier = CodexComposerSubmitVerifier()

    func testMissingAXEditableUsesSettableValueFallback() {
        XCTAssertTrue(CodexComposerEditabilityPolicy.accepts(
            explicitEditable: nil,
            valueIsSettable: true
        ))
        XCTAssertFalse(CodexComposerEditabilityPolicy.accepts(
            explicitEditable: nil,
            valueIsSettable: false
        ))
    }

    func testExplicitNonEditableComposerCannotUseFallback() {
        XCTAssertTrue(CodexComposerEditabilityPolicy.accepts(
            explicitEditable: true,
            valueIsSettable: false
        ))
        XCTAssertFalse(CodexComposerEditabilityPolicy.accepts(
            explicitEditable: false,
            valueIsSettable: true
        ))
    }

    func testFocusedComposerAdmissionDoesNotDependOnUnrelatedTreeCompleteness() {
        XCTAssertTrue(CodexFocusedComposerPolicy.accepts(
            roleIsTextArea: true,
            isFocused: true,
            belongsToFocusedWindow: true,
            explicitEditable: nil,
            valueIsSettable: true,
            numberOfCharacters: 5
        ))

        XCTAssertFalse(CodexFocusedComposerPolicy.accepts(
            roleIsTextArea: true,
            isFocused: true,
            belongsToFocusedWindow: false,
            explicitEditable: nil,
            valueIsSettable: true,
            numberOfCharacters: 5
        ))
    }

    func testNonEmptyUniqueFocusedComposerCanOnlyConfirmAfterItClears() {
        var adapter = FakeSubmitAdapter(
            before: snapshot(count: 12),
            after: snapshot(count: 0)
        )

        XCTAssertEqual(adapter.run(using: verifier), .composerClearedConfirmed)
        XCTAssertTrue(adapter.didPostFixedSubmitKey)
        XCTAssertEqual(adapter.postedToProcessIdentifier, 42)
    }

    func testEmptyComposerDoesNotPost() {
        var adapter = FakeSubmitAdapter(
            before: snapshot(count: 0),
            after: snapshot(count: 0)
        )

        XCTAssertEqual(adapter.run(using: verifier), .unavailable)
        XCTAssertFalse(adapter.didPostFixedSubmitKey)
    }

    func testBindingConflictDoesNotPost() {
        var adapter = FakeSubmitAdapter(
            before: snapshot(count: 12),
            after: snapshot(count: 0),
            bindingAvailable: false
        )

        XCTAssertEqual(adapter.run(using: verifier), .unavailable)
        XCTAssertFalse(adapter.didPostFixedSubmitKey)
        XCTAssertNil(adapter.postedToProcessIdentifier)
    }

    func testConfigurationChangedAfterSchedulingDoesNotPost() {
        var adapter = FakeSubmitAdapter(
            before: snapshot(count: 12),
            after: snapshot(count: 0),
            bindingAvailableImmediatelyBeforePost: false
        )

        XCTAssertEqual(adapter.run(using: verifier), .unavailable)
        XCTAssertFalse(adapter.didPostFixedSubmitKey)
    }

    func testReplacementBeforeDispatchDoesNotPost() {
        var adapter = FakeSubmitAdapter(
            before: snapshot(count: 12),
            immediatelyBeforePost: snapshot(
                count: 12,
                elementIdentity: "replacement"
            ),
            after: snapshot(count: 0, elementIdentity: "replacement")
        )

        XCTAssertEqual(adapter.run(using: verifier), .unavailable)
        XCTAssertFalse(adapter.didPostFixedSubmitKey)
    }

    func testAmbiguousOrUnfocusedComposerDoesNotPost() {
        var ambiguous = FakeSubmitAdapter(
            before: snapshot(count: 4, extraComposer: true),
            after: snapshot(count: 0)
        )
        XCTAssertEqual(ambiguous.run(using: verifier), .unavailable)
        XCTAssertFalse(ambiguous.didPostFixedSubmitKey)

        var unfocused = FakeSubmitAdapter(
            before: snapshot(count: 4, isFocused: false),
            after: snapshot(count: 0)
        )
        XCTAssertEqual(unfocused.run(using: verifier), .unavailable)
        XCTAssertFalse(unfocused.didPostFixedSubmitKey)
    }

    func testMissingCharacterCountOrWindowDriftDoesNotPost() {
        var missingCount = FakeSubmitAdapter(
            before: snapshot(count: nil),
            after: snapshot(count: 0)
        )
        XCTAssertEqual(missingCount.run(using: verifier), .unavailable)
        XCTAssertFalse(missingCount.didPostFixedSubmitKey)

        var windowDrift = FakeSubmitAdapter(
            before: snapshot(count: 4, focusedWindow: "focused", mainWindow: "main"),
            after: snapshot(count: 0)
        )
        XCTAssertEqual(windowDrift.run(using: verifier), .unavailable)
        XCTAssertFalse(windowDrift.didPostFixedSubmitKey)
    }

    func testPidWindowAndPostStateMustAllMatchBeforeConfirmation() {
        let before = snapshot(count: 4)
        let receipt = try! XCTUnwrap(verifier.begin(from: before))

        XCTAssertFalse(verifier.confirmsComposerCleared(
            receipt,
            after: snapshot(count: 0, pid: 99)
        ))
        XCTAssertFalse(verifier.confirmsComposerCleared(
            receipt,
            after: snapshot(count: 0, focusedWindow: "other", mainWindow: "other")
        ))
        XCTAssertFalse(verifier.confirmsComposerCleared(
            receipt,
            after: snapshot(count: 4)
        ))
        XCTAssertFalse(verifier.confirmsComposerCleared(
            receipt,
            after: snapshot(count: 0, elementIdentity: "replacement")
        ))
    }

    func testResultNameDoesNotClaimTurnCompletion() {
        XCTAssertEqual(
            CodexComposerSubmitAutomationResult.composerClearedConfirmed.diagnostic,
            "Composer 已清空（已确认）"
        )
        XCTAssertEqual(
            CodexComposerSubmitAutomationResult
                .shortcutPostedWithoutUIConfirmation.diagnostic,
            "提交已发送（未验证）"
        )
    }

    func testRequestGatePreservesXReleaseButCancelsEveryOtherAction() {
        XCTAssertFalse(CodexComposerSubmitRequestGate.cancelsPendingSubmit(
            bridgeEnabled: true,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true,
            inputLayer: .base,
            controllerActions: []
        ))
        XCTAssertFalse(CodexComposerSubmitRequestGate.cancelsPendingSubmit(
            bridgeEnabled: true,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true,
            inputLayer: .base,
            controllerActions: [.submit]
        ))
        XCTAssertTrue(CodexComposerSubmitRequestGate.cancelsPendingSubmit(
            bridgeEnabled: true,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true,
            inputLayer: .base,
            controllerActions: [.wakeCodex]
        ))
        XCTAssertTrue(CodexComposerSubmitRequestGate.cancelsPendingSubmit(
            bridgeEnabled: true,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true,
            inputLayer: .command,
            controllerActions: []
        ))
        XCTAssertTrue(CodexComposerSubmitRequestGate.cancelsPendingSubmit(
            bridgeEnabled: false,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true,
            inputLayer: .base,
            controllerActions: []
        ))
    }

    func testLayerChangeCancelsOnlySubmitNotTheGlobalSessionState() {
        XCTAssertTrue(CodexComposerSubmitRequestGate.cancelsPendingSubmit(
            bridgeEnabled: true,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true,
            inputLayer: .agent,
            controllerActions: []
        ))
        XCTAssertFalse(CodexControllerSessionGate.requiresGlobalCleanup(
            bridgeEnabled: true,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true
        ))
        XCTAssertTrue(CodexControllerSessionGate.requiresGlobalCleanup(
            bridgeEnabled: false,
            controllerConnected: true,
            sessionPhase: .active,
            codexForeground: true
        ))
    }

    func testMenuOrActionPanelCombinedWithXDropsThatBatchSubmit() {
        XCTAssertFalse(CodexComposerSubmitRequestGate.admitsSubmit(
            in: [.wakeCodex, .submit]
        ))
        XCTAssertFalse(CodexComposerSubmitRequestGate.admitsSubmit(
            in: [.openActionPanel, .submit]
        ))
        XCTAssertTrue(CodexComposerSubmitRequestGate.admitsSubmit(
            in: [.submit]
        ))
    }

    private func snapshot(
        count: Int?,
        pid: Int32 = 42,
        isFocused: Bool = true,
        focusedWindow: String? = "window",
        mainWindow: String? = "window",
        elementIdentity: String = "composer",
        extraComposer: Bool = false
    ) -> CodexComposerAXSnapshot {
        var elements = [CodexComposerAXElementSnapshot(
            role: "AXTextArea",
            isFocused: isFocused,
            isEditable: true,
            elementIdentity: elementIdentity,
            windowIdentity: focusedWindow ?? mainWindow ?? "none",
            numberOfCharacters: count
        )]
        if extraComposer {
            elements.append(CodexComposerAXElementSnapshot(
                role: "AXTextArea",
                isFocused: true,
                isEditable: true,
                elementIdentity: "second-composer",
                windowIdentity: focusedWindow ?? mainWindow ?? "none",
                numberOfCharacters: count
            ))
        }
        return CodexComposerAXSnapshot(
            processIdentifier: pid,
            isForegroundCodex: true,
            focusedWindowIdentity: focusedWindow,
            mainWindowIdentity: mainWindow,
            elements: elements
        )
    }
}

private struct FakeSubmitAdapter {
    let before: CodexComposerAXSnapshot
    let immediatelyBeforePost: CodexComposerAXSnapshot
    let after: CodexComposerAXSnapshot
    let bindingAvailable: Bool
    let bindingAvailableImmediatelyBeforePost: Bool
    private(set) var didPostFixedSubmitKey = false
    private(set) var postedToProcessIdentifier: Int32?

    init(
        before: CodexComposerAXSnapshot,
        immediatelyBeforePost: CodexComposerAXSnapshot? = nil,
        after: CodexComposerAXSnapshot,
        bindingAvailable: Bool = true,
        bindingAvailableImmediatelyBeforePost: Bool = true
    ) {
        self.before = before
        self.immediatelyBeforePost = immediatelyBeforePost ?? before
        self.after = after
        self.bindingAvailable = bindingAvailable
        self.bindingAvailableImmediatelyBeforePost =
            bindingAvailableImmediatelyBeforePost
    }

    mutating func run(
        using verifier: CodexComposerSubmitVerifier
    ) -> CodexComposerSubmitAutomationResult {
        guard bindingAvailable,
              let receipt = verifier.begin(from: before) else {
            return .unavailable
        }
        guard bindingAvailableImmediatelyBeforePost else {
            return .unavailable
        }
        guard verifier.confirmsSameNonEmptyComposer(
            receipt,
            beforeDispatch: immediatelyBeforePost
        ) else {
            return .unavailable
        }
        // The fake represents the only allowed transport: fixed composer.submit
        // to the receipt PID. It deliberately carries no composer text.
        didPostFixedSubmitKey = true
        postedToProcessIdentifier = receipt.processIdentifier
        return verifier.confirmsComposerCleared(receipt, after: after)
            ? .composerClearedConfirmed
            : .unavailable
    }
}
