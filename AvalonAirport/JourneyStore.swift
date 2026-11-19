import Foundation
import Observation
import AvalonCore

/// The active controller's device: holds the journey, its FlightTower, and runs the delay rules.
@MainActor
@Observable
final class JourneyStore {
    private(set) var snapshot: JourneySnapshot?
    private(set) var tower: FlightTower?
    private(set) var loadError: String?
    /// Simulated days added to the real clock, to watch the delay rules fire.
    private(set) var clockOffsetDays = 0

    init() {
        loadSample()
    }

    var now: Date {
        Calendar.current.date(byAdding: .day, value: clockOffsetDays, to: Date()) ?? Date()
    }

    private var engine: DelayEngine {
        DelayEngine(rules: tower?.delayRules ?? DelayRules())
    }

    var boardRows: [BoardRow] {
        guard let snapshot else { return [] }
        return engine.boardRows(for: snapshot, now: now)
    }

    // MARK: Loading

    func loadSample() {
        do {
            let snapshot = try AVJ.loadSnapshot(contentsOf: Self.sampleURL())
            let journey = snapshot.journey
            // The tower never travels in a package; it lives only on this device.
            tower = FlightTower(id: journey.flightTowerId ?? "FT-001",
                                journeyId: journey.id,
                                controllerIds: Array(journey.passengerIds.prefix(1)),
                                activeControllerId: journey.passengerIds.first)
            self.snapshot = snapshot
            clockOffsetDays = 0
            loadError = nil
            tick()
        } catch {
            snapshot = nil
            loadError = "Could not load anti-hustle.avj: \(error.localizedDescription)"
        }
    }

    private static func sampleURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "anti-hustle", withExtension: AVJ.fileExtension) {
            return url
        }
        #if DEBUG && targetEnvironment(simulator)
        // Simulator fallback: read straight from the repository checkout.
        let repoCopy = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("samples/anti-hustle.avj")
        if FileManager.default.fileExists(atPath: repoCopy.path) { return repoCopy }
        #endif
        throw CocoaError(.fileNoSuchFile)
    }

    // MARK: Tower actions

    /// Runs delay rule 1 against the current (possibly simulated) clock.
    func tick() {
        guard var snapshot, let tower else { return }
        let events = engine.tick(&snapshot, now: now, towerId: tower.id)
        if !events.isEmpty { self.snapshot = snapshot }
    }

    func advanceClock(days: Int) {
        clockOffsetDays += days
        tick()
    }

    /// Returns to real time. Delays already recorded stay: the log is append-only.
    func resetClock() {
        clockOffsetDays = 0
    }

    /// Applies an Update on the controller's device. Throws `UpdateRejection` (rule 3).
    func submit(_ update: Update) throws {
        guard var snapshot else { return }
        try engine.apply(update, to: &snapshot, receivedAt: now)
        self.snapshot = snapshot
        tick()
    }
}
