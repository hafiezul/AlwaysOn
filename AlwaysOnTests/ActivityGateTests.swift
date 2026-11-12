import XCTest

final class ActivityGateTests: XCTestCase {
    func testGateOffAlwaysPosts() {
        let gate = ActivityGate(idleOnlyEnabled: false)
        XCTAssertTrue(gate.shouldPost(idleSeconds: 0, hasRunningTarget: true))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }

    func testIdleGateSkipsWhenUserRecentlyActive() {
        let gate = ActivityGate(idleOnlyEnabled: true)
        XCTAssertFalse(gate.shouldPost(idleSeconds: 0, hasRunningTarget: true))
        XCTAssertFalse(gate.shouldPost(idleSeconds: ActivityGate.idleThreshold - 1, hasRunningTarget: true))
    }

    func testIdleGatePostsOnceIdleReachesThreshold() {
        let gate = ActivityGate(idleOnlyEnabled: true)
        XCTAssertTrue(gate.shouldPost(idleSeconds: ActivityGate.idleThreshold, hasRunningTarget: true))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }

    func testTargetGateSkipsWhenNoTargetRuns() {
        let gate = ActivityGate(requireTargetApp: true, targetBundleIDs: ["com.example.app"])
        XCTAssertFalse(gate.shouldPost(idleSeconds: 300, hasRunningTarget: false))
    }

    func testTargetGatePostsWhileTargetRuns() {
        let gate = ActivityGate(requireTargetApp: true, targetBundleIDs: ["com.example.app"])
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }

    func testBothGatesMustPass() {
        let gate = ActivityGate(idleOnlyEnabled: true, requireTargetApp: true, targetBundleIDs: ["com.example.app"])
        XCTAssertFalse(gate.shouldPost(idleSeconds: 5, hasRunningTarget: true))
        XCTAssertFalse(gate.shouldPost(idleSeconds: 300, hasRunningTarget: false))
        XCTAssertTrue(gate.shouldPost(idleSeconds: 300, hasRunningTarget: true))
    }
    func testEvaluationCountsForEveryFlagCombination() {
        for idleEnabled in [false, true] {
            for targetEnabled in [false, true] {
                var idleCalls = 0
                var targetCalls = 0
                func idle() -> TimeInterval { idleCalls += 1; return ActivityGate.idleThreshold }
                func target() -> Bool { targetCalls += 1; return true }
                let gate = ActivityGate(idleOnlyEnabled: idleEnabled, requireTargetApp: targetEnabled)

                XCTAssertTrue(gate.shouldPost(idleSeconds: idle(), hasRunningTarget: target()))
                XCTAssertEqual(idleCalls, idleEnabled ? 1 : 0)
                XCTAssertEqual(targetCalls, targetEnabled ? 1 : 0)
            }
        }
    }

    func testIdleRejectionSkipsTargetProvider() {
        var idleCalls = 0
        var targetCalls = 0
        func idle() -> TimeInterval { idleCalls += 1; return ActivityGate.idleThreshold - 1 }
        func target() -> Bool { targetCalls += 1; return true }
        let gate = ActivityGate(idleOnlyEnabled: true, requireTargetApp: true)

        XCTAssertFalse(gate.shouldPost(idleSeconds: idle(), hasRunningTarget: target()))
        XCTAssertEqual(idleCalls, 1)
        XCTAssertEqual(targetCalls, 0)
    }

    func testTruthTableAtThresholdBoundary() {
        for idleEnabled in [false, true] {
            for targetEnabled in [false, true] {
                for idle in [ActivityGate.idleThreshold - 1, ActivityGate.idleThreshold] {
                    for target in [false, true] {
                        let gate = ActivityGate(idleOnlyEnabled: idleEnabled, requireTargetApp: targetEnabled)
                        let expected = (!idleEnabled || idle >= ActivityGate.idleThreshold) && (!targetEnabled || target)
                        XCTAssertEqual(gate.shouldPost(idleSeconds: idle, hasRunningTarget: target), expected)
                    }
                }
            }
        }
    }

    func testSkipReasonsAndPulseHistory() {
        let gate = ActivityGate(idleOnlyEnabled: true, requireTargetApp: true)
        XCTAssertEqual(gate.decision(idleSeconds: 0, hasRunningTarget: false), .skip(.userActive))
        XCTAssertEqual(gate.decision(idleSeconds: 60, hasRunningTarget: false), .skip(.noTarget))
        XCTAssertEqual(gate.decision(idleSeconds: 60, hasRunningTarget: true), .post)
        let log = PulseLog()
        let date = Date(timeIntervalSince1970: 1_000)
        log.record(.userActive, date: date)
        XCTAssertEqual(log.history.first?.summary, "Skipped: user active")
        XCTAssertEqual(log.history.first?.date, date)
        let firstID = log.history.first?.id
        log.record(.noTarget, date: date)
        XCTAssertEqual(log.history.last?.summary, "Skipped: no target app")
        XCTAssertNotEqual(log.history.last?.id, firstID)
        log.record(.inputCreationFailed)
        XCTAssertEqual(log.history.last?.summary, "Input creation failed")
        for offset in 0..<201 { log.record(.posted, date: date.addingTimeInterval(Double(offset))) }
        XCTAssertEqual(log.history.count, 200)
        XCTAssertEqual(log.history.first?.date, Date(timeIntervalSince1970: 1_001))
        XCTAssertEqual(log.history.last?.date, Date(timeIntervalSince1970: 1_200))
        XCTAssertEqual(log.counts, [.userActive: 1, .noTarget: 1, .inputCreationFailed: 1, .posted: 201])
        XCTAssertEqual(log.latestOutcome, .posted)
        log.clear()
        XCTAssertEqual(log.history.count, 0)
        XCTAssertEqual(log.counts, [:])
        XCTAssertNil(log.latestOutcome)
        log.record(.noTarget)
        XCTAssertEqual(log.counts, [.noTarget: 1])
    }

    func testEveryOutcomeHasACategoryAndExplanation() {
        let all: [PulseLog.Outcome] = [.posted, .userActive, .noTarget, .inputCreationFailed,
                                       .inputNotRegistered, .systemPaused, .permissionMissing, .stoppedAway, .stoppedLowBattery]
        XCTAssertEqual(Set(all.map(\.category)), Set(PulseLog.Category.allCases))
        XCTAssertTrue(all.allSatisfy { !$0.explanation.isEmpty })
    }

    func testCategoryCountsAddUpOutcomes() {
        let log = PulseLog()
        [.posted, .posted, .userActive, .noTarget, .systemPaused, .inputCreationFailed, .stoppedAway]
            .forEach { log.record($0) }
        XCTAssertEqual(log.count(of: .posted), 2)
        XCTAssertEqual(log.count(of: .skipped), 2)
        XCTAssertEqual(log.count(of: .paused), 1)
        XCTAssertEqual(log.count(of: .problem), 2)
    }

    // MARK: - Post verification

    private let postTime = Date(timeIntervalSince1970: 10_000)

    func testNothingToConfirmWithoutAPost() {
        var verifier = PostVerifier()
        XCTAssertFalse(verifier.hasPendingPost)
        XCTAssertTrue(verifier.confirm(idleSeconds: 9_999, now: postTime))
    }

    func testPostThatResetIdleTimeIsConfirmed() {
        var verifier = PostVerifier()
        verifier.recordPost(at: postTime)
        XCTAssertTrue(verifier.hasPendingPost)
        // 45 s later the idle time is just under 45 s: our post was the last input
        XCTAssertTrue(verifier.confirm(idleSeconds: 44.95, now: postTime.addingTimeInterval(45)))
        XCTAssertFalse(verifier.hasPendingPost)
    }

    func testUserInputAfterThePostAlsoConfirms() {
        var verifier = PostVerifier()
        verifier.recordPost(at: postTime)
        XCTAssertTrue(verifier.confirm(idleSeconds: 3, now: postTime.addingTimeInterval(45)))
    }

    func testPostThatLeftNoTraceIsReported() {
        var verifier = PostVerifier()
        verifier.recordPost(at: postTime)
        // The user was last active 10 s before the post, and nothing has arrived since
        XCTAssertFalse(verifier.confirm(idleSeconds: 55, now: postTime.addingTimeInterval(45)))
        XCTAssertFalse(verifier.hasPendingPost)
    }

    func testMarginAllowsSmallOvershoot() {
        var verifier = PostVerifier()
        verifier.recordPost(at: postTime)
        XCTAssertTrue(verifier.confirm(idleSeconds: 45 + PostVerifier.margin, now: postTime.addingTimeInterval(45)))
        verifier.recordPost(at: postTime)
        XCTAssertFalse(verifier.confirm(idleSeconds: 45 + PostVerifier.margin + 0.1, now: postTime.addingTimeInterval(45)))
    }

    func testRepeatedFailureIsCaughtByTheSecondTick() {
        var verifier = PostVerifier()
        // The user touched the Mac 1 s before the first post, which hides one failure
        verifier.recordPost(at: postTime)
        XCTAssertTrue(verifier.confirm(idleSeconds: 46, now: postTime.addingTimeInterval(45)))
        verifier.recordPost(at: postTime.addingTimeInterval(45))
        XCTAssertFalse(verifier.confirm(idleSeconds: 91, now: postTime.addingTimeInterval(90)))
    }

    func testBadReadingsAndBackwardClockProveNothing() {
        var verifier = PostVerifier()
        verifier.recordPost(at: postTime)
        XCTAssertTrue(verifier.confirm(idleSeconds: .infinity, now: postTime.addingTimeInterval(45)))
        verifier.recordPost(at: postTime)
        XCTAssertTrue(verifier.confirm(idleSeconds: -1, now: postTime.addingTimeInterval(45)))
        verifier.recordPost(at: postTime)
        XCTAssertTrue(verifier.confirm(idleSeconds: 500, now: postTime.addingTimeInterval(-30)))
    }

    func testResetDropsThePendingPost() {
        var verifier = PostVerifier()
        verifier.recordPost(at: postTime)
        verifier.reset()
        XCTAssertFalse(verifier.hasPendingPost)
        XCTAssertTrue(verifier.confirm(idleSeconds: 9_999, now: postTime.addingTimeInterval(45)))
    }

    func testUnregisteredInputIsAProblem() {
        let log = PulseLog()
        log.record(.inputNotRegistered)
        XCTAssertEqual(log.history.last?.summary, "Input had no effect")
        XCTAssertEqual(log.count(of: .problem), 1)
    }

    // MARK: - Custom target apps

    /// Writes a minimal app bundle and returns its URL
    private func makeApp(named fileName: String, info: [String: Any]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlwaysOnTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent(fileName, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testCustomAppReadsBundleIDAndPrefersDisplayName() throws {
        let url = try makeApp(named: "Chat.app", info: ["CFBundleIdentifier": "com.example.chat",
                                                        "CFBundleDisplayName": "Example Chat",
                                                        "CFBundleName": "chat"])
        XCTAssertEqual(TargetApp.custom(fromAppAt: url), TargetApp(bundleID: "com.example.chat", name: "Example Chat"))
    }

    func testCustomAppFallsBackToBundleNameThenFileName() throws {
        let named = try makeApp(named: "A.app", info: ["CFBundleIdentifier": "com.example.a", "CFBundleName": "Alpha"])
        XCTAssertEqual(TargetApp.custom(fromAppAt: named)?.name, "Alpha")
        let unnamed = try makeApp(named: "Beta Chat.app", info: ["CFBundleIdentifier": "com.example.b",
                                                                 "CFBundleDisplayName": "  "])
        XCTAssertEqual(TargetApp.custom(fromAppAt: unnamed)?.name, "Beta Chat")
    }

    func testCustomAppRejectsNonAppsAndMissingBundleID() throws {
        let noID = try makeApp(named: "NoID.app", info: ["CFBundleName": "NoID"])
        XCTAssertNil(TargetApp.custom(fromAppAt: noID))
        let emptyID = try makeApp(named: "Empty.app", info: ["CFBundleIdentifier": ""])
        XCTAssertNil(TargetApp.custom(fromAppAt: emptyID))
        let notApp = try makeApp(named: "Folder", info: ["CFBundleIdentifier": "com.example.folder"])
        XCTAssertNil(TargetApp.custom(fromAppAt: notApp))
        XCTAssertNil(TargetApp.custom(fromAppAt: URL(fileURLWithPath: "/nonexistent/Missing.app")))
    }

    func testAddingSkipsDuplicatesCatalogAppsAndAlwaysOn() {
        let chat = TargetApp(bundleID: "com.example.chat", name: "Example Chat")
        let added = TargetApp.adding(chat, to: [])
        XCTAssertEqual(added, [chat])
        XCTAssertEqual(TargetApp.adding(TargetApp(bundleID: "com.example.chat", name: "Renamed"), to: added), added)
        XCTAssertEqual(TargetApp.adding(TargetApp.catalog[0], to: added), added)
        XCTAssertEqual(TargetApp.adding(TargetApp(bundleID: TargetApp.ownBundleID, name: "AlwaysOn"), to: added), added)
        let other = TargetApp(bundleID: "com.example.other", name: "Other")
        XCTAssertEqual(TargetApp.adding(other, to: added), [chat, other])
    }

    func testTargetAppsSurviveEncoding() throws {
        let apps = [TargetApp(bundleID: "com.example.chat", name: "Example Chat")]
        let data = try JSONEncoder().encode(apps)
        XCTAssertEqual(try JSONDecoder().decode([TargetApp].self, from: data), apps)
    }
}

final class SimulatedInputTests: XCTestCase {
    func testMethodsPickTheirInputWhenNothingPlays() {
        XCTAssertEqual(ActivityMethod.mouse.input(lastWasMouse: false, mediaPlaying: false), .mouse)
        XCTAssertEqual(ActivityMethod.keyboard.input(lastWasMouse: false, mediaPlaying: false), .keyboard)
        XCTAssertEqual(ActivityMethod.alternating.input(lastWasMouse: true, mediaPlaying: false), .keyboard)
        XCTAssertEqual(ActivityMethod.alternating.input(lastWasMouse: false, mediaPlaying: false), .mouse)
    }

    func testPlaybackAlwaysUsesKeyboard() {
        for method in ActivityMethod.allCases {
            for lastWasMouse in [false, true] {
                XCTAssertEqual(method.input(lastWasMouse: lastWasMouse, mediaPlaying: true), .keyboard)
            }
        }
    }
}
