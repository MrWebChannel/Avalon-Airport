import Foundation
import Yams

// MARK: - Snapshot

/// A journey as carried in a snapshot package (controller → others).
/// Already filtered by the recipient's BoardingPass; never contains the FlightTower.
public struct JourneySnapshot: Codable, Hashable, Sendable {
    public var journey: Journey
    public var destination: Destination?
    @DefaultEmpty public var passengers: [Passenger]
    @DefaultEmpty public var airlines: [Airline]
    @DefaultEmpty public var flights: [Flight]
    @DefaultEmpty public var repositories: [Repository]
    @DefaultEmpty public var boardingPasses: [BoardingPass]
    public var lounge: Lounge?
    @DefaultEmpty public var atlas: [AtlasEntry]
    @DefaultEmpty public var updates: [Update]
    @DefaultEmpty public var events: [Event]

    public func flight(_ id: String?) -> Flight? {
        guard let id else { return nil }
        return flights.first { $0.id == id }
    }

    public func passenger(_ id: String?) -> Passenger? {
        guard let id else { return nil }
        return passengers.first { $0.id == id }
    }

    public func airline(_ id: String?) -> Airline? {
        guard let id else { return nil }
        return airlines.first { $0.id == id }
    }

    /// Journey completion, 0…1. Computed from flight states, never stored.
    public var completion: Double {
        let counted = flights.filter { $0.status != .cancelled }
        guard !counted.isEmpty else { return 0 }
        return Double(counted.filter { $0.status.isComplete }.count) / Double(counted.count)
    }

    /// Flights in dependency order (a flight comes after everything it depends on).
    /// Ties keep the journey's `flightIds` order. Cycles are appended at the end.
    public var orderedFlights: [Flight] {
        let order = journey.flightIds
        let ranked = flights.sorted {
            (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
        }
        let known = Set(ranked.map(\.id))
        var placed = Set<String>()
        var result: [Flight] = []
        var remaining = ranked
        while !remaining.isEmpty {
            guard let next = remaining.firstIndex(where: { flight in
                flight.dependsOn.allSatisfy { placed.contains($0) || !known.contains($0) }
            }) else {
                result += remaining // dependency cycle; keep them visible
                break
            }
            let flight = remaining.remove(at: next)
            placed.insert(flight.id)
            result.append(flight)
        }
        return result
    }
}

/// Body of an update package (provider → controller): exactly one Update.
public struct UpdateBody: Codable, Hashable, Sendable {
    public var update: Update

    public init(update: Update) { self.update = update }
}

// MARK: - JourneyPackage (.avj)

public enum PackageKind: String, Codable, Hashable, Sendable {
    case snapshot, update
}

public enum PackageBody: Hashable, Sendable {
    case snapshot(JourneySnapshot)
    case update(UpdateBody)
}

/// The file traded between devices by Messages, email or AirDrop.
public struct JourneyPackage: Codable, Hashable, Sendable {
    public var schemaVersion: String
    public var kind: PackageKind
    public var journeyId: String
    public var sender: ActorRef?
    public var recipient: ActorRef?
    public var sentAt: Date?
    /// Lets the receiver detect gaps.
    public var lastEventHash: String?
    public var body: PackageBody

    public init(schemaVersion: String = AVJ.schemaVersion, journeyId: String, sender: ActorRef?,
                recipient: ActorRef?, sentAt: Date?, lastEventHash: String?, body: PackageBody) {
        self.schemaVersion = schemaVersion
        self.journeyId = journeyId
        self.sender = sender
        self.recipient = recipient
        self.sentAt = sentAt
        self.lastEventHash = lastEventHash
        self.body = body
        switch body {
        case .snapshot: kind = .snapshot
        case .update: kind = .update
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, journeyId, sender, recipient, sentAt, lastEventHash, body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        kind = try c.decode(PackageKind.self, forKey: .kind)
        journeyId = try c.decode(String.self, forKey: .journeyId)
        sender = try c.decodeIfPresent(ActorRef.self, forKey: .sender)
        recipient = try c.decodeIfPresent(ActorRef.self, forKey: .recipient)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        lastEventHash = try c.decodeIfPresent(String.self, forKey: .lastEventHash)
        switch kind {
        case .snapshot: body = .snapshot(try c.decode(JourneySnapshot.self, forKey: .body))
        case .update: body = .update(try c.decode(UpdateBody.self, forKey: .body))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(kind, forKey: .kind)
        try c.encode(journeyId, forKey: .journeyId)
        try c.encodeIfPresent(sender, forKey: .sender)
        try c.encodeIfPresent(recipient, forKey: .recipient)
        try c.encodeIfPresent(sentAt, forKey: .sentAt)
        try c.encodeIfPresent(lastEventHash, forKey: .lastEventHash)
        switch body {
        case .snapshot(let snapshot): try c.encode(snapshot, forKey: .body)
        case .update(let update): try c.encode(update, forKey: .body)
        }
    }

    public var snapshot: JourneySnapshot? {
        if case .snapshot(let s) = body { return s }
        return nil
    }
}

// MARK: - Loading and saving

public enum AVJError: Error, LocalizedError, Equatable {
    case unsupportedSchema(String)
    case notASnapshot

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let v): return "Unsupported .avj schema version \(v) (expected \(AVJ.schemaVersion))."
        case .notASnapshot: return "This .avj file is an update, not a journey snapshot."
        }
    }
}

/// Reads and writes `.avj` journey packages (YAML, top-level key `journeyPackage`).
public enum AVJ {
    public static let schemaVersion = "0.2"
    public static let fileExtension = "avj"

    private struct Document: Codable {
        var journeyPackage: JourneyPackage
    }

    public static func decode(yaml: String) throws -> JourneyPackage {
        let package = try YAMLDecoder().decode(Document.self, from: yaml).journeyPackage
        guard package.schemaVersion.split(separator: ".").first == schemaVersion.split(separator: ".").first else {
            throw AVJError.unsupportedSchema(package.schemaVersion)
        }
        return package
    }

    public static func decode(data: Data) throws -> JourneyPackage {
        try decode(yaml: String(decoding: data, as: UTF8.self))
    }

    public static func load(contentsOf url: URL) throws -> JourneyPackage {
        try decode(data: Data(contentsOf: url))
    }

    /// Convenience: load a file that must be a snapshot.
    public static func loadSnapshot(contentsOf url: URL) throws -> JourneySnapshot {
        guard let snapshot = try load(contentsOf: url).snapshot else { throw AVJError.notASnapshot }
        return snapshot
    }

    public static func encode(_ package: JourneyPackage) throws -> String {
        try YAMLEncoder().encode(Document(journeyPackage: package))
    }
}
