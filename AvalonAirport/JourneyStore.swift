import Foundation
import Observation
import AvalonCore

/// The active controller's device: holds the journey, its FlightTower, runs the delay rules,
/// and saves both to local storage after every change.
@MainActor
@Observable
final class JourneyStore {
    private(set) var snapshot: JourneySnapshot?
    private(set) var tower: FlightTower?
    private(set) var loadError: String?
    private(set) var saveError: String?
    /// Simulated days added to the real clock, to watch the delay rules fire.
    private(set) var clockOffsetDays = 0

    init() {
        load()
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

    /// The person acting on this device: the tower's active controller.
    var controllerActor: ActorRef {
        ActorRef(kind: .passenger, id: tower?.activeControllerId, operatedBy: .human)
    }

    // MARK: - Loading and saving

    /// Opens the saved journey if there is one, otherwise the bundled sample.
    func load() {
        if let saved = try? Data(contentsOf: Self.journeyFile),
           let snapshot = try? AVJ.decode(data: saved).snapshot {
            let tower = (try? String(contentsOf: Self.towerFile, encoding: .utf8))
                .flatMap { try? FlightTower.decode(yaml: $0) }
            install(snapshot, tower: tower)
        } else {
            loadSample()
        }
    }

    /// Discards the saved journey and starts again from samples/anti-hustle.avj.
    func loadSample() {
        do {
            install(try AVJ.loadSnapshot(contentsOf: Self.sampleURL()), tower: nil)
            save()
        } catch {
            snapshot = nil
            loadError = "Could not load anti-hustle.avj: \(error.localizedDescription)"
        }
    }

    private func install(_ snapshot: JourneySnapshot, tower: FlightTower?) {
        var snapshot = snapshot
        snapshot.ensureLounge()
        let journey = snapshot.journey
        // The tower never travels in a package; it lives only on this device.
        self.tower = tower ?? FlightTower(id: journey.flightTowerId ?? "FT-001",
                                          journeyId: journey.id,
                                          controllerIds: Array(journey.passengerIds.prefix(1)),
                                          activeControllerId: journey.passengerIds.first)
        self.snapshot = snapshot
        clockOffsetDays = 0
        loadError = nil
        tick()
    }

    private func save() {
        guard snapshot != nil, let tower else { return }
        do {
            try FileManager.default.createDirectory(at: Self.storageDirectory, withIntermediateDirectories: true)
            try exportYAML().write(to: Self.journeyFile, atomically: true, encoding: .utf8)
            try tower.yaml().write(to: Self.towerFile, atomically: true, encoding: .utf8)
            saveError = nil
        } catch {
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Commits a change made to a copy of the snapshot, then saves.
    private func commit(_ change: (inout JourneySnapshot) throws -> Void) rethrows {
        guard var snapshot else { return }
        try change(&snapshot)
        self.snapshot = snapshot
        save()
    }

    private static var storageDirectory: URL {
        #if os(tvOS)
        // tvOS has no guaranteed persistent storage; caches survive relaunches but may be purged.
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        return base.appendingPathComponent("Journeys", isDirectory: true)
    }

    /// The journey as it would be sent: a snapshot `.avj` file.
    static var journeyFile: URL { storageDirectory.appendingPathComponent("journey.avj") }
    /// Device-only governance; never shared.
    static var towerFile: URL { storageDirectory.appendingPathComponent("tower.yaml") }

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

    // MARK: - YAML

    func exportYAML() throws -> String {
        guard let snapshot else { return "" }
        return try AVJ.encodeSnapshot(snapshot, sender: controllerActor, recipient: controllerActor, sentAt: now)
    }

    func towerYAML() throws -> String {
        try tower?.yaml() ?? ""
    }

    func updateTemplate(for flightId: String?) -> String {
        guard let snapshot, let flight = snapshot.flight(flightId) ?? snapshot.orderedFlights.first else { return "" }
        return AVJ.updateTemplate(for: flight, in: snapshot, now: now)
    }

    /// Appends an update (package or bare) to the journey. Throws if the YAML is
    /// unreadable, for another journey, or rejected by the delay rules.
    @discardableResult
    func appendYAML(_ yaml: String) throws -> [Event] {
        var events: [Event] = []
        try commit { snapshot in
            events = try engine.append(yaml: yaml, to: &snapshot, receivedAt: now)
        }
        tick()
        return events
    }

    // MARK: - Tower actions

    /// Runs delay rule 1 against the current (possibly simulated) clock.
    func tick() {
        guard var snapshot, let tower else { return }
        let events = engine.tick(&snapshot, now: now, towerId: tower.id)
        if !events.isEmpty {
            self.snapshot = snapshot
            save()
        }
    }

    func advanceClock(days: Int) {
        clockOffsetDays += days
        tick()
    }

    /// Returns to real time. Delays already recorded stay: the log is append-only.
    func resetClock() {
        clockOffsetDays = 0
    }

    func setDelayRules(_ rules: DelayRules) {
        tower?.delayRules = rules
        save()
        tick()
    }

    /// Applies an Update on the controller's device. Throws `UpdateRejection` (rule 3).
    func submit(_ update: Update) throws {
        try commit { snapshot in
            try engine.apply(update, to: &snapshot, receivedAt: now)
        }
        tick()
    }

    // MARK: - Lounge

    func addDecision(title: String, rationale: String?, approvedBy: String?) {
        commit { $0.addDecision(title: title, rationale: rationale, approvedBy: approvedBy, at: now) }
    }

    func addLoungeNote(_ note: String) {
        commit { $0.addLoungeNote(note) }
    }

    func setConciergeAccess(_ allowed: Bool) {
        commit { snapshot in
            snapshot.ensureLounge()
            snapshot.lounge?.conciergeAccess = allowed
        }
    }

    // MARK: - Atlas

    func arrive(summary: String?) {
        commit { _ = $0.arrive(at: now, actor: controllerActor, summary: summary) }
    }
}
