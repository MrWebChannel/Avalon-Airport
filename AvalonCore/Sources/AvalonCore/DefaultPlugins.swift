import Foundation

// Default plugins ship in the app, always run, and always win over package plugins.
// Security covers permissions, visibility and journey governance (the board's SECURITY list),
// so the flight checks that hold a flight are a security-type plugin and may block.

private let accessActions: Set<ActionType> = [.shareFolderLink, .revokeFolderLink, .issueCredential, .revokeCredential]

/// Permissions, credentials, access control and delay accountability.
public struct SecurityPlugin: NativePlugin {
    public var descriptor = PluginDescriptor(id: "avalon.security", name: "Security", type: .security, tier: .default)
    public init() {}

    public func evaluate(_ c: PluginContext) -> [FindingDraft] {
        guard c.trigger == .onProposal, let p = c.proposal else { return [] }
        var out: [FindingDraft] = []

        switch p.authorType {
        case .crew:
            guard let cred = c.credential else {
                return [FindingDraft(.block, "No credential presented with this proposal")]
            }
            if !cred.isActive(at: c.now) { out.append(FindingDraft(.block, "Credential is expired or revoked")) }
            if !cred.permissions.contains(.propose) { out.append(FindingDraft(.block, "Credential does not allow proposals")) }
            if cred.recipientId != p.authorId { out.append(FindingDraft(.block, "Credential belongs to someone else")) }
            if let bp = c.boardingPass {
                if !cred.covers(bp.id) { out.append(FindingDraft(.block, "Credential does not cover \(bp.code)")) }
                if let crew = c.journey.crewMember(p.authorId), crew.airlineId != bp.airlineId {
                    out.append(FindingDraft(.block, "\(crew.displayName) is not crew on \(bp.code)"))
                }
            }
            if p.actionRequests.contains(where: { accessActions.contains($0.type) }) {
                out.append(FindingDraft(.block, "Only the FlightTower can grant or revoke access"))
            }
        case .member:
            guard let member = c.journey.member(p.authorId) else {
                return [FindingDraft(.block, "Unknown tower member")]
            }
            if member.role == .passenger || member.role == .observer {
                out.append(FindingDraft(.block, "\(member.role.rawValue.capitalized)s cannot propose changes"))
            }
        case .plugin, .tower:
            if p.actionRequests.contains(where: { accessActions.contains($0.type) }) {
                out.append(FindingDraft(.block, "Plugins cannot request access changes"))
            }
        case .concierge:
            if p.actionRequests.contains(where: { accessActions.contains($0.type) }) {
                out.append(FindingDraft(.block, "The Concierge cannot request access changes"))
            }
        }

        // Delay accountability: changing the ETA of a delayed flight, or clearing the delay,
        // needs a reason and a cause.
        if let bp = c.boardingPass, bp.status == .delayed, let sc = p.statusChange {
            let changesEta = sc.eta != nil && sc.eta != bp.eta
            let clearsDelay = sc.status != nil && sc.status != .delayed
            let hasReason = !(sc.reason ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            if (changesEta || clearsDelay) && (!hasReason || sc.cause == nil) {
                out.append(FindingDraft(.block, "\(bp.code) is delayed: an ETA change or clearing the delay needs a reason and a cause"))
            }
        }
        return out
    }
}

/// Pre-flight, in-flight and landing checks.
public struct FlightChecksPlugin: NativePlugin {
    public var descriptor = PluginDescriptor(id: "avalon.flightchecks", name: "Flight checks", type: .security, tier: .default)
    public init() {}

    public func evaluate(_ c: PluginContext) -> [FindingDraft] {
        guard let bp = c.boardingPass else { return [] }
        switch c.trigger {
        case .onProposal:
            guard let target = c.proposal?.statusChange?.status else { return [] }
            let launching: [FlightStatus] = [.boarding, .departed, .inFlight]
            if launching.contains(target) && !bp.status.isTerminal && bp.departedAt == nil {
                return preFlight(bp, c)
            }
            if target == .landed { return landing(bp, c) }
            return []
        case .onSchedule, .onAppOpen:
            return inFlight(bp, c)
        case .onEvent:
            return []
        }
    }

    private func preFlight(_ bp: BoardingPass, _ c: PluginContext) -> [FindingDraft] {
        var out: [FindingDraft] = []
        for depId in bp.dependsOn {
            guard let dep = c.journey.boardingPass(depId) else { continue }
            if dep.status != .landed && dep.status != .closed {
                out.append(FindingDraft(.block, "Can't depart: waiting on \(dep.code) to land"))
                continue
            }
            let unfiled = c.journey.deliverables.filter { $0.boardingPassId == dep.id && $0.status != .filed }
            for d in unfiled {
                out.append(FindingDraft(.block, "Can't depart: \(d.title) from \(dep.code) is not yet filed by the Captain"))
            }
        }
        if bp.kind == .flight {
            let hasPilot = bp.crewIds.contains { c.journey.crewMember($0)?.role == .pilot }
            if !hasPilot { out.append(FindingDraft(.block, "Can't depart: no Pilot assigned to \(bp.code)")) }
        }
        if bp.eta == nil { out.append(FindingDraft(.block, "Can't depart: \(bp.code) has no ETA")) }
        if out.isEmpty { out.append(FindingDraft(.info, "Pre-flight checks passed for \(bp.code)")) }
        return out
    }

    private func landing(_ bp: BoardingPass, _ c: PluginContext) -> [FindingDraft] {
        let sent = !bp.deliverableIds.isEmpty || c.proposal?.deliverableNotice != nil
        if bp.kind == .flight && !sent {
            return [FindingDraft(.warning, "\(bp.code) is landing with no deliverable sent")]
        }
        return [FindingDraft(.info, "\(bp.code) landing: Captain review of the deliverable is pending")]
    }

    private func inFlight(_ bp: BoardingPass, _ c: PluginContext) -> [FindingDraft] {
        let active: [FlightStatus] = [.departed, .inFlight, .holding, .delayed]
        guard active.contains(bp.status) else { return [] }
        return bp.waypoints
            .filter { $0.reachedAt == nil && ($0.dueAt.map { $0 < c.now } ?? false) }
            .map { FindingDraft(.warning, "\(bp.code): waypoint \"\($0.title)\" is overdue") }
    }
}

/// Delay rules from v0.2, now a default analytics plugin. Settings: graceHours, staleContactDays.
public struct DelayPlugin: NativePlugin {
    public static let pluginId = "avalon.delay"
    public var descriptor = PluginDescriptor(id: DelayPlugin.pluginId, name: "Delay rules", type: .analytics,
                                             tier: .default, settings: ["graceHours": "0", "staleContactDays": "7"])
    public init() {}

    public func evaluate(_ c: PluginContext) -> [FindingDraft] {
        guard c.trigger == .onSchedule || c.trigger == .onAppOpen,
              let bp = c.boardingPass, !bp.status.isTerminal, bp.status != .proposed, bp.status != .cancelled
        else { return [] }
        var out: [FindingDraft] = []
        let grace = TimeInterval((Double(c.settings["graceHours"] ?? "0") ?? 0) * 3600)
        let staleDays = Int(c.settings["staleContactDays"] ?? "7") ?? 7

        // Rule 1: overdue flights become delayed (raised as a Proposal, auto-approved by the delayRule).
        if bp.status != .delayed, let eta = bp.eta, c.now > eta.addingTimeInterval(grace) {
            out.append(FindingDraft(.warning, "\(bp.code) passed its ETA and has not landed",
                                    recommendation: Recommendation(message: "Mark \(bp.code) delayed",
                                                                   statusChange: StatusChange(status: .delayed))))
        }
        // Rule 2: no contact from aircraft.
        if ([.departed, .inFlight, .holding, .delayed] as [FlightStatus]).contains(bp.status),
           let last = bp.lastContactAt ?? bp.departedAt,
           c.now.timeIntervalSince(last) > TimeInterval(staleDays * 86_400) {
            out.append(FindingDraft(.warning, "No contact from aircraft \(bp.code) for over \(staleDays) days"))
        }
        // Rule 5: delays pass down the dependsOn chain.
        if let blocker = DelayPlugin.upstreamDelay(of: bp, in: c.journey) {
            out.append(FindingDraft(.info, "\(bp.code) delayed by \(blocker.code)"))
        }
        // ETA drift.
        if let eta = bp.eta, let original = bp.originalEta, eta > original.addingTimeInterval(86_400) {
            let days = Calendar.current.dateComponents([.day], from: original, to: eta).day ?? 0
            out.append(FindingDraft(.info, "\(bp.code) ETA drifted \(days) days from the original"))
        }
        return out
    }

    /// The nearest delayed boarding pass upstream on the dependsOn chain.
    public static func upstreamDelay(of bp: BoardingPass, in journey: Journey) -> BoardingPass? {
        var queue = bp.dependsOn
        var seen = Set<String>()
        while let id = queue.first {
            queue.removeFirst()
            guard seen.insert(id).inserted, let dep = journey.boardingPass(id) else { continue }
            if dep.status == .delayed { return dep }
            queue.append(contentsOf: dep.dependsOn)
        }
        return nil
    }
}
