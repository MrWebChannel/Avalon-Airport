import XCTest
@testable import AvalonCore

final class TestClock {
    var now = ISO8601DateFormatter().date(from: "2026-12-01T09:00:00Z")!
    func advance(days: Int) { now = now.addingTimeInterval(TimeInterval(days * 86_400)) }
}

final class AvalonCoreTests: XCTestCase {
    var clock: TestClock!
    var services: GroundServices!
    var tower: FlightTower!
    let captain = TowerMember(id: "M-CAP", displayName: "Captain", role: .captain)
    let coCaptain = TowerMember(id: "M-CO", displayName: "Co-Captain", role: .coCaptain)
    let passenger = TowerMember(id: "M-PAX", displayName: "Passenger", role: .passenger)
    let advisor = CrewMember(id: "CW-ADV", displayName: "Advisor", role: .pilot, airlineId: "AL-WM")
    let attorney = CrewMember(id: "CW-ATT", displayName: "Attorney", role: .pilot, airlineId: "AL-LAW")
    let agent = CrewMember(id: "CW-AGT", displayName: "Agent", role: .crew, kind: .agent, airlineId: "AL-LAW")
    var advisorCred: Credential!
    var attorneyCred: Credential!
    var agentCred: Credential!

    var review: BoardingPass { tower.journey.boardingPasses[0] }
    var trust: BoardingPass { tower.journey.boardingPasses[1] }
    var sign: BoardingPass { tower.journey.boardingPasses[2] }

    override func setUpWithError() throws {
        clock = TestClock()
        services = .inMemory()
        let pkg = SampleCatalog.protectedEstate
        let c = clock!
        tower = FlightTower.create(from: pkg.journeyTemplates[0], in: pkg, captain: captain,
                                   others: [coCaptain, passenger], start: c.now, services: services, clock: { c.now })
        advisorCred = try tower.addCrew(advisor, to: tower.journey.boardingPasses[0].id, by: captain.id)
        attorneyCred = try tower.addCrew(attorney, to: tower.journey.boardingPasses[1].id, by: captain.id)
        agentCred = try tower.addCrew(agent, to: tower.journey.boardingPasses[1].id, by: captain.id)
        try tower.linkConnector(Connector(id: "C-1", type: .storage, provider: "dropbox", auth: "iOS Files",
                                          rootPath: "/Avalon", capabilities: ["read"]), by: captain.id)
        try tower.addRepository(connectorId: "C-1", path: "/Avalon/Estate", by: captain.id)
    }

    func crewProposal(_ crew: CrewMember, _ bp: BoardingPass, _ change: StatusChange? = nil,
                      notice: DeliverableNotice? = nil, actions: [ActionRequest] = [], message: String = "update") -> Proposal {
        Proposal(boardingPassId: bp.id, authorId: crew.id, authorType: .crew, reportedAt: clock.now, message: message,
                 statusChange: change, deliverableNotice: notice, actionRequests: actions)
    }

    /// Departs and lands the review flight with a filed deliverable.
    func completeReview() throws {
        var p = tower.submit(crewProposal(advisor, review, StatusChange(status: .departed)), credentialId: advisorCred.id)
        try tower.approve(p.id, by: captain.id)
        p = tower.submit(crewProposal(advisor, review, StatusChange(status: .landed),
                                      notice: DeliverableNotice(title: "Summary", sentVia: "secure email")),
                         credentialId: advisorCred.id)
        try tower.approve(p.id, by: captain.id)
        let d = tower.journey.deliverables.first { $0.boardingPassId == review.id }!
        try tower.markDeliverable(d.id, as: .filed, filedPath: "/Avalon/Estate/summary.pdf", by: captain.id)
    }

    // MARK: Template instantiation

    func testPackageCreatesBoardingPassesInSequence() {
        let passes = tower.journey.boardingPasses
        XCTAssertEqual(passes.map(\.code), ["PE-101", "PE-201", "PE-301", "PE-401"])
        XCTAssertEqual(passes[2].kind, .customs)
        XCTAssertEqual(passes[1].dependsOn, [passes[0].id])
        XCTAssertEqual(passes[1].pluginIds, ["hcs.decision-nudge"])
        XCTAssertNotNil(tower.engine.packagePlugins["hcs.decision-nudge"])
    }

    // MARK: Governance

    func testCrewProposalWaitsForCaptain() throws {
        let p = tower.submit(crewProposal(advisor, review, StatusChange(status: .departed)), credentialId: advisorCred.id)
        XCTAssertEqual(p.status, .pending)
        XCTAssertEqual(review.status, .scheduled, "Nothing changes until a Captain approves")
        let notifier = services.notifier as! InMemoryNotifier
        XCTAssertTrue(notifier.sent.contains { $0.recipientId == captain.id })
        let approved = try tower.approve(p.id, by: coCaptain.id)
        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(review.status, .departed)
    }

    func testOnlyCommittersCanApprove() {
        let p = tower.submit(crewProposal(advisor, review, StatusChange(status: .departed)), credentialId: advisorCred.id)
        XCTAssertThrowsError(try tower.approve(p.id, by: passenger.id))
    }

    func testPassengerCannotPropose() {
        let p = tower.submit(Proposal(boardingPassId: review.id, authorId: passenger.id, authorType: .member,
                                      reportedAt: clock.now, message: "x", statusChange: StatusChange(status: .departed)))
        XCTAssertEqual(p.status, .blocked)
    }

    func testCrewOutsideScopeIsBlocked() {
        let p = tower.submit(crewProposal(advisor, trust, StatusChange(status: .departed)), credentialId: advisorCred.id)
        XCTAssertEqual(p.status, .blocked)
    }

    func testRevokedCredentialIsBlocked() throws {
        try tower.revokeCredential(advisorCred.id, by: captain.id)
        let p = tower.submit(crewProposal(advisor, review, StatusChange(status: .departed)), credentialId: advisorCred.id)
        XCTAssertEqual(p.status, .blocked)
    }

    func testAgentCannotRequestAccessChanges() {
        let p = tower.submit(crewProposal(agent, trust, actions: [ActionRequest(type: .shareFolderLink,
                                                                                params: ["credentialId": agentCred.id])]),
                             credentialId: agentCred.id)
        XCTAssertEqual(p.status, .blocked)
        XCTAssertTrue(tower.state.storageGrants.isEmpty)
    }

    // MARK: Flight checks

    func testPreFlightBlocksUntilPreviousLandsAndDeliverableIsFiled() throws {
        var p = tower.submit(crewProposal(attorney, trust, StatusChange(status: .departed)), credentialId: attorneyCred.id)
        XCTAssertEqual(p.status, .blocked)
        XCTAssertTrue(p.decisionNote?.contains("waiting on PE-101") ?? false)

        p = tower.submit(crewProposal(advisor, review, StatusChange(status: .departed)), credentialId: advisorCred.id)
        try tower.approve(p.id, by: captain.id)
        p = tower.submit(crewProposal(advisor, review, StatusChange(status: .landed),
                                      notice: DeliverableNotice(title: "Summary", sentVia: "secure email")),
                         credentialId: advisorCred.id)
        try tower.approve(p.id, by: captain.id)
        XCTAssertEqual(trust.waitingOn?.kind, .passenger, "Next flight waits on the Captain's review")

        p = tower.submit(crewProposal(attorney, trust, StatusChange(status: .departed)), credentialId: attorneyCred.id)
        XCTAssertEqual(p.status, .blocked)
        XCTAssertTrue(p.decisionNote?.contains("not yet filed") ?? false)

        let d = tower.journey.deliverables[0]
        try tower.markDeliverable(d.id, as: .filed, filedPath: "/Avalon/Estate/summary.pdf", by: captain.id)
        XCTAssertNil(trust.waitingOn)
        p = tower.submit(crewProposal(attorney, trust, StatusChange(status: .departed)), credentialId: attorneyCred.id)
        XCTAssertEqual(p.status, .pending)
    }

    func testFilingNeedsAPathAndAHuman() throws {
        var p = tower.submit(crewProposal(advisor, review, StatusChange(status: .landed),
                                          notice: DeliverableNotice(title: "Summary", sentVia: "portal")),
                             credentialId: advisorCred.id)
        p = try tower.approve(p.id, by: captain.id)
        let d = tower.journey.deliverables[0]
        XCTAssertEqual(d.status, .sent)
        XCTAssertThrowsError(try tower.markDeliverable(d.id, as: .filed, by: captain.id))
        XCTAssertThrowsError(try tower.markDeliverable(d.id, as: .filed, filedPath: "/x", by: passenger.id))
    }

    // MARK: Delay plugin

    func testOverdueFlightIsAutoDelayedAndBlameFollowsWaitingOn() throws {
        try completeReview()
        let p = tower.submit(crewProposal(attorney, trust, StatusChange(status: .departed)), credentialId: attorneyCred.id)
        try tower.approve(p.id, by: captain.id)
        clock.advance(days: 40)
        tower.tick()
        XCTAssertEqual(trust.status, .delayed)
        XCTAssertTrue(tower.state.proposals.contains { $0.status == .autoApproved && $0.authorId == DelayPlugin.pluginId })
        let row = tower.flightBoard().first { $0.id == sign.id }!
        XCTAssertEqual(row.delayedBy, trust.code)
        XCTAssertTrue(tower.flightBoard().first { $0.id == trust.id }!.noContact)
    }

    func testDelayedEtaChangeNeedsReasonAndCause() throws {
        try completeReview()
        var p = tower.submit(crewProposal(attorney, trust, StatusChange(status: .departed)), credentialId: attorneyCred.id)
        try tower.approve(p.id, by: captain.id)
        clock.advance(days: 40)
        tower.tick()
        let later = clock.now.addingTimeInterval(7 * 86_400)
        p = tower.submit(crewProposal(attorney, trust, StatusChange(eta: later)), credentialId: attorneyCred.id)
        XCTAssertEqual(p.status, .blocked)
        p = tower.submit(crewProposal(attorney, trust, StatusChange(eta: later, reason: "Waiting on list", cause: .passenger)),
                         credentialId: attorneyCred.id)
        XCTAssertEqual(p.status, .pending)
    }

    // MARK: Plugin engine

    func testRunOrderAndTypeLimits() {
        XCTAssertEqual(tower.engine.runOrder, [.security, .analytics, .contentBehavior])
        let script = "function evaluate(ctx) { return [{severity: 'block', message: 'loud content'}]; }"
        let loud = PluginDescriptor(id: "test.loud", name: "Loud", type: .contentBehavior, tier: .package,
                                    signature: Hashing.sha256(script), script: script)
        let engine = PluginEngine(defaults: [], runtime: StubRuntime(output: "[{\"severity\":\"block\",\"message\":\"loud\"}]"))
        XCTAssertTrue(engine.register(loud))
        var bp = review
        bp.pluginIds = ["test.loud"]
        let result = engine.run(PluginContext(trigger: .onSchedule, now: clock.now, journey: tower.journey, boardingPass: bp))
        XCTAssertEqual(result.findings.first?.severity, .info, "contentBehavior may only inform")
        XCTAssertFalse(result.blocked)
    }

    func testUnsignedOrTamperedPluginIsRejected() {
        var tampered = SampleCatalog.decisionNudge
        tampered.id = "test.tampered"
        tampered.script = (tampered.script ?? "") + "\n// changed"
        XCTAssertFalse(tower.engine.register(tampered))
        var impostor = SampleCatalog.decisionNudge
        impostor.id = "avalon.security"
        XCTAssertFalse(tower.engine.register(impostor), "A package plugin cannot replace a default")
    }

    func testPluginsOnlyRunOnTheirFlight() {
        let engine = PluginEngine(defaults: [], runtime: StubRuntime(output: "[{\"severity\":\"info\",\"message\":\"hi\"}]"))
        engine.register(SampleCatalog.decisionNudge)
        let onReview = engine.run(PluginContext(trigger: .onSchedule, now: clock.now, journey: tower.journey, boardingPass: review))
        let onTrust = engine.run(PluginContext(trigger: .onSchedule, now: clock.now, journey: tower.journey, boardingPass: trust))
        XCTAssertTrue(onReview.findings.isEmpty)
        XCTAssertEqual(onTrust.findings.count, 1)
    }

    #if canImport(JavaScriptCore)
    func testDecisionNudgeRunsInJavaScriptCore() throws {
        try completeReview()
        var p = tower.submit(crewProposal(attorney, trust, StatusChange(status: .departed)), credentialId: attorneyCred.id)
        try tower.approve(p.id, by: captain.id)
        p = tower.submit(crewProposal(attorney, trust, StatusChange(waitingOn: WaitingOn(kind: .passenger, ref: captain.id, since: clock.now))),
                         credentialId: attorneyCred.id)
        try tower.approve(p.id, by: captain.id)
        clock.advance(days: 4)
        let findings = tower.tick()
        XCTAssertTrue(findings.contains { $0.pluginId == "hcs.decision-nudge" && $0.recommendation != nil })
    }
    #endif

    // MARK: Ground Crew and storage

    func testStorageGrantIsReadOnlyAndExpiresAtLanding() throws {
        try completeReview()
        let repo = tower.journey.repositories[0]
        let p = try tower.requestAction(ActionRequest(type: .shareFolderLink,
                                                      params: ["credentialId": attorneyCred.id, "repositoryId": repo.id,
                                                               "folder": "/ForAttorney", "boardingPassId": trust.id]),
                                        boardingPassId: trust.id, by: captain.id, message: "share")
        XCTAssertEqual(p.status, .approved)
        let grant = try XCTUnwrap(tower.state.storageGrants.first)
        XCTAssertEqual(grant.permission, "read")
        XCTAssertEqual(grant.status, .active)

        var q = tower.submit(crewProposal(attorney, trust, StatusChange(status: .departed)), credentialId: attorneyCred.id)
        try tower.approve(q.id, by: captain.id)
        q = tower.submit(crewProposal(attorney, trust, StatusChange(status: .landed),
                                      notice: DeliverableNotice(title: "Trust", sentVia: "in person")),
                         credentialId: attorneyCred.id)
        try tower.approve(q.id, by: captain.id)
        XCTAssertEqual(tower.state.storageGrants.first?.status, .expired)
    }

    func testRepeatedActionIsHarmless() throws {
        let request = ActionRequest(type: .notify, params: ["message": "hello"])
        let p = try tower.requestAction(request, by: captain.id, message: "notify")
        let again = tower.groundCrew.execute(request, for: p, in: tower)
        XCTAssertEqual(again.result, .skipped)
    }

    // MARK: Manifests and the event log

    func testSnapshotHidesOtherFlightsTitlesAndContacts() throws {
        let m = try tower.snapshotManifest(for: attorneyCred.id)
        let passes = try XCTUnwrap(m.snapshot?.boardingPasses)
        XCTAssertEqual(passes.first { $0.id == review.id }?.title, review.code)
        XCTAssertEqual(passes.first { $0.id == trust.id }?.title, "Trust Rewrite")
        XCTAssertTrue(m.snapshot?.crew.allSatisfy { $0.contact == nil } ?? false)
    }

    func testManifestRoundTripThroughYAML() throws {
        let snapshot = try tower.snapshotManifest(for: advisorCred.id)
        let reply = snapshot.reply(with: crewProposal(advisor, review, StatusChange(status: .departed)), sentAt: clock.now)
        let decoded = try Manifest.fromYAML(try reply.yaml())
        let p = try tower.receive(decoded)
        XCTAssertEqual(p.status, .pending)
        XCTAssertEqual(p.authorId, advisor.id)
    }

    func testManifestWithWrongKeyIsRefused() throws {
        var reply = try tower.snapshotManifest(for: advisorCred.id)
            .reply(with: crewProposal(advisor, review, StatusChange(status: .departed)), sentAt: clock.now)
        reply.keyCode = "WRONG1"
        XCTAssertThrowsError(try tower.receive(reply))
    }

    func testEventChainDetectsTampering() throws {
        try completeReview()
        XCTAssertNil(tower.state.log.verify())
        var log = tower.state.log
        var events = log.events
        events[2].payload["title"] = "edited"
        log = try JSONDecoder().decode(EventLog.self, from: JSONEncoder().encode(TamperedLog(events: events)))
        XCTAssertEqual(log.verify(), events[2].id)
    }

    func testSaveAndLoad() throws {
        try completeReview()
        let data = try tower.save()
        let loaded = try FlightTower.load(data)
        XCTAssertEqual(loaded.journey.boardingPasses.map(\.status), tower.journey.boardingPasses.map(\.status))
        XCTAssertNil(loaded.state.log.verify())
        XCTAssertNotNil(loaded.engine.packagePlugins["hcs.decision-nudge"])
    }

    func testArrivalWhenEveryFlightLandsAndEveryDocumentIsFiled() throws {
        try completeReview()
        for bp in tower.journey.boardingPasses.dropFirst() {
            _ = tower.submit(Proposal(boardingPassId: bp.id, authorId: captain.id, authorType: .member,
                                      reportedAt: clock.now, message: "close", statusChange: StatusChange(status: .landed)))
        }
        XCTAssertEqual(tower.journey.status, .arrived)
        XCTAssertEqual(tower.journey.destination.status, .achieved)
    }
}

struct TamperedLog: Encodable { var events: [Event] }

final class StubRuntime: ScriptRuntime {
    let output: String
    init(output: String) { self.output = output }
    func run(script: String, contextJSON: String) throws -> String { output }
}
