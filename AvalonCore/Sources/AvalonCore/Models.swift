import Foundation

// Avalon Airport domain model v0.3.
// Source of truth: spec/domain-model.md and the "Domain Model v0.3" area of the Miro board.
// The client owns the airport, one device writes, nothing is overwritten,
// every delay names its bottleneck, and a human reviews every document.

// MARK: - Enumerations

public enum FlightStatus: String, Codable, CaseIterable, Sendable {
    case proposed, scheduled, boarding, departed
    case inFlight = "in-flight"
    case holding, delayed, landed, closed, cancelled

    /// Statuses where the flight is finished and delay rules no longer apply.
    public var isTerminal: Bool { self == .landed || self == .closed || self == .cancelled }
}

public enum WaitingCause: String, Codable, CaseIterable, Sendable {
    case passenger, document, flight, airline, external
}

public enum BoardingKind: String, Codable, Sendable {
    case flight     // operated by an Airline
    case customs    // a decision step held by the Captain (review, sign, approve)
}

public enum JourneyStatus: String, Codable, Sendable { case active, paused, arrived, abandoned }
public enum DestinationStatus: String, Codable, Sendable { case active, achieved }

public enum TowerRole: String, Codable, CaseIterable, Sendable {
    case captain, coCaptain, passenger, observer
    /// Only Captains and Co-Captains may commit changes to Journey state.
    public var canCommit: Bool { self == .captain || self == .coCaptain }
}

public enum CrewRole: String, Codable, CaseIterable, Sendable { case pilot, coPilot, crew }
public enum CrewKind: String, Codable, Sendable { case human, agent }

public enum Permission: String, Codable, CaseIterable, Sendable { case read, propose, invite, observe }
public enum RecipientKind: String, Codable, Sendable { case member, crew }
public enum CredentialStatus: String, Codable, Sendable { case active, revoked, expired }

public enum DeliverableStatus: String, Codable, CaseIterable, Sendable { case sent, received, reviewed, filed }

public enum ProposalStatus: String, Codable, Sendable {
    case pending, approved, rejected, autoApproved, blocked
}
public enum AuthorType: String, Codable, Sendable { case crew, member, plugin, concierge, tower }

public enum ActionType: String, Codable, CaseIterable, Sendable {
    case notify, addCalendarEvent, verifyDeliverable, shareFolderLink, revokeFolderLink
    case issueCredential, revokeCredential, remindCustoms, updateEta
}
public enum ActionResult: String, Codable, Sendable { case success, failed, skipped }

public enum FindingSeverity: String, Codable, CaseIterable, Comparable, Sendable {
    case info, warning, block
    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .block: return 2
        }
    }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// The three plugin types. The PluginEngine orders plugins by type and limits what each may output.
public enum PluginType: String, Codable, CaseIterable, Sendable {
    case security, analytics, contentBehavior

    /// runOrder: security, analytics, contentBehavior
    public var runRank: Int {
        switch self {
        case .security: return 0
        case .analytics: return 1
        case .contentBehavior: return 2
        }
    }

    /// security: block, warning, info / analytics: warning, info / contentBehavior: info only
    public var maxSeverity: FindingSeverity {
        switch self {
        case .security: return .block
        case .analytics: return .warning
        case .contentBehavior: return .info
        }
    }
    /// Only analytics plugins may turn a recommendation into a Proposal.
    public var mayRaiseProposal: Bool { self == .analytics }
}

public enum PluginTier: String, Codable, Sendable { case `default`, package }

public enum ConnectorType: String, Codable, Sendable { case storage, calendar }
public enum ConnectorStatus: String, Codable, Sendable { case linked, expired, revoked }

// MARK: - People and providers

public struct TowerMember: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var role: TowerRole
    /// Never sent to providers.
    public var contact: String?
    public init(id: String, displayName: String, role: TowerRole, contact: String? = nil) {
        self.id = id; self.displayName = displayName; self.role = role; self.contact = contact
    }
}

/// A person or AI agent working for an Airline on a BoardingPass.
public struct CrewMember: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var role: CrewRole
    public var kind: CrewKind
    public var airlineId: String
    public var contact: String?
    public init(id: String, displayName: String, role: CrewRole, kind: CrewKind = .human,
                airlineId: String, contact: String? = nil) {
        self.id = id; self.displayName = displayName; self.role = role; self.kind = kind
        self.airlineId = airlineId; self.contact = contact
    }
}

/// A professional service provider (the firm).
public struct Airline: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: String
    public init(id: String, name: String, type: String) { self.id = id; self.name = name; self.type = type }
}

/// A curated ecosystem of trusted Airlines within a Hub.
public struct Airport: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var airlineIds: [String]
    public init(id: String, name: String, airlineIds: [String]) { self.id = id; self.name = name; self.airlineIds = airlineIds }
}

/// A knowledge and service domain.
public struct Hub: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public init(id: String, name: String, summary: String) { self.id = id; self.name = name; self.summary = summary }
}

// MARK: - Templates and packages (the product)

/// A reusable service offering published by an Airline.
public struct Flight: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var airlineId: String
    public var title: String
    public var description: String
    public var defaultDeliverables: [String]
    public var typicalDurationDays: Int
    public var pluginIds: [String]
    public var version: String
    public init(id: String, airlineId: String, title: String, description: String,
                defaultDeliverables: [String], typicalDurationDays: Int,
                pluginIds: [String] = [], version: String = "1.0") {
        self.id = id; self.airlineId = airlineId; self.title = title; self.description = description
        self.defaultDeliverables = defaultDeliverables; self.typicalDurationDays = typicalDurationDays
        self.pluginIds = pluginIds; self.version = version
    }
}

/// One step of a JourneyTemplate: an Airline's Flight or a Customs step held by the Captain.
public struct JourneyStep: Codable, Hashable, Sendable {
    public var kind: BoardingKind
    public var flightId: String?
    public var title: String?
    public var durationDays: Int?
    public init(flight flightId: String) { kind = .flight; self.flightId = flightId }
    public init(customs title: String, durationDays: Int = 3) {
        kind = .customs; self.title = title; self.durationDays = durationDays
    }
}

/// A ready-made sequence of Flights toward a Destination.
public struct JourneyTemplate: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var destinationTitle: String
    public var successCriteria: [String]
    public var steps: [JourneyStep]
    public init(id: String, title: String, destinationTitle: String, successCriteria: [String], steps: [JourneyStep]) {
        self.id = id; self.title = title; self.destinationTitle = destinationTitle
        self.successCriteria = successCriteria; self.steps = steps
    }
}

/// Describes a plugin. Default plugins ship in the app; package plugins arrive in a HubPackage
/// as YAML settings plus a JavaScript `evaluate(context)` function.
public struct PluginDescriptor: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: PluginType
    public var tier: PluginTier
    public var version: String
    /// SHA-256 of `script`, hex. Stand-in for real code signing; checked before a package plugin runs.
    public var signature: String?
    public var settings: [String: String]
    public var script: String?
    public init(id: String, name: String, type: PluginType, tier: PluginTier, version: String = "1.0",
                signature: String? = nil, settings: [String: String] = [:], script: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.tier = tier; self.version = version
        self.signature = signature; self.settings = settings; self.script = script
    }
}

/// The sellable bundle: content, journey templates, flights, plugins and connected providers.
public struct HubPackage: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var hubId: String
    public var publisher: String
    public var title: String
    public var summary: String
    public var version: String
    public var contentRefs: [String]
    public var journeyTemplates: [JourneyTemplate]
    public var flights: [Flight]
    public var plugins: [PluginDescriptor]
    public var airports: [Airport]
    public var airlines: [Airline]
    public var customizedFor: String?
    public init(id: String, hubId: String, publisher: String, title: String, summary: String, version: String = "1.0",
                contentRefs: [String] = [], journeyTemplates: [JourneyTemplate] = [], flights: [Flight] = [],
                plugins: [PluginDescriptor] = [], airports: [Airport] = [], airlines: [Airline] = [],
                customizedFor: String? = nil) {
        self.id = id; self.hubId = hubId; self.publisher = publisher; self.title = title; self.summary = summary
        self.version = version; self.contentRefs = contentRefs; self.journeyTemplates = journeyTemplates
        self.flights = flights; self.plugins = plugins; self.airports = airports; self.airlines = airlines
        self.customizedFor = customizedFor
    }
}

// MARK: - Journey and its parts

public struct Destination: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var successCriteria: [String]
    public var status: DestinationStatus
    public var achievedAt: Date?
}

public struct WaitingOn: Codable, Hashable, Sendable {
    public var kind: WaitingCause
    public var ref: String?
    public var since: Date
    public init(kind: WaitingCause, ref: String? = nil, since: Date) { self.kind = kind; self.ref = ref; self.since = since }
}

public struct Waypoint: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var dueAt: Date?
    public var reachedAt: Date?
}

/// One instance of a Flight inside a Journey (or a Customs step).
public struct BoardingPass: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var code: String
    public var title: String
    public var kind: BoardingKind
    public var flightId: String?
    public var airlineId: String?
    public var status: FlightStatus
    public var originalEta: Date?
    public var eta: Date?
    public var departedAt: Date?
    public var landedAt: Date?
    public var lastContactAt: Date?
    public var dependsOn: [String]
    public var crewIds: [String]
    public var waypoints: [Waypoint]
    public var waitingOn: WaitingOn?
    public var deliverableIds: [String]
    public var pluginIds: [String]
}

public struct Deliverable: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var boardingPassId: String
    public var title: String
    public var status: DeliverableStatus
    /// How the provider sent it to the Captain: patient portal, secure email, in person.
    public var sentVia: String?
    public var sentAt: Date?
    public var reviewedBy: String?
    public var filedPath: String?
}

/// A folder in the Captain's own storage, reached through a Connector.
public struct Repository: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var connectorId: String
    public var path: String
    public var ownerMemberId: String
    public var mode: String = "read-only"
}

public struct LoungeMessage: Codable, Hashable, Sendable {
    public var authorId: String
    public var text: String
    public var at: Date
}

/// Private space for tower members. Airlines never see it.
public struct Lounge: Codable, Hashable, Sendable {
    public var memberIds: [String]
    public var conciergeAccess: Bool
    public var messages: [LoungeMessage]
}

public struct Journey: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    public var status: JourneyStatus
    public var destination: Destination
    public var hubId: String?
    public var templateId: String?
    public var members: [TowerMember]
    public var airlines: [Airline]
    public var crew: [CrewMember]
    public var boardingPasses: [BoardingPass]
    public var deliverables: [Deliverable]
    public var repositories: [Repository]
    public var lounge: Lounge?
    public var createdAt: Date
    public var updatedAt: Date

    /// Computed from boarding pass states, never stored.
    public var completion: Double {
        let counted = boardingPasses.filter { $0.status != .cancelled }
        guard !counted.isEmpty else { return 0 }
        let done = counted.filter { $0.status == .landed || $0.status == .closed }.count
        return Double(done) / Double(counted.count)
    }

    public func boardingPass(_ id: String) -> BoardingPass? { boardingPasses.first { $0.id == id } }
    public func member(_ id: String) -> TowerMember? { members.first { $0.id == id } }
    public func crewMember(_ id: String) -> CrewMember? { crew.first { $0.id == id } }
    public func airline(_ id: String?) -> Airline? { airlines.first { $0.id == id } }
}

// MARK: - Governance objects (device only)

public struct Credential: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var issuedBy: String
    public var recipientId: String
    public var recipientKind: RecipientKind
    public var permissions: [Permission]
    /// nil means the whole journey; otherwise these boarding passes only.
    public var scopeBoardingPassIds: [String]?
    public var keyCode: String
    public var expiresAt: Date?
    public var status: CredentialStatus

    public func covers(_ boardingPassId: String) -> Bool {
        scopeBoardingPassIds?.contains(boardingPassId) ?? true
    }
    public func isActive(at now: Date) -> Bool {
        status == .active && (expiresAt.map { now < $0 } ?? true)
    }
}

/// Read-only access to one folder of the Captain's storage, tied to a Credential.
public struct StorageGrant: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var credentialId: String
    public var repositoryId: String
    public var folderPath: String
    public var permission: String = "read"
    public var issuedBy: String
    /// The grant expires when this boarding pass lands.
    public var expiresOnLandingOf: String?
    public var link: String?
    public var status: CredentialStatus
}

public struct Connector: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var type: ConnectorType
    public var provider: String          // dropbox, box, gdrive, onedrive, icloud, device calendar
    public var auth: String              // "iOS Files", "device calendar", later "provider API"
    public var rootPath: String
    public var capabilities: [String]    // read, write, share, backgroundSync
    public var status: ConnectorStatus
    public init(id: String, type: ConnectorType, provider: String, auth: String, rootPath: String,
                capabilities: [String], status: ConnectorStatus = .linked) {
        self.id = id; self.type = type; self.provider = provider; self.auth = auth
        self.rootPath = rootPath; self.capabilities = capabilities; self.status = status
    }
}

public struct StatusChange: Codable, Hashable, Sendable {
    public var status: FlightStatus?
    public var eta: Date?
    public var reason: String?
    public var cause: WaitingCause?
    public var waitingOn: WaitingOn?
    /// Explicitly clears waitingOn when true.
    public var clearWaitingOn: Bool?
    public init(status: FlightStatus? = nil, eta: Date? = nil, reason: String? = nil, cause: WaitingCause? = nil,
                waitingOn: WaitingOn? = nil, clearWaitingOn: Bool? = nil) {
        self.status = status; self.eta = eta; self.reason = reason; self.cause = cause
        self.waitingOn = waitingOn; self.clearWaitingOn = clearWaitingOn
    }
}

/// A provider telling the Captain a deliverable was sent through its own channel.
/// Avalon carries the notice, never the file.
public struct DeliverableNotice: Codable, Hashable, Sendable {
    public var title: String
    public var sentVia: String
    public init(title: String, sentVia: String) { self.title = title; self.sentVia = sentVia }
}

public struct ActionRequest: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var type: ActionType
    public var params: [String: String]
    public init(id: String = Ids.make("AR"), type: ActionType, params: [String: String] = [:]) {
        self.id = id; self.type = type; self.params = params
    }
}

/// Every change from crew, plugins or the Concierge enters the FlightTower as a Proposal.
public struct Proposal: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var boardingPassId: String?
    public var authorId: String
    public var authorType: AuthorType
    public var reportedAt: Date
    public var message: String
    public var statusChange: StatusChange?
    public var deliverableNotice: DeliverableNotice?
    public var waypointReached: String?
    public var actionRequests: [ActionRequest]
    public var status: ProposalStatus
    public var decidedBy: String?
    public var decidedAt: Date?
    public var decisionNote: String?
    public var findingIds: [String]

    public init(id: String = Ids.make("PR"), boardingPassId: String?, authorId: String, authorType: AuthorType,
                reportedAt: Date, message: String, statusChange: StatusChange? = nil,
                deliverableNotice: DeliverableNotice? = nil, waypointReached: String? = nil,
                actionRequests: [ActionRequest] = []) {
        self.id = id; self.boardingPassId = boardingPassId; self.authorId = authorId; self.authorType = authorType
        self.reportedAt = reportedAt; self.message = message; self.statusChange = statusChange
        self.deliverableNotice = deliverableNotice; self.waypointReached = waypointReached
        self.actionRequests = actionRequests; self.status = .pending; self.findingIds = []
    }

    /// True when the proposal only moves status or ETA (eligible for auto-approve rules).
    public var isStatusOnly: Bool {
        deliverableNotice == nil && actionRequests.isEmpty && statusChange != nil
    }
}

public struct ActionRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var proposalId: String?
    public var actionRequestId: String
    public var type: ActionType
    public var executedAt: Date
    public var result: ActionResult
    public var detail: String
}

public struct Finding: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var pluginId: String
    public var pluginType: PluginType
    public var boardingPassId: String?
    public var proposalId: String?
    public var severity: FindingSeverity
    public var message: String
    public var recommendation: String?
    public var createdAt: Date
}

public enum AutoApproveRule: String, Codable, CaseIterable, Sendable {
    /// Delay plugin proposals that mark an overdue flight delayed.
    case delayRule
    /// ETA changes by crew that stay inside the grace window of the current ETA.
    case etaWithinGraceWindow
}

// MARK: - IDs

public enum Ids {
    private static var counter = 0
    private static let lock = NSLock()
    public static func make(_ prefix: String) -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return "\(prefix)-\(String(UUID().uuidString.prefix(4)))\(counter)"
    }
    public static func keyCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
