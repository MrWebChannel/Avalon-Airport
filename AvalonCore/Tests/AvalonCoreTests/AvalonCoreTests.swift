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
}
