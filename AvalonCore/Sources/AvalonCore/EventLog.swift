import Foundation
import CryptoKit

public enum EventType: String, Codable, CaseIterable, Sendable {
    case journeyCreated = "journey_created"
    case boardingPassCreated = "boarding_pass_created"
    case statusChanged = "status_changed"
    case etaChanged = "eta_changed"
    case flightDelayed = "flight_delayed"
    case flightDeparted = "flight_departed"
    case flightLanded = "flight_landed"
    case waitingOnChanged = "waiting_on_changed"
    case waypointReached = "waypoint_reached"
    case proposalSubmitted = "proposal_submitted"
    case proposalApproved = "proposal_approved"
    case proposalAutoApproved = "proposal_auto_approved"
    case proposalRejected = "proposal_rejected"
    case proposalBlocked = "proposal_blocked"
    case deliverableSent = "deliverable_sent"
    case deliverableReceived = "deliverable_received"
    case deliverableReviewed = "deliverable_reviewed"
    case deliverableFiled = "deliverable_filed"
    case credentialIssued = "credential_issued"
    case credentialRevoked = "credential_revoked"
    case storageGranted = "storage_granted"
    case storageRevoked = "storage_revoked"
    case actionExecuted = "action_executed"
    case connectorLinked = "connector_linked"
    case destinationAchieved = "destination_achieved"
}

public struct EventActor: Codable, Hashable, Sendable {
    public var kind: AuthorType
    public var id: String
    public init(kind: AuthorType, id: String) { self.kind = kind; self.id = id }
    public static let tower = EventActor(kind: .tower, id: "tower")
}

/// Immutable history. Never edited, never deleted.
public struct Event: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var type: EventType
    public var actor: EventActor
    public var boardingPassId: String?
    public var reportedAt: Date
    public var receivedAt: Date
    public var payload: [String: String]
    public var previousEventHash: String?
    public var eventHash: String
    public var signature: String?
}

/// Hash-chained, append-only log. Each event's hash covers its content and the previous hash,
/// so any edit or gap is detectable with `verify()`.
public struct EventLog: Codable, Hashable, Sendable {
    public private(set) var events: [Event] = []

    public init() {}

    public var lastHash: String? { events.last?.eventHash }

    @discardableResult
    public mutating func append(_ type: EventType, actor: EventActor, boardingPassId: String? = nil,
                                reportedAt: Date, receivedAt: Date, payload: [String: String] = [:]) -> Event {
        let id = "EV-\(String(format: "%04d", events.count + 1))"
        let previous = lastHash
        let hash = Self.hash(id: id, type: type, actor: actor, boardingPassId: boardingPassId,
                             reportedAt: reportedAt, receivedAt: receivedAt, payload: payload, previous: previous)
        let event = Event(id: id, type: type, actor: actor, boardingPassId: boardingPassId,
                          reportedAt: reportedAt, receivedAt: receivedAt, payload: payload,
                          previousEventHash: previous, eventHash: hash, signature: nil)
        events.append(event)
        return event
    }

    /// Recomputes every hash. Returns the id of the first broken event, or nil when the chain is intact.
    public func verify() -> String? {
        var previous: String? = nil
        for e in events {
            let expected = Self.hash(id: e.id, type: e.type, actor: e.actor, boardingPassId: e.boardingPassId,
                                     reportedAt: e.reportedAt, receivedAt: e.receivedAt, payload: e.payload,
                                     previous: previous)
            if e.previousEventHash != previous || e.eventHash != expected { return e.id }
            previous = e.eventHash
        }
        return nil
    }

    static func hash(id: String, type: EventType, actor: EventActor, boardingPassId: String?,
                     reportedAt: Date, receivedAt: Date, payload: [String: String], previous: String?) -> String {
        let payloadText = payload.keys.sorted().map { "\($0)=\(payload[$0]!)" }.joined(separator: "&")
        let parts = [id, type.rawValue, actor.kind.rawValue, actor.id, boardingPassId ?? "",
                     String(reportedAt.timeIntervalSince1970), String(receivedAt.timeIntervalSince1970),
                     payloadText, previous ?? ""]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum Hashing {
    /// Hex SHA-256, used as the stand-in signature for package plugin scripts.
    public static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
