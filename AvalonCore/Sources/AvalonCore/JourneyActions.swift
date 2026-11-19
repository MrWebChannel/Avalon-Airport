import Foundation
import Yams

// MARK: - Appending YAML to a journey

/// What a pasted or received YAML document turned out to be.
public enum IncomingYAML: Sendable {
    /// A full `.avj` package (`journeyPackage:` root).
    case package(JourneyPackage)
    /// A bare update (`update:` root), as an airline or agent might write by hand.
    case update(Update)
}

public enum AppendError: Error, LocalizedError, Equatable {
    case unrecognised
    case wrongJourney(expected: String, got: String)
    case snapshotNotAppendable
    case invalidYAML(String)

    public var errorDescription: String? {
        switch self {
        case .unrecognised:
            return "Expected a document starting with journeyPackage: or update:."
        case let .wrongJourney(expected, got):
            return "This package is for journey \(got), not \(expected)."
        case .snapshotNotAppendable:
            return "This is a snapshot package. Only update packages can be appended; the controller's journey is never overwritten."
        case .invalidYAML(let detail):
            return "Could not read the YAML: \(detail)"
        }
    }
}

extension AVJ {
    /// Reads a YAML document meant to be appended to a journey.
    public static func decodeIncoming(yaml: String) throws -> IncomingYAML {
        let node: Node?
        do {
            node = try Yams.compose(yaml: yaml)
        } catch {
            throw AppendError.invalidYAML(String(describing: error))
        }
        guard let mapping = node?.mapping else { throw AppendError.unrecognised }
        do {
            if mapping["journeyPackage"] != nil {
                return .package(try decode(yaml: yaml))
            }
            if mapping["update"] != nil {
                return .update(try YAMLDecoder().decode(UpdateBody.self, from: yaml).update)
            }
        } catch let error as AVJError {
            throw error
        } catch {
            throw AppendError.invalidYAML(Self.describe(error))
        }
        throw AppendError.unrecognised
    }

    /// The current journey as a snapshot `.avj` document.
    public static func encodeSnapshot(_ snapshot: JourneySnapshot, sender: ActorRef?, recipient: ActorRef?,
                                      sentAt: Date) throws -> String {
        try encode(JourneyPackage(journeyId: snapshot.journey.id, sender: sender, recipient: recipient,
                                  sentAt: sentAt, lastEventHash: snapshot.events.last?.eventHash,
                                  body: .snapshot(snapshot)))
    }

    /// A starter update package an airline would send for `flight`.
    public static func updateTemplate(for flight: Flight, in snapshot: JourneySnapshot, now: Date) -> String {
        let author = flight.airlineId.map { "{ kind: airline, id: \($0), operatedBy: human }" }
            ?? "{ kind: passenger, id: \(flight.holder?.id ?? snapshot.journey.passengerIds.first ?? "P-001"), operatedBy: human }"
        let stamp = ISO8601DateFormatter().string(from: now)
        let eta = flight.eta?.description ?? ""
        return """
        journeyPackage:
          schemaVersion: \(schemaVersion)
          kind: update
          journeyId: \(snapshot.journey.id)
          sender: \(author)
          sentAt: \(stamp)
          body:
            update:
              id: UP-\(UUID().uuidString.prefix(8))
              journeyId: \(snapshot.journey.id)
              flightId: \(flight.id)
              author: \(author)
              reportedAt: \(stamp)
              message: |
                Describe what happened on \(flight.code).
              statusChange:
                status: \(flight.status.rawValue)
                eta: \(eta)
                reason:
                cause:

        """
    }

    static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, let context):
                return "missing \(path(context.codingPath + [key]))"
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                return "\(path(context.codingPath)): \(context.debugDescription)"
            @unknown default:
                break
            }
        }
        return String(describing: error)
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}

extension DelayEngine {
    /// Appends a YAML update (package or bare) to the journey via the delay rules.
    /// Rejected updates change nothing.
    @discardableResult
    public func append(yaml: String, to snapshot: inout JourneySnapshot, receivedAt: Date) throws -> [Event] {
        let update: Update
        switch try AVJ.decodeIncoming(yaml: yaml) {
        case .update(let bare):
            update = bare
        case .package(let package):
            guard package.journeyId == snapshot.journey.id else {
                throw AppendError.wrongJourney(expected: snapshot.journey.id, got: package.journeyId)
            }
            switch package.body {
            case .update(let body): update = body.update
            case .snapshot: throw AppendError.snapshotNotAppendable
            }
        }
        if let journeyId = update.journeyId, journeyId != snapshot.journey.id {
            throw AppendError.wrongJourney(expected: snapshot.journey.id, got: journeyId)
        }
        return try apply(update, to: &snapshot, receivedAt: receivedAt)
    }
}

// MARK: - FlightTower file (device only)

extension FlightTower {
    private struct Document: Codable { var flightTower: FlightTower }

    /// The tower as YAML. Saved on the controller's device only, never in a package.
    public func yaml() throws -> String {
        try YAMLEncoder().encode(Document(flightTower: self))
    }

    public static func decode(yaml: String) throws -> FlightTower {
        try YAMLDecoder().decode(Document.self, from: yaml).flightTower
    }
}

// MARK: - Lounge and Atlas

extension JourneySnapshot {
    /// The Lounge, created from the journey's passengers if the package did not carry one.
    public mutating func ensureLounge() {
        guard lounge == nil else { return }
        lounge = Lounge(id: journey.loungeId ?? "LG-001", journeyId: journey.id, memberIds: journey.passengerIds)
    }

    public mutating func addDecision(title: String, rationale: String?, approvedBy: String?, at: Date) {
        ensureLounge()
        let next = (lounge?.decisions.count ?? 0) + 1
        lounge?.decisions.append(Decision(id: String(format: "DC-%03d", next), title: title,
                                          rationale: rationale, approvedBy: approvedBy, at: at))
    }

    public mutating func addLoungeNote(_ note: String) {
        ensureLounge()
        lounge?.conversations.append(note)
    }

    /// Marks the destination achieved: logs `destination_achieved`, sets the journey to arrived,
    /// and records the trip in the Atlas.
    @discardableResult
    public mutating func arrive(at date: Date, actor: ActorRef, summary: String?) -> Event? {
        guard var destination, destination.status != .achieved else { return nil }
        destination.status = .achieved
        destination.achievedAt = date
        self.destination = destination
        journey.status = .arrived
        journey.updatedAt = date

        var log = EventLog(events: events)
        let event = log.append(type: .destinationAchieved, journeyId: journey.id, flightId: nil, actor: actor,
                               reportedAt: date, receivedAt: date,
                               payload: EventPayload(message: summary))
        events = log.events

        atlas.append(AtlasEntry(id: String(format: "AE-%03d", atlas.count + 1),
                                journeyId: journey.id,
                                destinationId: destination.id,
                                title: destination.title,
                                startedAt: journey.createdAt,
                                completedAt: date,
                                summary: summary,
                                repositoryIds: journey.repositoryIds))
        return event
    }
}
