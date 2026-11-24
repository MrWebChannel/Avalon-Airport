import Foundation

public enum TowerError: Error, LocalizedError, Equatable {
    case notAuthorized(String)
    case notFound(String)
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .notAuthorized(let m), .notFound(let m), .invalid(let m): return m
        }
    }
}

/// Everything the FlightTower persists on the controller's device. Never written to a repository
/// and never included whole in a manifest.
public struct TowerState: Codable {
    public var journey: Journey
    public var controllerIds: [String]
    public var activeControllerId: String
    public var credentials: [Credential] = []
    public var storageGrants: [StorageGrant] = []
    public var proposals: [Proposal] = []
    public var findings: [Finding] = []
    public var actionRecords: [ActionRecord] = []
    public var connectors: [Connector] = []
    public var autoApproveRules: [AutoApproveRule] = [.delayRule]
    public var packagePlugins: [PluginDescriptor] = []
    public var log = EventLog()
    /// Optional so towers saved before Build 2 still load.
    public var atlas: [AtlasEntry]? = nil
}

/// Governs one Journey. Only the FlightTower persists changes to Journey state.
/// Humans retain authority; agents and plugins provide recommendations.
public final class FlightTower {
    public internal(set) var state: TowerState
    public let engine: PluginEngine
    public let groundCrew: GroundCrew
    public var clock: () -> Date

    public init(state: TowerState, engine: PluginEngine = PluginEngine(),
                services: GroundServices = .inMemory(), clock: @escaping () -> Date = Date.init) {
        self.state = state
        self.engine = engine
        self.groundCrew = GroundCrew(services: services)
        self.clock = clock
        for plugin in state.packagePlugins { engine.register(plugin) }
    }

    // MARK: Read access

    public var journey: Journey { state.journey }
    public var events: [Event] { state.log.events }
    public var pendingProposals: [Proposal] { state.proposals.filter { $0.status == .pending } }
    public func now() -> Date { clock() }
    public func credential(_ id: String) -> Credential? { state.credentials.first { $0.id == id } }
    public func findings(for boardingPassId: String) -> [Finding] {
        state.findings.filter { $0.boardingPassId == boardingPassId }
    }
    /// Captains and Co-Captains.
    public var commitMemberIds: [String] { journey.members.filter { $0.role.canCommit }.map(\.id) }
    public var captain: TowerMember? { journey.members.first { $0.role == .captain } }
    public var atlasEntries: [AtlasEntry] { state.atlas ?? [] }
    public var loungeMessages: [LoungeMessage] { journey.lounge?.messages ?? [] }

    // MARK: Creating a journey from a package

    /// Approving and appending a HubPackage's JourneyTemplate creates the Journey, its BoardingPasses
    /// (one per step, each depending on the previous) and registers the package's plugins.
    public static func create(from template: JourneyTemplate, in package: HubPackage, title: String? = nil,
                              captain: TowerMember, others: [TowerMember] = [], start: Date,
                              engine: PluginEngine = PluginEngine(), services: GroundServices = .inMemory(),
                              clock: @escaping () -> Date = Date.init) -> FlightTower {
        var passes: [BoardingPass] = []
        var cursor = start
        let initials = template.title.split(separator: " ").compactMap(\.first).prefix(2)
        let prefix = initials.count == 2 ? String(initials).uppercased() : "AV"
        for (index, step) in template.steps.enumerated() {
            let flight = step.flightId.flatMap { id in package.flights.first { $0.id == id } }
            let days = flight?.typicalDurationDays ?? step.durationDays ?? 3
            cursor = Calendar.current.date(byAdding: .day, value: days, to: cursor) ?? cursor
            let id = "BP-\(index + 1)"
            passes.append(BoardingPass(
                id: id, code: "\(prefix)-\((index + 1) * 100 + 1)",
                title: flight?.title ?? step.title ?? "Customs",
                kind: step.kind, flightId: flight?.id, airlineId: flight?.airlineId,
                status: .scheduled, originalEta: cursor, eta: cursor,
                departedAt: nil, landedAt: nil, lastContactAt: nil,
                dependsOn: passes.last.map { [$0.id] } ?? [],
                crewIds: [], waypoints: [], waitingOn: nil, deliverableIds: [],
                pluginIds: flight?.pluginIds ?? []))
        }
        let members = [captain] + others
        let usedAirlines = Set(passes.compactMap(\.airlineId))
        let journey = Journey(
            id: Ids.make("J"), title: title ?? template.title, description: package.summary, status: .active,
            destination: Destination(id: Ids.make("D"), title: template.destinationTitle,
                                     successCriteria: template.successCriteria, status: .active, achievedAt: nil),
            hubId: package.hubId, templateId: template.id, members: members,
            airlines: package.airlines.filter { usedAirlines.contains($0.id) }, crew: [],
            boardingPasses: passes, deliverables: [], repositories: [],
            lounge: Lounge(memberIds: members.map(\.id), conciergeAccess: false, messages: []),
            createdAt: start, updatedAt: start)
        let controllers = members.filter { $0.role.canCommit }.map(\.id)
        var state = TowerState(journey: journey, controllerIds: controllers, activeControllerId: captain.id)
        state.packagePlugins = package.plugins
        let tower = FlightTower(state: state, engine: engine, services: services, clock: clock)
        tower.log(.journeyCreated, actor: EventActor(kind: .member, id: captain.id), reportedAt: start,
                  payload: ["title": journey.title, "package": package.id, "template": template.id])
        for bp in passes {
            tower.log(.boardingPassCreated, actor: .tower, boardingPassId: bp.id, reportedAt: start,
                      payload: ["code": bp.code, "title": bp.title, "kind": bp.kind.rawValue])
        }
        return tower
    }

    // MARK: Crew, credentials, connectors (Captain only)

    func requireCommitter(_ memberId: String) throws -> TowerMember {
        guard let m = journey.member(memberId) else { throw TowerError.notFound("Unknown member \(memberId)") }
        guard m.role.canCommit else { throw TowerError.notAuthorized("Only a Captain or Co-Captain can do this") }
        return m
    }

    /// Adds a Pilot, Co-Pilot or Crew member to a boarding pass and issues their scoped credential.
    @discardableResult
    public func addCrew(_ crew: CrewMember, to boardingPassId: String, by memberId: String,
                        permissions: [Permission] = [.read, .propose]) throws -> Credential {
        _ = try requireCommitter(memberId)
        guard let i = state.journey.boardingPasses.firstIndex(where: { $0.id == boardingPassId }) else {
            throw TowerError.notFound("No boarding pass \(boardingPassId)")
        }
        guard state.journey.boardingPasses[i].airlineId == crew.airlineId else {
            throw TowerError.invalid("\(crew.displayName) does not work for the airline operating this flight")
        }
        guard state.journey.airlines.contains(where: { $0.id == crew.airlineId }) else {
            throw TowerError.invalid("Airline \(crew.airlineId) is not on this journey")
        }
        if journey.crewMember(crew.id) == nil { state.journey.crew.append(crew) }
        if !state.journey.boardingPasses[i].crewIds.contains(crew.id) {
            state.journey.boardingPasses[i].crewIds.append(crew.id)
        }
        let now = clock()
        return makeCredential(recipientId: crew.id, kind: .crew, permissions: permissions,
                              scope: [boardingPassId], issuedBy: memberId, now: now)
    }

    public func addMember(_ member: TowerMember, by memberId: String) throws {
        _ = try requireCommitter(memberId)
        state.journey.members.append(member)
        state.journey.lounge?.memberIds.append(member.id)
        if member.role.canCommit { state.controllerIds.append(member.id) }
    }

    func makeCredential(recipientId: String, kind: RecipientKind, permissions: [Permission], scope: [String]?,
                        issuedBy: String, now: Date, expiresAt: Date? = nil) -> Credential {
        let cred = Credential(id: Ids.make("CR"), issuedBy: issuedBy, recipientId: recipientId, recipientKind: kind,
                              permissions: permissions, scopeBoardingPassIds: scope, keyCode: Ids.keyCode(),
                              expiresAt: expiresAt, status: .active)
        state.credentials.append(cred)
        log(.credentialIssued, actor: EventActor(kind: .member, id: issuedBy), reportedAt: now,
            payload: ["credentialId": cred.id, "recipient": recipientId,
                      "permissions": permissions.map(\.rawValue).joined(separator: ","),
                      "scope": scope?.joined(separator: ",") ?? "journey"])
        return cred
    }

    public func revokeCredential(_ id: String, by memberId: String) throws {
        _ = try requireCommitter(memberId)
        guard revokeCredentialInternal(id, now: clock()) else { throw TowerError.notFound("No active credential \(id)") }
    }

    func revokeCredentialInternal(_ id: String, now: Date) -> Bool {
        guard let i = state.credentials.firstIndex(where: { $0.id == id && $0.status == .active }) else { return false }
        state.credentials[i].status = .revoked
        log(.credentialRevoked, actor: .tower, reportedAt: now, payload: ["credentialId": id])
        for g in state.storageGrants where g.credentialId == id && g.status == .active {
            _ = revokeGrant(g.id, reason: "credential revoked", now: now)
        }
        return true
    }

    func revokeGrant(_ grantId: String, reason: String, now: Date, newStatus: CredentialStatus = .revoked) -> Bool {
        guard let i = state.storageGrants.firstIndex(where: { $0.id == grantId && $0.status == .active }) else { return false }
        let g = state.storageGrants[i]
        if let repo = journey.repositories.first(where: { $0.id == g.repositoryId }) {
            try? groundCrew.services.storage.revokeFolder(repository: repo, folder: g.folderPath, link: g.link)
        }
        state.storageGrants[i].status = newStatus
        log(.storageRevoked, actor: .tower, boardingPassId: g.expiresOnLandingOf, reportedAt: now,
            payload: ["grantId": g.id, "reason": reason])
        return true
    }

    public func linkConnector(_ connector: Connector, by memberId: String) throws {
        _ = try requireCommitter(memberId)
        state.connectors.append(connector)
        log(.connectorLinked, actor: EventActor(kind: .member, id: memberId), reportedAt: clock(),
            payload: ["connector": connector.id, "type": connector.type.rawValue, "provider": connector.provider])
    }

    @discardableResult
    public func addRepository(connectorId: String, path: String, by memberId: String) throws -> Repository {
        _ = try requireCommitter(memberId)
        guard state.connectors.contains(where: { $0.id == connectorId && $0.type == .storage }) else {
            throw TowerError.notFound("No storage connector \(connectorId)")
        }
        let repo = Repository(id: Ids.make("R"), connectorId: connectorId, path: path, ownerMemberId: memberId)
        state.journey.repositories.append(repo)
        return repo
    }

    public func setAutoApprove(_ rules: [AutoApproveRule], by memberId: String) throws {
        _ = try requireCommitter(memberId)
        state.autoApproveRules = rules
    }

    // MARK: Proposals

    /// Every change enters here. Plugins evaluate it; a block stops it. A Captain's own proposal
    /// commits at once; auto-approve rules may commit routine status changes; everything else waits
    /// for a Captain or Co-Captain, who is notified.
    @discardableResult
    public func submit(_ proposal: Proposal, credentialId: String? = nil) -> Proposal {
        var p = proposal
        p.status = .pending
        let now = clock()
        let actor = EventActor(kind: p.authorType, id: p.authorId)
        log(.proposalSubmitted, actor: actor, boardingPassId: p.boardingPassId, reportedAt: p.reportedAt,
            payload: ["proposalId": p.id, "message": p.message])

        let bp = p.boardingPassId.flatMap { journey.boardingPass($0) }
        if p.authorType == .crew, let bpId = bp?.id, let i = index(of: bpId) {
            state.journey.boardingPasses[i].lastContactAt = now   // the tower records contact
        }

        let context = PluginContext(trigger: .onProposal, now: now, journey: journey, boardingPass: bp,
                                    proposal: p, credential: credentialId.flatMap(credential))
        let result = engine.run(context)
        state.findings.append(contentsOf: result.findings)
        p.findingIds.append(contentsOf: result.findings.map(\.id))

        if result.blocked {
            p.status = .blocked
            p.decisionNote = result.blockMessages.joined(separator: "; ")
            p.decidedBy = "tower"
            p.decidedAt = now
            state.proposals.append(p)
            log(.proposalBlocked, actor: .tower, boardingPassId: p.boardingPassId, reportedAt: now,
                payload: ["proposalId": p.id, "reason": p.decisionNote ?? ""])
            return p
        }

        if p.authorType == .member, let m = journey.member(p.authorId), m.role.canCommit {
            p = commit(p, status: .approved, decidedBy: m.id)
        } else if isAutoApprovable(p) {
            p = commit(p, status: .autoApproved, decidedBy: "tower")
        } else {
            state.proposals.append(p)
            let where_ = bp.map { "\($0.code) " } ?? ""
            for id in commitMemberIds {
                groundCrew.services.notifier.notify(recipientId: id, title: "Proposal to review",
                                                    body: "\(where_)\(p.message)")
            }
        }
        for raised in result.raisedProposals where p.authorType != .plugin { submit(raised) }
        return p
    }

    @discardableResult
    public func approve(_ proposalId: String, by memberId: String, note: String? = nil) throws -> Proposal {
        let member = try requireCommitter(memberId)
        guard let i = state.proposals.firstIndex(where: { $0.id == proposalId }) else {
            throw TowerError.notFound("No proposal \(proposalId)")
        }
        guard state.proposals[i].status == .pending else { throw TowerError.invalid("Proposal is not pending") }
        var p = state.proposals.remove(at: i)
        p.decisionNote = note
        return commit(p, status: .approved, decidedBy: member.id)
    }

    @discardableResult
    public func reject(_ proposalId: String, by memberId: String, note: String) throws -> Proposal {
        let member = try requireCommitter(memberId)
        guard let i = state.proposals.firstIndex(where: { $0.id == proposalId && $0.status == .pending }) else {
            throw TowerError.notFound("No pending proposal \(proposalId)")
        }
        let now = clock()
        state.proposals[i].status = .rejected
        state.proposals[i].decidedBy = member.id
        state.proposals[i].decidedAt = now
        state.proposals[i].decisionNote = note
        log(.proposalRejected, actor: EventActor(kind: .member, id: member.id),
            boardingPassId: state.proposals[i].boardingPassId, reportedAt: now,
            payload: ["proposalId": proposalId, "note": note])
        return state.proposals[i]
    }

    /// A Captain asks Ground Crew to do something (share a folder, post to the calendar, issue a credential).
    /// It still goes through a Proposal so it is checked and logged like everything else.
    @discardableResult
    public func requestAction(_ request: ActionRequest, boardingPassId: String? = nil, by memberId: String,
                              message: String) throws -> Proposal {
        _ = try requireCommitter(memberId)
        let p = Proposal(boardingPassId: boardingPassId, authorId: memberId, authorType: .member,
                         reportedAt: clock(), message: message, actionRequests: [request])
        return submit(p)
    }

    func isAutoApprovable(_ p: Proposal) -> Bool {
        guard p.isStatusOnly, let sc = p.statusChange else { return false }
        if state.autoApproveRules.contains(.delayRule), p.authorType == .plugin,
           p.authorId == DelayPlugin.pluginId, sc.status == .delayed, sc.eta == nil {
            return true
        }
        if state.autoApproveRules.contains(.etaWithinGraceWindow), p.authorType == .crew, sc.status == nil,
           let newEta = sc.eta, let bp = p.boardingPassId.flatMap({ journey.boardingPass($0) }),
           bp.status != .delayed, let oldEta = bp.eta {
            let grace = (Double(engine.setting(pluginId: DelayPlugin.pluginId, key: "graceHours") ?? "0") ?? 0) * 3600
            return grace > 0 && abs(newEta.timeIntervalSince(oldEta)) <= grace
        }
        return false
    }

    /// Applies an approved proposal to Journey state, writes Events, then hands its actions to Ground Crew.
    private func commit(_ proposal: Proposal, status: ProposalStatus, decidedBy: String) -> Proposal {
        var p = proposal
        let now = clock()
        p.status = status
        p.decidedBy = decidedBy
        p.decidedAt = now
        state.proposals.append(p)
        let deciderActor = decidedBy == "tower" ? EventActor.tower : EventActor(kind: .member, id: decidedBy)
        log(status == .autoApproved ? .proposalAutoApproved : .proposalApproved, actor: deciderActor,
            boardingPassId: p.boardingPassId, reportedAt: now, payload: ["proposalId": p.id])

        let changeActor = p.authorType == .plugin ? EventActor.tower : EventActor(kind: p.authorType, id: p.authorId)
        if let bpId = p.boardingPassId, let i = index(of: bpId) {
            if let sc = p.statusChange { apply(sc, to: i, actor: changeActor, reportedAt: p.reportedAt, now: now) }
            if let notice = p.deliverableNotice { recordDeliverable(notice, on: i, actor: changeActor, now: now) }
            if let wpId = p.waypointReached,
               let w = state.journey.boardingPasses[i].waypoints.firstIndex(where: { $0.id == wpId }) {
                state.journey.boardingPasses[i].waypoints[w].reachedAt = now
                log(.waypointReached, actor: changeActor, boardingPassId: bpId, reportedAt: p.reportedAt,
                    payload: ["waypoint": state.journey.boardingPasses[i].waypoints[w].title])
            }
            if p.authorType == .crew { state.journey.boardingPasses[i].lastContactAt = now }
        }
        state.journey.updatedAt = now

        for request in p.actionRequests { _ = groundCrew.execute(request, for: p, in: self) }

        if let bp = p.boardingPassId.flatMap({ journey.boardingPass($0) }) {
            let result = engine.run(PluginContext(trigger: .onEvent, now: now, journey: journey, boardingPass: bp))
            state.findings.append(contentsOf: result.findings)
        }
        checkArrival(now: now)
        return p
    }

    private func apply(_ sc: StatusChange, to i: Int, actor: EventActor, reportedAt: Date, now: Date) {
        let bp = state.journey.boardingPasses[i]
        var payload: [String: String] = [:]
        if let r = sc.reason { payload["reason"] = r }
        if let c = sc.cause { payload["cause"] = c.rawValue }

        if let eta = sc.eta, eta != bp.eta {
            state.journey.boardingPasses[i].eta = eta
            var etaPayload = payload
            etaPayload["previousEta"] = bp.eta.map(Self.iso.string(from:)) ?? ""
            etaPayload["newEta"] = Self.iso.string(from: eta)
            log(.etaChanged, actor: actor, boardingPassId: bp.id, reportedAt: reportedAt, payload: etaPayload)
        }
        if let newStatus = sc.status, newStatus != bp.status {
            state.journey.boardingPasses[i].status = newStatus
            var statusPayload = payload
            statusPayload["from"] = bp.status.rawValue
            statusPayload["to"] = newStatus.rawValue
            switch newStatus {
            case .departed:
                state.journey.boardingPasses[i].departedAt = now
                log(.flightDeparted, actor: actor, boardingPassId: bp.id, reportedAt: reportedAt, payload: statusPayload)
            case .landed:
                state.journey.boardingPasses[i].landedAt = now
                state.journey.boardingPasses[i].waitingOn = nil
                log(.flightLanded, actor: actor, boardingPassId: bp.id, reportedAt: reportedAt, payload: statusPayload)
                for g in state.storageGrants where g.expiresOnLandingOf == bp.id && g.status == .active {
                    _ = revokeGrant(g.id, reason: "expired at landing", now: now, newStatus: .expired)
                }
            case .delayed:
                log(.flightDelayed, actor: actor, boardingPassId: bp.id, reportedAt: reportedAt, payload: statusPayload)
            default:
                log(.statusChanged, actor: actor, boardingPassId: bp.id, reportedAt: reportedAt, payload: statusPayload)
            }
        }
        if sc.clearWaitingOn == true {
            state.journey.boardingPasses[i].waitingOn = nil
            log(.waitingOnChanged, actor: actor, boardingPassId: bp.id, reportedAt: reportedAt, payload: ["waitingOn": "none"])
        } else if let w = sc.waitingOn {
            state.journey.boardingPasses[i].waitingOn = w
            log(.waitingOnChanged, actor: actor, boardingPassId: bp.id, reportedAt: reportedAt,
                payload: ["waitingOn": w.kind.rawValue, "ref": w.ref ?? ""])
        }
    }

    /// A provider sent a deliverable through its own channel. Avalon records the notice only.
    /// Flights that depend on this one now wait on the Captain's review.
    private func recordDeliverable(_ notice: DeliverableNotice, on i: Int, actor: EventActor, now: Date) {
        let bp = state.journey.boardingPasses[i]
        let d = Deliverable(id: Ids.make("DL"), boardingPassId: bp.id, title: notice.title, status: .sent,
                            sentVia: notice.sentVia, sentAt: now, reviewedBy: nil, filedPath: nil)
        state.journey.deliverables.append(d)
        state.journey.boardingPasses[i].deliverableIds.append(d.id)
        log(.deliverableSent, actor: actor, boardingPassId: bp.id, reportedAt: now,
            payload: ["deliverableId": d.id, "title": d.title, "sentVia": notice.sentVia])
        for j in state.journey.boardingPasses.indices where state.journey.boardingPasses[j].dependsOn.contains(bp.id)
            && !state.journey.boardingPasses[j].status.isTerminal {
            state.journey.boardingPasses[j].waitingOn = WaitingOn(kind: .passenger, ref: captain?.id, since: now)
        }
        for id in commitMemberIds {
            groundCrew.services.notifier.notify(recipientId: id, title: "Deliverable to review",
                                                body: "\(bp.code): \(d.title) was sent via \(notice.sentVia)")
        }
    }

    /// The Captain moves a deliverable through received, reviewed and filed. Only humans do this.
    public func markDeliverable(_ deliverableId: String, as status: DeliverableStatus, filedPath: String? = nil,
                                by memberId: String) throws {
        let member = try requireCommitter(memberId)
        guard let i = state.journey.deliverables.firstIndex(where: { $0.id == deliverableId }) else {
            throw TowerError.notFound("No deliverable \(deliverableId)")
        }
        if status == .filed && (filedPath ?? "").isEmpty { throw TowerError.invalid("Filing needs the path where you saved it") }
        let now = clock()
        state.journey.deliverables[i].status = status
        if status == .reviewed || status == .filed { state.journey.deliverables[i].reviewedBy = member.id }
        if let filedPath { state.journey.deliverables[i].filedPath = filedPath }
        let d = state.journey.deliverables[i]
        let type: EventType
        switch status {
        case .sent: type = .deliverableSent
        case .received: type = .deliverableReceived
        case .reviewed: type = .deliverableReviewed
        case .filed: type = .deliverableFiled
        }
        log(type, actor: EventActor(kind: .member, id: member.id), boardingPassId: d.boardingPassId, reportedAt: now,
            payload: ["deliverableId": d.id, "title": d.title, "path": d.filedPath ?? ""])

        if status == .filed {
            let stillOpen = journey.deliverables.contains { $0.boardingPassId == d.boardingPassId && $0.status != .filed }
            if !stillOpen {
                for j in state.journey.boardingPasses.indices
                where state.journey.boardingPasses[j].dependsOn.contains(d.boardingPassId)
                    && state.journey.boardingPasses[j].waitingOn?.kind == .passenger {
                    state.journey.boardingPasses[j].waitingOn = nil
                }
            }
        }
        state.journey.updatedAt = now
        if status == .filed { checkArrival(now: now) }
    }

    // MARK: Lounge (tower members only; airlines never see it)

    public func postToLounge(_ text: String, by memberId: String) throws {
        guard let lounge = journey.lounge, lounge.memberIds.contains(memberId) else {
            throw TowerError.notAuthorized("Only Lounge members can post here")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TowerError.invalid("Message is empty") }
        state.journey.lounge?.messages.append(LoungeMessage(authorId: memberId, text: trimmed, at: clock()))
    }

    // MARK: Scheduled checks

    /// Runs plugins for every open boarding pass (delay rules, flight checks, package plugins).
    /// Analytics recommendations become Proposals; the delayRule auto-approves overdue flights.
    @discardableResult
    public func tick(trigger: PluginTrigger = .onSchedule) -> [Finding] {
        let now = clock()
        var all: [Finding] = []
        for bp in journey.boardingPasses where !bp.status.isTerminal {
            let current = journey.boardingPass(bp.id) ?? bp
            let result = engine.run(PluginContext(trigger: trigger, now: now, journey: journey, boardingPass: current))
            state.findings.append(contentsOf: result.findings)
            all.append(contentsOf: result.findings)
            for raised in result.raisedProposals { submit(raised) }
        }
        return all
    }

    private func checkArrival(now: Date) {
        guard journey.status == .active else { return }
        let counted = journey.boardingPasses.filter { $0.status != .cancelled }
        guard !counted.isEmpty, counted.allSatisfy({ $0.status == .landed || $0.status == .closed }),
              journey.deliverables.allSatisfy({ $0.status == .filed }) else { return }
        state.journey.status = .arrived
        state.journey.destination.status = .achieved
        state.journey.destination.achievedAt = now
        log(.destinationAchieved, actor: .tower, reportedAt: now, payload: ["destination": journey.destination.title])
        let entry = AtlasEntry(id: Ids.make("AE"), journeyId: journey.id, title: journey.title,
                               destinationTitle: journey.destination.title, startedAt: journey.createdAt, completedAt: now,
                               summary: "\(counted.count) flights, \(journey.deliverables.count) documents filed")
        state.atlas = (state.atlas ?? []) + [entry]
    }

    // MARK: Helpers

    func index(of boardingPassId: String) -> Int? {
        state.journey.boardingPasses.firstIndex { $0.id == boardingPassId }
    }

    @discardableResult
    func log(_ type: EventType, actor: EventActor, boardingPassId: String? = nil, reportedAt: Date,
             payload: [String: String] = [:]) -> Event {
        state.log.append(type, actor: actor, boardingPassId: boardingPassId, reportedAt: reportedAt,
                         receivedAt: clock(), payload: payload)
    }

    static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    // MARK: Persistence (device only)

    public func save() throws -> Data {
        // Dates keep full precision (default strategy) so event hashes still verify after reloading.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    public static func load(_ data: Data, services: GroundServices = .inMemory(),
                            clock: @escaping () -> Date = Date.init) throws -> FlightTower {
        let decoder = JSONDecoder()
        let state = try decoder.decode(TowerState.self, from: data)
        return FlightTower(state: state, services: services, clock: clock)
    }
}
