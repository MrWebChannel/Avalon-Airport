import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Append-only, hash-chained event log. Events are never edited or deleted.
public struct EventLog: Sendable {
    public private(set) var events: [Event]

    public init(events: [Event] = []) {
        self.events = events
    }

    public var lastEventHash: String? { events.last?.eventHash }

    @discardableResult
    public mutating func append(type: EventType,
                                journeyId: String?,
                                flightId: String?,
                                actor: ActorRef,
                                reportedAt: Date?,
                                receivedAt: Date,
                                payload: EventPayload?) -> Event {
        var event = Event(id: nextId(),
                          journeyId: journeyId,
                          flightId: flightId,
                          actor: actor,
                          type: type,
                          reportedAt: reportedAt,
                          receivedAt: receivedAt,
                          payload: payload,
                          previousEventHash: lastEventHash,
                          eventHash: nil,
                          signature: nil)
        event.eventHash = Self.hash(of: event)
        events.append(event)
        return event
    }

    private func nextId() -> String {
        let highest = events.compactMap { event -> Int? in
            guard event.id.hasPrefix("EV-") else { return nil }
            return Int(event.id.dropFirst(3))
        }.max() ?? 0
        return String(format: "EV-%04d", highest + 1)
    }

    /// SHA-256 over a canonical line of the event's fields plus the previous hash.
    public static func hash(of event: Event) -> String? {
        let p = event.payload
        let fields: [String] = [
            event.previousEventHash ?? "",
            event.id,
            event.journeyId ?? "",
            event.flightId ?? "",
            event.actor.kind.rawValue,
            event.actor.id ?? "",
            event.actor.operatedBy?.rawValue ?? "",
            event.type.rawValue,
            event.reportedAt.map { String($0.timeIntervalSince1970) } ?? "",
            event.receivedAt.map { String($0.timeIntervalSince1970) } ?? "",
            p?.previousEta?.description ?? "",
            p?.newEta?.description ?? "",
            p?.previousStatus?.rawValue ?? "",
            p?.status?.rawValue ?? "",
            p?.reason ?? "",
            p?.cause?.rawValue ?? "",
            p?.waitingOn?.kind?.rawValue ?? "",
            p?.waitingOn?.ref ?? "",
            p?.message ?? ""
        ]
        let canonical = fields.joined(separator: "|")
        #if canImport(CryptoKit)
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }
}
