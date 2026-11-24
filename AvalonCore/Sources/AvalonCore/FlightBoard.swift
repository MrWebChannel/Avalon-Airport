import Foundation

/// One row of the flight board: "are we getting closer, and what's holding us up?"
public struct FlightBoardRow: Identifiable, Hashable, Sendable {
    public var id: String
    public var code: String
    public var title: String
    public var operatedBy: String
    public var kind: BoardingKind
    public var status: FlightStatus
    public var eta: Date?
    public var originalEta: Date?
    /// Who or what is holding the flight. Blame follows waitingOn, not the airline by default.
    public var holdingParty: String?
    public var delayedBy: String?
    public var noContact: Bool
    public var deliverablesAwaitingReview: Int
    public var openFindings: Int
}

public extension FlightTower {
    func flightBoard() -> [FlightBoardRow] {
        let j = journey
        let now = now()
        let staleDays = Int(engine.setting(pluginId: DelayPlugin.pluginId, key: "staleContactDays") ?? "7") ?? 7
        return j.boardingPasses.map { bp in
            var holding: String?
            if let w = bp.waitingOn {
                switch w.kind {
                case .passenger: holding = w.ref.flatMap { j.member($0)?.displayName }.map { "Waiting on \($0)" } ?? "Waiting on the Captain"
                case .document: holding = "Waiting on document \(w.ref ?? "")"
                case .flight: holding = "Waiting on flight \(w.ref.flatMap { j.boardingPass($0)?.code } ?? w.ref ?? "")"
                case .airline: holding = "Waiting on \(j.airline(w.ref)?.name ?? "the airline")"
                case .external: holding = "Waiting on \(w.ref ?? "an outside party")"
                }
            } else if bp.kind == .customs && !bp.status.isTerminal {
                holding = "Your decision"
            }
            let active: [FlightStatus] = [.departed, .inFlight, .holding, .delayed]
            let last = bp.lastContactAt ?? bp.departedAt
            let noContact = active.contains(bp.status) && (last.map { now.timeIntervalSince($0) > Double(staleDays * 86_400) } ?? false)
            let awaiting = j.deliverables.filter { $0.boardingPassId == bp.id && $0.status != .filed }.count
            let open = state.findings.filter { $0.boardingPassId == bp.id && $0.severity != .info && $0.createdAt > now.addingTimeInterval(-86_400) }.count
            return FlightBoardRow(
                id: bp.id, code: bp.code, title: bp.title,
                operatedBy: bp.kind == .customs ? (captain?.displayName ?? "Captain") : (j.airline(bp.airlineId)?.name ?? "Unassigned"),
                kind: bp.kind, status: bp.status, eta: bp.eta, originalEta: bp.originalEta,
                holdingParty: holding, delayedBy: DelayPlugin.upstreamDelay(of: bp, in: j).map(\.code),
                noContact: noContact, deliverablesAwaitingReview: awaiting, openFindings: open)
        }
    }

    /// Plain-text board for the demo and logs.
    func flightBoardText() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        var lines = ["\(journey.title)  ->  \(journey.destination.title)   \(Int(journey.completion * 100))% complete"]
        for r in flightBoard() {
            var line = "  \(r.code.padding(toLength: 8, withPad: " ", startingAt: 0))"
            line += "\(r.title.padding(toLength: 28, withPad: " ", startingAt: 0))"
            line += "\(r.operatedBy.padding(toLength: 24, withPad: " ", startingAt: 0))"
            line += "\(r.status.rawValue.uppercased().padding(toLength: 11, withPad: " ", startingAt: 0))"
            line += r.eta.map { df.string(from: $0) } ?? "--"
            var notes: [String] = []
            if let h = r.holdingParty { notes.append(h) }
            if let d = r.delayedBy { notes.append("Delayed by \(d)") }
            if r.noContact { notes.append("No contact from aircraft") }
            if r.deliverablesAwaitingReview > 0 { notes.append("\(r.deliverablesAwaitingReview) deliverable(s) to file") }
            if !notes.isEmpty { line += "   [" + notes.joined(separator: "; ") + "]" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
