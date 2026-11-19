import XCTest
@testable import AvalonCore

final class AvalonCoreTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func sample() throws -> JourneySnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AvalonCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AvalonCore
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("samples/anti-hustle.avj")
        return try AVJ.loadSnapshot(contentsOf: url)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private var engine: DelayEngine { DelayEngine(rules: DelayRules(graceHours: 0, staleContactDays: 7), calendar: calendar) }

    // MARK: Loading

    func testLoadsSample() throws {
        let s = try sample()
        XCTAssertEqual(s.journey.id, "J-001")
        XCTAssertEqual(s.flights.map(\.code), ["AH-101", "AH-201", "AH-301", "AH-401"])
        XCTAssertEqual(s.flight("FL-201")?.eta, CalendarDay(year: 2026, month: 11, day: 26))
        XCTAssertEqual(s.flight("FL-401")?.kind, .customs)
        XCTAssertNil(s.flight("FL-401")?.airlineId)
        XCTAssertEqual(s.destination?.successCriteria.count, 3)
        XCTAssertEqual(s.events.first?.type, .journeyCreated)
        XCTAssertEqual(s.completion, 0)
    }

    func testRoundTrip() throws {
        let s = try sample()
        let package = JourneyPackage(journeyId: s.journey.id, sender: nil, recipient: nil,
                                     sentAt: nil, lastEventHash: nil, body: .snapshot(s))
        let yaml = try AVJ.encode(package)
        XCTAssertEqual(try AVJ.decode(yaml: yaml).snapshot?.flights, s.flights)
    }

    // MARK: Rule 1

    func testFlightBecomesDelayedAfterEtaDay() throws {
        var s = try sample()
        XCTAssertTrue(engine.tick(&s, now: date(2026, 11, 21, 23), towerId: "FT-001").isEmpty)

        let events = engine.tick(&s, now: date(2026, 11, 22, 1), towerId: "FT-001")
        XCTAssertEqual(events.map(\.flightId), ["FL-101"])
        XCTAssertEqual(events.first?.actor.kind, .tower)
        XCTAssertEqual(s.flight("FL-101")?.status, .delayed)
        XCTAssertNotNil(events.first?.eventHash)
        XCTAssertEqual(events.first?.previousEventHash, s.events[0].eventHash)

        // Ticking again records nothing new.
        XCTAssertTrue(engine.tick(&s, now: date(2026, 11, 23), towerId: "FT-001").isEmpty)
    }

    // MARK: Rule 2

    func testNoContactFromAircraft() throws {
        var flight = try XCTUnwrap(sample().flight("FL-101"))
        flight.lastContactAt = date(2026, 11, 1)
        XCTAssertFalse(engine.hasLostContact(flight, now: date(2026, 11, 7)))
        XCTAssertTrue(engine.hasLostContact(flight, now: date(2026, 11, 9)))
    }

    // MARK: Rule 3

    func testDelayedFlightEtaChangeNeedsReasonAndCause() throws {
        var s = try sample()
        engine.tick(&s, now: date(2026, 11, 22), towerId: "FT-001")
        let newEta = CalendarDay(year: 2026, month: 11, day: 24)
        let author = ActorRef(kind: .airline, id: "AL-001", operatedBy: .agent)

        let bare = Update(id: "UP-1", journeyId: "J-001", flightId: "FL-101", author: author,
                          reportedAt: date(2026, 11, 22), message: "Pushing",
                          statusChange: StatusChange(eta: newEta))
        XCTAssertThrowsError(try engine.apply(bare, to: &s, receivedAt: date(2026, 11, 22))) { error in
            XCTAssertEqual(error as? UpdateRejection, .missingJustification(missingReason: true, missingCause: true))
        }
        XCTAssertEqual(s.flight("FL-101")?.eta, CalendarDay(year: 2026, month: 11, day: 21), "rejected update changes nothing")

        var justified = bare
        justified.statusChange = StatusChange(eta: newEta, reason: "Waiting on chapter files from client", cause: .passenger)
        let events = try engine.apply(justified, to: &s, receivedAt: date(2026, 11, 22))
        XCTAssertEqual(events.map(\.type), [.etaChanged, .waitingOnChanged])
        XCTAssertEqual(s.flight("FL-101")?.eta, newEta)
        XCTAssertEqual(s.flight("FL-101")?.status, .delayed)
    }

    func testClearingDelayNeedsJustification() throws {
        var s = try sample()
        engine.tick(&s, now: date(2026, 11, 22), towerId: "FT-001")
        let landed = Update(id: "UP-2", journeyId: "J-001", flightId: "FL-101",
                            author: ActorRef(kind: .airline, id: "AL-001"), reportedAt: nil,
                            message: nil, statusChange: StatusChange(status: .landed))
        XCTAssertThrowsError(try engine.apply(landed, to: &s, receivedAt: date(2026, 11, 22)))
    }

    func testOnTimeFlightNeedsNoJustification() throws {
        var s = try sample()
        let update = Update(id: "UP-3", journeyId: "J-001", flightId: "FL-101",
                            author: ActorRef(kind: .airline, id: "AL-001"), reportedAt: date(2026, 11, 20),
                            message: "Done", statusChange: StatusChange(status: .landed))
        let events = try engine.apply(update, to: &s, receivedAt: date(2026, 11, 20))
        XCTAssertEqual(events.map(\.type), [.flightLanded])
        XCTAssertEqual(s.completion, 0.25)
    }

    // MARK: Rules 4 and 5

    func testBoardShowsBottleneckAndDelayChain() throws {
        var s = try sample()
        engine.tick(&s, now: date(2026, 11, 22), towerId: "FT-001")
        let update = Update(id: "UP-4", journeyId: "J-001", flightId: "FL-101",
                            author: ActorRef(kind: .airline, id: "AL-001"), reportedAt: date(2026, 11, 22),
                            message: nil,
                            statusChange: StatusChange(eta: CalendarDay(year: 2026, month: 11, day: 24),
                                                       reason: "Waiting on folders from client", cause: .passenger))
        try engine.apply(update, to: &s, receivedAt: date(2026, 11, 22))

        let rows = engine.boardRows(for: s, now: date(2026, 11, 22))
        XCTAssertEqual(rows.map(\.code), ["AH-101", "AH-201", "AH-301", "AH-401"])
        XCTAssertEqual(rows[0].bottleneck, "Client", "blame follows waitingOn, not the airline")
        XCTAssertEqual(rows[1].delayedBy, "AH-101")
        XCTAssertEqual(rows[3].delayedBy, "AH-101")
        XCTAssertEqual(rows[3].operatorName, "Kole")
    }

    // MARK: Appending YAML

    func testAppendTemplateUpdatePackage() throws {
        var s = try sample()
        let flight = try XCTUnwrap(s.flight("FL-101"))
        let yaml = AVJ.updateTemplate(for: flight, in: s, now: date(2026, 11, 20))
            .replacingOccurrences(of: "status: scheduled", with: "status: landed")
        let events = try engine.append(yaml: yaml, to: &s, receivedAt: date(2026, 11, 20))
        XCTAssertEqual(events.map(\.type), [.flightLanded])
        XCTAssertEqual(s.updates.count, 1)
    }

    func testAppendBareUpdateIsRejectedForDelayedFlightWithoutCause() throws {
        var s = try sample()
        engine.tick(&s, now: date(2026, 11, 22), towerId: "FT-001")
        let yaml = """
        update:
          id: UP-9
          flightId: FL-101
          author: { kind: airline, id: AL-001, operatedBy: agent }
          statusChange:
            eta: 2026-11-28
            reason: Waiting on chapter files
        """
        XCTAssertThrowsError(try engine.append(yaml: yaml, to: &s, receivedAt: date(2026, 11, 22))) { error in
            XCTAssertEqual(error as? UpdateRejection, .missingJustification(missingReason: false, missingCause: true))
        }
    }

    func testAppendRefusesSnapshotsAndOtherJourneys() throws {
        var s = try sample()
        let snapshotYAML = try AVJ.encodeSnapshot(s, sender: nil, recipient: nil, sentAt: Date())
        XCTAssertThrowsError(try engine.append(yaml: snapshotYAML, to: &s, receivedAt: Date())) { error in
            XCTAssertEqual(error as? AppendError, .snapshotNotAppendable)
        }
        let other = AVJ.updateTemplate(for: s.flights[0], in: s, now: Date())
            .replacingOccurrences(of: "journeyId: J-001", with: "journeyId: J-999")
        XCTAssertThrowsError(try engine.append(yaml: other, to: &s, receivedAt: Date()))
        XCTAssertThrowsError(try engine.append(yaml: "hello: world", to: &s, receivedAt: Date())) { error in
            XCTAssertEqual(error as? AppendError, .unrecognised)
        }
    }

    func testSnapshotYAMLRoundTripsAfterAppend() throws {
        var s = try sample()
        engine.tick(&s, now: date(2026, 11, 22), towerId: "FT-001")
        let yaml = try AVJ.encodeSnapshot(s, sender: nil, recipient: nil, sentAt: date(2026, 11, 22))
        let reloaded = try XCTUnwrap(AVJ.decode(yaml: yaml).snapshot)
        XCTAssertEqual(reloaded.events.map(\.eventHash), s.events.map(\.eventHash))
        XCTAssertEqual(reloaded.flight("FL-101")?.status, .delayed)
    }

    func testTowerYAMLRoundTrip() throws {
        let tower = FlightTower(id: "FT-001", journeyId: "J-001", controllerIds: ["P-001"], activeControllerId: "P-001",
                                delayRules: DelayRules(graceHours: 12, staleContactDays: 3))
        XCTAssertEqual(try FlightTower.decode(yaml: tower.yaml()), tower)
    }

    // MARK: Lounge and Atlas

    func testLoungeAndArrival() throws {
        var s = try sample()
        s.ensureLounge()
        XCTAssertEqual(s.lounge?.memberIds, ["P-001", "P-002"])
        s.addDecision(title: "Cut chapter 9", rationale: "Repeats chapter 4", approvedBy: "P-001", at: date(2026, 11, 20))
        XCTAssertEqual(s.lounge?.decisions.first?.id, "DC-001")

        let event = s.arrive(at: date(2026, 12, 12), actor: ActorRef(kind: .passenger, id: "P-001"), summary: "Done")
        XCTAssertEqual(event?.type, .destinationAchieved)
        XCTAssertEqual(s.journey.status, .arrived)
        XCTAssertEqual(s.destination?.status, .achieved)
        XCTAssertEqual(s.atlas.first?.repositoryIds, ["R-001"])
        XCTAssertNil(s.arrive(at: date(2026, 12, 13), actor: ActorRef(kind: .passenger, id: "P-001"), summary: nil),
                     "arriving twice does nothing")
    }
}
