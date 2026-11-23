import Foundation

// MARK: - Services Ground Crew may call (provided by the app; in-memory versions for tests and the demo)

public protocol StorageService: AnyObject {
    /// Shares a folder of the Captain's storage, read-only, with a recipient. Returns a link when the
    /// connector can make one; nil means the Captain is asked to share it in the provider's app.
    func shareFolder(repository: Repository, folder: String, with recipientName: String) throws -> String?
    func revokeFolder(repository: Repository, folder: String, link: String?) throws
    func fileExists(repository: Repository, path: String) -> Bool
}

public protocol CalendarService: AnyObject {
    func upsertEvent(key: String, title: String, date: Date) throws
}

public protocol NotificationService: AnyObject {
    func notify(recipientId: String, title: String, body: String)
}

public struct GroundServices {
    public var storage: StorageService
    public var calendar: CalendarService
    public var notifier: NotificationService
    public init(storage: StorageService, calendar: CalendarService, notifier: NotificationService) {
        self.storage = storage; self.calendar = calendar; self.notifier = notifier
    }
    public static func inMemory() -> GroundServices {
        GroundServices(storage: InMemoryStorage(), calendar: InMemoryCalendar(), notifier: InMemoryNotifier())
    }
}

public final class InMemoryStorage: StorageService {
    public var files: Set<String> = []
    public private(set) var activeShares: [String: String] = [:]   // folder -> recipient
    public init() {}
    public func shareFolder(repository: Repository, folder: String, with recipientName: String) throws -> String? {
        activeShares[repository.path + folder] = recipientName
        return "memory://\(repository.path)\(folder)"
    }
    public func revokeFolder(repository: Repository, folder: String, link: String?) throws {
        activeShares[repository.path + folder] = nil
    }
    public func fileExists(repository: Repository, path: String) -> Bool { files.contains(path) }
}

public final class InMemoryCalendar: CalendarService {
    public private(set) var events: [String: (title: String, date: Date)] = [:]
    public init() {}
    public func upsertEvent(key: String, title: String, date: Date) throws { events[key] = (title, date) }
}

public final class InMemoryNotifier: NotificationService {
    public private(set) var sent: [(recipientId: String, title: String, body: String)] = []
    public init() {}
    public func notify(recipientId: String, title: String, body: String) { sent.append((recipientId, title, body)) }
}

// MARK: - Ground Crew

/// The native executor inside the FlightTower. It runs approved ActionRequests from the fixed action
/// catalog compiled into the app, checks Credentials and StorageGrants at execution time, makes
/// repeats harmless, and logs every outcome as an ActionRecord and an Event.
public final class GroundCrew {
    public let actionCatalog: [ActionType] = ActionType.allCases
    public var services: GroundServices

    public init(services: GroundServices) { self.services = services }

    func execute(_ request: ActionRequest, for proposal: Proposal, in tower: FlightTower) -> ActionRecord {
        let now = tower.now()
        func record(_ result: ActionResult, _ detail: String) -> ActionRecord {
            let rec = ActionRecord(id: Ids.make("AX"), proposalId: proposal.id, actionRequestId: request.id,
                                   type: request.type, executedAt: now, result: result, detail: detail)
            tower.state.actionRecords.append(rec)
            tower.log(.actionExecuted, actor: .tower, boardingPassId: proposal.boardingPassId, reportedAt: now,
                      payload: ["action": request.type.rawValue, "result": result.rawValue, "detail": detail])
            return rec
        }

        if tower.state.actionRecords.contains(where: { $0.actionRequestId == request.id && $0.result == .success }) {
            return record(.skipped, "Already executed")
        }
        guard proposal.status == .approved || proposal.status == .autoApproved else {
            return record(.failed, "Proposal is not approved")
        }
        guard actionCatalog.contains(request.type) else { return record(.failed, "Action not in catalog") }

        let p = request.params
        let bpId = p["boardingPassId"] ?? proposal.boardingPassId
        let bp = bpId.flatMap { tower.journey.boardingPass($0) }

        switch request.type {
        case .notify:
            let to = p["to"].map { [$0] } ?? tower.commitMemberIds
            for id in to { services.notifier.notify(recipientId: id, title: p["title"] ?? "Avalon", body: p["message"] ?? proposal.message) }
            return record(.success, "Notified \(to.joined(separator: ", "))")

        case .addCalendarEvent, .updateEta:
            guard let bp, let eta = bp.eta else { return record(.failed, "No boarding pass ETA to post") }
            do {
                try services.calendar.upsertEvent(key: bp.id, title: "\(bp.code) \(bp.title) ETA", date: eta)
                return record(.success, "Calendar updated for \(bp.code)")
            } catch { return record(.failed, error.localizedDescription) }

        case .remindCustoms:
            guard let bp, bp.kind == .customs else { return record(.failed, "Not a customs step") }
            for id in tower.commitMemberIds {
                services.notifier.notify(recipientId: id, title: "Waiting on you", body: "\(bp.code) \(bp.title) is waiting for your decision")
            }
            return record(.success, "Reminded the Captain about \(bp.code)")

        case .verifyDeliverable:
            guard let dId = p["deliverableId"], let d = tower.journey.deliverables.first(where: { $0.id == dId }),
                  let path = d.filedPath, let repo = tower.journey.repositories.first else {
                return record(.failed, "Deliverable not filed or no repository linked")
            }
            return services.storage.fileExists(repository: repo, path: path)
                ? record(.success, "\(d.title) found at \(path)")
                : record(.failed, "\(d.title) not found at \(path)")

        case .shareFolderLink:
            guard let credId = p["credentialId"], let cred = tower.credential(credId), cred.isActive(at: now) else {
                return record(.failed, "Credential missing, expired or revoked")
            }
            guard let repo = tower.journey.repositories.first(where: { $0.id == (p["repositoryId"] ?? "") })
                    ?? tower.journey.repositories.first else {
                return record(.failed, "No repository linked")
            }
            let folder = p["folder"] ?? "/"
            let name = tower.journey.crewMember(cred.recipientId)?.displayName
                ?? tower.journey.member(cred.recipientId)?.displayName ?? cred.recipientId
            do {
                let link = try services.storage.shareFolder(repository: repo, folder: folder, with: name)
                let grant = StorageGrant(id: Ids.make("SG"), credentialId: cred.id, repositoryId: repo.id,
                                         folderPath: folder, issuedBy: proposal.decidedBy ?? "tower",
                                         expiresOnLandingOf: bpId, link: link, status: .active)
                tower.state.storageGrants.append(grant)
                tower.log(.storageGranted, actor: .tower, boardingPassId: bpId, reportedAt: now,
                          payload: ["grantId": grant.id, "credentialId": cred.id, "folder": folder, "permission": "read"])
                return record(.success, link == nil ? "Share \(folder) read-only with \(name) in your storage app" : "Shared \(folder) read-only with \(name)")
            } catch { return record(.failed, error.localizedDescription) }

        case .revokeFolderLink:
            guard let gId = p["grantId"] else { return record(.failed, "No grant named") }
            return tower.revokeGrant(gId, reason: "revoked", now: now)
                ? record(.success, "Revoked \(gId)") : record(.failed, "Grant not active")

        case .issueCredential:
            guard let recipient = p["recipientId"] else { return record(.failed, "No recipient") }
            let kind = RecipientKind(rawValue: p["recipientKind"] ?? "crew") ?? .crew
            let perms = (p["permissions"] ?? "read,propose").split(separator: ",").compactMap { Permission(rawValue: String($0)) }
            let scope = p["scope"].map { $0.split(separator: ",").map(String.init) }
            let cred = tower.makeCredential(recipientId: recipient, kind: kind, permissions: perms, scope: scope,
                                            issuedBy: proposal.decidedBy ?? "tower", now: now)
            return record(.success, "Issued \(cred.id) key \(cred.keyCode)")

        case .revokeCredential:
            guard let credId = p["credentialId"] else { return record(.failed, "No credential named") }
            return tower.revokeCredentialInternal(credId, now: now)
                ? record(.success, "Revoked \(credId)") : record(.failed, "Credential not active")
        }
    }
}
