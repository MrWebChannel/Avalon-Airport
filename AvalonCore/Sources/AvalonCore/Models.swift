import Foundation

// Domain model v0.2 — see spec/domain-model.md (the single source of truth).

// MARK: - Shared references

public enum ActorKind: String, Codable, Hashable, Sendable {
    case passenger, airline, tower, authority, external
}

public enum Operator: String, Codable, Hashable, Sendable {
    case human, agent, tower
}

/// Who did something, or who something belongs to: `{ kind: airline, id: AL-001, operatedBy: agent }`.
public struct ActorRef: Codable, Hashable, Sendable {
    public var kind: ActorKind
    public var id: String?
    public var operatedBy: Operator?

    public init(kind: ActorKind, id: String?, operatedBy: Operator? = nil) {
        self.kind = kind
        self.id = id
        self.operatedBy = operatedBy
    }

    public static func tower(_ id: String) -> ActorRef {
        ActorRef(kind: .tower, id: id, operatedBy: .tower)
    }
}

public struct Contact: Codable, Hashable, Sendable {
    public var email: String?
    public var phone: String?
}

// MARK: - Journey

public enum JourneyStatus: String, Codable, Hashable, Sendable {
    case active, paused, arrived, abandoned
}

public struct Journey: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var description: String?
    public var destinationId: String?
    public var status: JourneyStatus
    public var flightTowerId: String?
    @DefaultEmpty public var passengerIds: [String]
    @DefaultEmpty public var flightIds: [String]
    @DefaultEmpty public var airportIds: [String]
    @DefaultEmpty public var repositoryIds: [String]
    public var loungeId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    // completion % is computed from flight states, never stored (see JourneySnapshot.completion)
}

// MARK: - Destination

public enum DestinationStatus: String, Codable, Hashable, Sendable {
    case active, achieved
}

public struct Destination: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var description: String?
    @DefaultEmpty public var successCriteria: [String]
    public var status: DestinationStatus
    public var achievedAt: Date?
    public var image: String?
}

// MARK: - Passenger

public enum PassengerRole: String, Codable, Hashable, Sendable {
    case passenger, observer, family, caregiver
}

public struct IdentityProvider: Codable, Hashable, Sendable {
    public var type: String?
}

public struct Passenger: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var displayName: String?
    public var role: PassengerRole
    public var identityProvider: IdentityProvider?
    public var contact: Contact?
    @DefaultEmpty public var boardingPassIds: [String]

    public var name: String { displayName ?? id }
}

// MARK: - FlightTower

public struct DelayRules: Codable, Hashable, Sendable {
    /// A flight flips to delayed this long after its ETA passes.
    public var graceHours: Double
    /// "No contact from aircraft" after this many days without an update.
    public var staleContactDays: Int

    public init(graceHours: Double = 0, staleContactDays: Int = 7) {
        self.graceHours = graceHours
        self.staleContactDays = staleContactDays
    }
}

public struct TowerVisibility: Codable, Hashable, Sendable {
    public var `default`: String?
}

public struct NotificationPolicy: Codable, Hashable, Sendable {
    public var enabled: Bool
}

public struct RepositoryPolicy: Codable, Hashable, Sendable {
    public var mode: RepositoryMode
}

/// Governance for one journey. Lives only on the active controller's device:
/// never written to a repository and never included in a package.
public struct FlightTower: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var journeyId: String
    public var controllerIds: [String]
    public var activeControllerId: String?
    @DefaultEmpty public var boardingPassIds: [String]
    public var visibility: TowerVisibility?
    public var delayRules: DelayRules
    public var notificationPolicy: NotificationPolicy?
    public var repositoryPolicy: RepositoryPolicy?

    public init(id: String,
                journeyId: String,
                controllerIds: [String],
                activeControllerId: String?,
                boardingPassIds: [String] = [],
                delayRules: DelayRules = DelayRules()) {
        self.id = id
        self.journeyId = journeyId
        self.controllerIds = controllerIds
        self.activeControllerId = activeControllerId
        self.boardingPassIds = boardingPassIds
        self.visibility = TowerVisibility(default: "restricted")
        self.delayRules = delayRules
        self.notificationPolicy = NotificationPolicy(enabled: true)
        self.repositoryPolicy = RepositoryPolicy(mode: .readOnly)
    }
}

// MARK: - BoardingPass

public enum Permission: String, Codable, Hashable, Sendable {
    case read, update, invite, observe
}

public enum BoardingPassStatus: String, Codable, Hashable, Sendable {
    case active, revoked, expired
}

public enum OtherAirlinesVisibility: String, Codable, Hashable, Sendable {
    case none
    case namesOnly = "names-only"
    case status
}

public struct BoardingPassVisibility: Codable, Hashable, Sendable {
    /// Flight IDs, or `["all"]` (a bare `all` scalar is also accepted).
    public var flights: [String]
    public var showOtherAirlines: OtherAirlinesVisibility?
    public var showPassengerContact: Bool?
    public var lounge: Bool?

    enum CodingKeys: String, CodingKey { case flights, showOtherAirlines, showPassengerContact, lounge }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decode([String].self, forKey: .flights) {
            flights = list
        } else if let single = try c.decodeIfPresent(String.self, forKey: .flights) {
            flights = [single]
        } else {
            flights = []
        }
        showOtherAirlines = try c.decodeIfPresent(OtherAirlinesVisibility.self, forKey: .showOtherAirlines)
        showPassengerContact = try c.decodeIfPresent(Bool.self, forKey: .showPassengerContact)
        lounge = try c.decodeIfPresent(Bool.self, forKey: .lounge)
    }

    public var includesAllFlights: Bool { flights.contains("all") }
}

public struct BoardingPass: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var issuedBy: String
    public var journeyId: String
    public var recipient: ActorRef
    @DefaultEmpty public var permissions: [Permission]
    public var visibility: BoardingPassVisibility?
    public var keyCode: String?
    public var expiresAt: Date?
    public var status: BoardingPassStatus
}

// MARK: - Flight

public enum FlightKind: String, Codable, Hashable, Sendable {
    /// A unit of work operated by an airline.
    case flight
    /// A checkpoint held by a passenger or authority.
    case customs
}

public enum FlightStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case proposed, scheduled, boarding, departed
    case inFlight = "in-flight"
    case holding, delayed, landed, closed, cancelled

    /// Delay rule 1 never applies to these.
    public var isTerminal: Bool {
        self == .landed || self == .closed || self == .cancelled
    }

    public var isComplete: Bool {
        self == .landed || self == .closed
    }

    public var displayName: String {
        switch self {
        case .inFlight: return "In flight"
        default: return rawValue.capitalized
        }
    }

    public var boardLabel: String { displayName.uppercased() }
}

/// Who or what can hold a flight. Also the `cause` of a delay.
public enum WaitingCause: String, Codable, Hashable, Sendable, CaseIterable {
    case passenger, document, flight, airline, external

    public var displayName: String { rawValue.capitalized }
}

public struct WaitingOn: Codable, Hashable, Sendable {
    public var kind: WaitingCause?
    public var ref: String?
    public var since: Date?

    public init(kind: WaitingCause?, ref: String? = nil, since: Date? = nil) {
        self.kind = kind
        self.ref = ref
        self.since = since
    }
}

public struct Flight: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var journeyId: String?
    /// Shown on the flight board, e.g. `AH-201`.
    public var code: String
    public var title: String
    public var airlineId: String?
    public var kind: FlightKind
    /// For customs checkpoints: the passenger or authority holding it.
    public var holder: ActorRef?
    public var status: FlightStatus
    public var originalEta: CalendarDay?
    public var eta: CalendarDay?
    public var departedAt: Date?
    public var landedAt: Date?
    public var lastContactAt: Date?
    /// Flights that must land first.
    @DefaultEmpty public var dependsOn: [String]
    /// Who or what is holding this flight right now; nil when moving.
    public var waitingOn: WaitingOn?
    @DefaultEmpty public var deliverables: [String]

    public var isWaiting: Bool { waitingOn?.kind != nil }
}

// MARK: - Event

public enum EventType: String, Codable, Hashable, Sendable {
    case journeyCreated = "journey_created"
    case flightCreated = "flight_created"
    case flightAssigned = "flight_assigned"
    case flightDeparted = "flight_departed"
    case etaChanged = "eta_changed"
    case flightDelayed = "flight_delayed"
    case flightLanded = "flight_landed"
    case flightCancelled = "flight_cancelled"
    case waitingOnChanged = "waiting_on_changed"
    case boardingPassIssued = "boarding_pass_issued"
    case boardingPassRevoked = "boarding_pass_revoked"
    case airlineJoined = "airline_joined"
    case towerTransferred = "tower_transferred"
    case destinationAchieved = "destination_achieved"
    /// Not in spec v0.2: records status moves with no dedicated type
    /// (boarding, in-flight, holding, closed, scheduled…) so nothing is changed silently.
    case flightStatusChanged = "flight_status_changed"

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct EventPayload: Codable, Hashable, Sendable {
    public var previousEta: CalendarDay?
    public var newEta: CalendarDay?
    public var previousStatus: FlightStatus?
    public var status: FlightStatus?
    public var reason: String?
    public var cause: WaitingCause?
    public var waitingOn: WaitingOn?
    public var message: String?

    public init(previousEta: CalendarDay? = nil, newEta: CalendarDay? = nil,
                previousStatus: FlightStatus? = nil, status: FlightStatus? = nil,
                reason: String? = nil, cause: WaitingCause? = nil,
                waitingOn: WaitingOn? = nil, message: String? = nil) {
        self.previousEta = previousEta
        self.newEta = newEta
        self.previousStatus = previousStatus
        self.status = status
        self.reason = reason
        self.cause = cause
        self.waitingOn = waitingOn
        self.message = message
    }
}

/// Immutable history. Never edited, never deleted.
public struct Event: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var journeyId: String?
    public var flightId: String?
    public var actor: ActorRef
    public var type: EventType
    /// When the sender says it happened.
    public var reportedAt: Date?
    /// When the controller's device logged it.
    public var receivedAt: Date?
    public var payload: EventPayload?
    public var previousEventHash: String?
    public var eventHash: String?
    public var signature: String?
}

// MARK: - Update

public struct StatusChange: Codable, Hashable, Sendable {
    public var status: FlightStatus?
    public var eta: CalendarDay?
    /// Required when the flight is delayed.
    public var reason: String?
    /// Required when the flight is delayed.
    public var cause: WaitingCause?

    public init(status: FlightStatus? = nil, eta: CalendarDay? = nil,
                reason: String? = nil, cause: WaitingCause? = nil) {
        self.status = status
        self.eta = eta
        self.reason = reason
        self.cause = cause
    }
}

/// A human-readable message. May carry a status change, which produces Events.
public struct Update: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var journeyId: String?
    public var flightId: String
    public var author: ActorRef
    public var reportedAt: Date?
    public var message: String?
    public var statusChange: StatusChange?

    public init(id: String, journeyId: String?, flightId: String, author: ActorRef,
                reportedAt: Date?, message: String?, statusChange: StatusChange?) {
        self.id = id
        self.journeyId = journeyId
        self.flightId = flightId
        self.author = author
        self.reportedAt = reportedAt
        self.message = message
        self.statusChange = statusChange
    }
}

// MARK: - Repository

public enum RepositoryProvider: String, Codable, Hashable, Sendable {
    case dropbox, box, gdrive, onedrive, icloud

    public var displayName: String {
        switch self {
        case .dropbox: return "Dropbox"
        case .box: return "Box"
        case .gdrive: return "Google Drive"
        case .onedrive: return "OneDrive"
        case .icloud: return "iCloud Drive"
        }
    }
}

public enum RepositoryMode: String, Codable, Hashable, Sendable {
    case readOnly = "read-only"
    case readWrite = "read-write"
}

public struct Repository: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var provider: RepositoryProvider
    public var path: String
    public var mode: RepositoryMode
    public var ownerPassengerId: String?
}

// MARK: - Lounge

public struct Decision: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var rationale: String?
    public var approvedBy: String?
    public var at: Date?

    public init(id: String, title: String, rationale: String?, approvedBy: String?, at: Date?) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.approvedBy = approvedBy
        self.at = at
    }
}

/// Private space for passengers. Airlines never see it.
public struct Lounge: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var journeyId: String?
    @DefaultEmpty public var memberIds: [String]
    public var conciergeAccess: Bool?
    /// MVP: plain notes, newest last.
    @DefaultEmpty public var conversations: [String]
    @DefaultEmpty public var decisions: [Decision]

    public init(id: String, journeyId: String?, memberIds: [String], conciergeAccess: Bool? = false,
                conversations: [String] = [], decisions: [Decision] = []) {
        self.id = id
        self.journeyId = journeyId
        self.memberIds = memberIds
        self.conciergeAccess = conciergeAccess
        self.conversations = conversations
        self.decisions = decisions
    }
}

// MARK: - Atlas

public struct AtlasEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var journeyId: String?
    public var destinationId: String?
    public var title: String?
    public var startedAt: Date?
    public var completedAt: Date?
    public var summary: String?
    @DefaultEmpty public var repositoryIds: [String]

    public init(id: String, journeyId: String?, destinationId: String?, title: String?,
                startedAt: Date?, completedAt: Date?, summary: String?, repositoryIds: [String] = []) {
        self.id = id
        self.journeyId = journeyId
        self.destinationId = destinationId
        self.title = title
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.summary = summary
        self.repositoryIds = repositoryIds
    }
}

// MARK: - Light objects (reserved)

public struct Airline: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: String?
    public var contact: Contact?
}

public struct Airport: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var ownerAirlineId: String?
    @DefaultEmpty public var airlineIds: [String]
}

public struct Hub: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    @DefaultEmpty public var airportIds: [String]
}

public struct Route: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sourceAirportId: String?
    public var destinationAirportId: String?
    public var relationshipType: String?
}

public struct Concierge: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var enabled: Bool
    @DefaultEmpty public var capabilities: [String]
}
