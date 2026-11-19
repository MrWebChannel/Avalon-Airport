import Foundation

/// Why an Update was refused.
public enum UpdateRejection: Error, LocalizedError, Equatable {
    case unknownFlight(String)
    /// Delay rule 3: changing the ETA of a delayed flight, clearing a delay, or
    /// declaring one needs both a reason and a cause.
    case missingJustification(missingReason: Bool, missingCause: Bool)

    public var errorDescription: String? {
        switch self {
        case .unknownFlight(let id):
            return "No flight \(id) on this journey."
        case let .missingJustification(missingReason, missingCause):
            let missing = [missingReason ? "a reason" : nil, missingCause ? "a cause" : nil]
                .compactMap { $0 }.joined(separator: " and ")
            return "This flight is delayed. Changing its ETA or status needs \(missing)."
        }
    }
}

/// One line on the flight board, with all delay rules applied.
public struct BoardRow: Identifiable, Hashable, Sendable {
    public var id: String { flight.id }
    public var flight: Flight
    /// Airline name, or the customs holder.
    public var operatorName: String
    /// Rule 2: no update for longer than `staleContactDays`.
    public var noContact: Bool
    /// Rule 5: the nearest delayed flight upstream on the `dependsOn` chain.
    public var delayedBy: String?
    /// Rule 4: who or what is holding this flight (follows `waitingOn`).
    public var bottleneck: String?

    public var code: String { flight.code }
    public var status: FlightStatus { flight.status }
    public var isDelayed: Bool { flight.status == .delayed }
    public var etaSlipped: Bool {
        guard let eta = flight.eta, let original = flight.originalEta else { return false }
        return eta > original
    }

    /// Board remarks, most important first.
    public var remarks: [String] {
        var result: [String] = []
        if noContact { result.append("No contact from aircraft") }
        if let delayedBy { result.append("Delayed by \(delayedBy)") }
        if let bottleneck, bottleneck != delayedBy { result.append("Waiting on \(bottleneck)") }
        return result
    }
}

/// The delay rules from spec/domain-model.md. Runs on the controller's device.
/// Pure: pass in `now` so behaviour is deterministic and testable.
public struct DelayEngine: Sendable {
    public var rules: DelayRules
    public var calendar: Calendar

    public init(rules: DelayRules = DelayRules(), calendar: Calendar = .current) {
        self.rules = rules
        self.calendar = calendar
    }

    // MARK: Rule 1 — ETA passed

    /// ETAs are calendar days: a flight is due by the end of its ETA day,
    /// then gets `graceHours` before it is late.
    public func deadline(for flight: Flight) -> Date? {
        guard let start = flight.eta?.startOfDay(in: calendar),
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return endOfDay.addingTimeInterval(rules.graceHours * 3600)
    }

    public func isOverdue(_ flight: Flight, now: Date) -> Bool {
        guard !flight.status.isTerminal, let deadline = deadline(for: flight) else { return false }
        return now > deadline
    }

    /// Applies rule 1: every overdue flight becomes delayed, and the tower records
    /// a `flight_delayed` event. Returns the new events.
    @discardableResult
    public func tick(_ snapshot: inout JourneySnapshot, now: Date, towerId: String) -> [Event] {
        var log = EventLog(events: snapshot.events)
        var newEvents: [Event] = []
        for index in snapshot.flights.indices {
            let flight = snapshot.flights[index]
            guard flight.status != .delayed, isOverdue(flight, now: now) else { continue }
            snapshot.flights[index].status = .delayed
            newEvents.append(log.append(
                type: .flightDelayed,
                journeyId: snapshot.journey.id,
                flightId: flight.id,
                actor: .tower(towerId),
                reportedAt: now,
                receivedAt: now,
                payload: EventPayload(newEta: flight.eta,
                                      previousStatus: flight.status,
                                      status: .delayed,
                                      reason: "ETA passed without landing",
                                      cause: flight.waitingOn?.kind)))
        }
        if !newEvents.isEmpty {
            snapshot.events = log.events
            snapshot.journey.updatedAt = now
        }
        return newEvents
    }

    // MARK: Rule 2 — no contact

    public func hasLostContact(_ flight: Flight, now: Date) -> Bool {
        guard !flight.status.isTerminal, let last = flight.lastContactAt else { return false }
        return now.timeIntervalSince(last) > Double(rules.staleContactDays) * 86_400
    }

    // MARK: Rule 3 — delayed flights need a reason and a cause

    public func validate(_ update: Update, for flight: Flight) throws {
        guard let change = update.statusChange else { return } // message only
        let changesEta = change.eta != nil && change.eta != flight.eta
        let clearsDelay = flight.status == .delayed && change.status != nil && change.status != .delayed
        let declaresDelay = change.status == .delayed && flight.status != .delayed
        let needsJustification = (flight.status == .delayed && (changesEta || clearsDelay)) || declaresDelay
        guard needsJustification else { return }

        let missingReason = (change.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingCause = change.cause == nil
        if missingReason || missingCause {
            throw UpdateRejection.missingJustification(missingReason: missingReason, missingCause: missingCause)
        }
    }

    /// Validates and applies an Update on the controller's device. Records the
    /// update and the events it produces. Throws `UpdateRejection` and changes nothing if refused.
    @discardableResult
    public func apply(_ update: Update, to snapshot: inout JourneySnapshot, receivedAt: Date) throws -> [Event] {
        guard let index = snapshot.flights.firstIndex(where: { $0.id == update.flightId }) else {
            throw UpdateRejection.unknownFlight(update.flightId)
        }
        var flight = snapshot.flights[index]
        try validate(update, for: flight)

        let reported = update.reportedAt ?? receivedAt
        var log = EventLog(events: snapshot.events)
        var newEvents: [Event] = []
        func record(_ type: EventType, _ payload: EventPayload) {
            newEvents.append(log.append(type: type, journeyId: snapshot.journey.id, flightId: flight.id,
                                        actor: update.author, reportedAt: reported,
                                        receivedAt: receivedAt, payload: payload))
        }

        // Any update counts as contact from the aircraft.
        if flight.lastContactAt.map({ $0 < reported }) ?? true {
            flight.lastContactAt = reported
        }

        if let change = update.statusChange {
            if let eta = change.eta, eta != flight.eta {
                record(.etaChanged, EventPayload(previousEta: flight.eta, newEta: eta,
                                                 reason: change.reason, cause: change.cause))
                flight.eta = eta
            }

            var statusChanged = false
            if let status = change.status, status != flight.status {
                statusChanged = true
                let type: EventType
                switch status {
                case .departed:
                    type = .flightDeparted
                    flight.departedAt = reported
                case .landed:
                    type = .flightLanded
                    flight.landedAt = reported
                case .cancelled: type = .flightCancelled
                case .delayed: type = .flightDelayed
                default: type = .flightStatusChanged
                }
                record(type, EventPayload(previousStatus: flight.status, status: status,
                                          reason: change.reason, cause: change.cause,
                                          message: update.message))
                flight.status = status
            }

            // Rule 4 needs waitingOn: a justified delay names its cause; clearing the delay frees the flight.
            let newWaitingOn: WaitingOn?? = {
                if flight.status == .delayed, let cause = change.cause, cause != flight.waitingOn?.kind {
                    return .some(WaitingOn(kind: cause, ref: nil, since: reported))
                }
                if statusChanged, flight.status != .delayed, flight.status != .holding, flight.isWaiting {
                    return .some(nil)
                }
                return .none
            }()
            if case .some(let waitingOn) = newWaitingOn {
                record(.waitingOnChanged, EventPayload(reason: change.reason, cause: waitingOn?.kind,
                                                       waitingOn: waitingOn))
                flight.waitingOn = waitingOn
            }
        }

        snapshot.flights[index] = flight
        snapshot.updates.append(update)
        snapshot.events = log.events
        snapshot.journey.updatedAt = receivedAt
        return newEvents
    }

    // MARK: Rules 4 and 5 — the board

    public func boardRows(for snapshot: JourneySnapshot, now: Date) -> [BoardRow] {
        snapshot.orderedFlights.map { flight in
            let upstream = nearestDelayedUpstream(of: flight, in: snapshot)
            return BoardRow(flight: flight,
                            operatorName: operatorName(of: flight, in: snapshot),
                            noContact: hasLostContact(flight, now: now),
                            delayedBy: upstream?.code,
                            bottleneck: bottleneck(of: flight, upstream: upstream, in: snapshot))
        }
    }

    /// Rule 5: breadth-first up the `dependsOn` chain to the closest delayed flight.
    public func nearestDelayedUpstream(of flight: Flight, in snapshot: JourneySnapshot) -> Flight? {
        var queue = flight.dependsOn
        var seen: Set<String> = [flight.id]
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard seen.insert(id).inserted, let candidate = snapshot.flight(id) else { continue }
            if candidate.status == .delayed { return candidate }
            queue += candidate.dependsOn
        }
        return nil
    }

    /// Rule 4: blame follows `waitingOn`, not the airline by default.
    public func bottleneck(of flight: Flight, upstream: Flight?, in snapshot: JourneySnapshot) -> String? {
        if let waitingOn = flight.waitingOn, let kind = waitingOn.kind {
            return describe(kind, ref: waitingOn.ref, in: snapshot)
        }
        if let upstream { return upstream.code }
        if flight.status == .delayed || flight.status == .holding {
            return operatorName(of: flight, in: snapshot)
        }
        return nil
    }

    public func operatorName(of flight: Flight, in snapshot: JourneySnapshot) -> String {
        if let airline = snapshot.airline(flight.airlineId) { return airline.name }
        if let holder = flight.holder {
            switch holder.kind {
            case .passenger: return snapshot.passenger(holder.id)?.name ?? "Client"
            case .airline: return snapshot.airline(holder.id)?.name ?? holder.id ?? "Airline"
            default: return holder.id ?? "Customs"
            }
        }
        return flight.airlineId ?? (flight.kind == .customs ? "Customs" : "Unassigned")
    }

    private func describe(_ kind: WaitingCause, ref: String?, in snapshot: JourneySnapshot) -> String {
        switch kind {
        case .passenger: return snapshot.passenger(ref)?.name ?? "Client"
        case .airline: return snapshot.airline(ref)?.name ?? ref ?? "Airline"
        case .flight: return snapshot.flight(ref)?.code ?? ref ?? "Another flight"
        case .document: return ref.map { "Document \($0)" } ?? "Document"
        case .external: return ref ?? "External party"
        }
    }
}
