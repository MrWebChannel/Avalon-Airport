import Foundation
import Observation
import UniformTypeIdentifiers
import AvalonCore

extension UTType {
    static let avalonManifest = UTType(filenameExtension: "avj") ?? .data
}

/// Holds the FlightTower on this device (the Captain's), plus any snapshots received while acting as
/// a provider. Every change goes through the tower, then the state is saved.
@Observable
final class AppModel {
    private(set) var tower: FlightTower?
    private(set) var version = 0
    var actingMemberId: String = ""
    var errorMessage: String?
    var infoMessage: String?
    private(set) var providerSnapshots: [Manifest] = []

    let storage = FilesStorageService()
    let calendar = EventKitCalendarService()
    let notifier = LocalNotificationService()
    private var services: GroundServices { GroundServices(storage: storage, calendar: calendar, notifier: notifier) }

    private var towerURL: URL { URL.documentsDirectory.appending(path: "avalon-tower.json") }
    private var snapshotsURL: URL { URL.documentsDirectory.appending(path: "avalon-provider-snapshots.json") }

    init() {
        notifier.requestAuthorization()
        load()
    }

    // MARK: Reads (touch `version` so views refresh after each change)

    var journey: Journey? { _ = version; return tower?.journey }
    var board: [FlightBoardRow] { _ = version; return tower?.flightBoard() ?? [] }
    var pending: [Proposal] { _ = version; return tower?.pendingProposals ?? [] }
    var decided: [Proposal] {
        _ = version
        return (tower?.state.proposals ?? []).filter { $0.status != .pending }.sorted { ($0.decidedAt ?? .distantPast) > ($1.decidedAt ?? .distantPast) }
    }
    var events: [Event] { _ = version; return tower.map { Array($0.events.reversed()) } ?? [] }
    var credentials: [Credential] { _ = version; return tower?.state.credentials ?? [] }
    var grants: [StorageGrant] { _ = version; return tower?.state.storageGrants ?? [] }
    var connectors: [Connector] { _ = version; return tower?.state.connectors ?? [] }
    var actionRecords: [ActionRecord] { _ = version; return tower.map { Array($0.state.actionRecords.reversed()) } ?? [] }
    var snapshots: [Manifest] { _ = version; return providerSnapshots }
    var acting: TowerMember? { journey?.member(actingMemberId) }
    var atlas: [AtlasEntry] { _ = version; return tower?.atlasEntries ?? [] }
    var loungeMessages: [LoungeMessage] { _ = version; return tower?.loungeMessages ?? [] }

    func postToLounge(_ text: String) {
        perform { t in try t.postToLounge(text, by: actingMemberId) }
    }

    func findings(for bpId: String) -> [Finding] {
        _ = version
        return Array((tower?.findings(for: bpId) ?? []).suffix(20).reversed())
    }

    // MARK: Changes

    func perform(_ success: String? = nil, _ body: (FlightTower) throws -> Void) {
        guard let tower else { errorMessage = "Start a journey first"; return }
        do {
            try body(tower)
            save()
            if let success { infoMessage = success }
        } catch {
            errorMessage = error.localizedDescription
        }
        version += 1
    }

    func startJourney(template: JourneyTemplate, package: HubPackage, title: String, captainName: String, coCaptainName: String) {
        let captain = TowerMember(id: "M-CAP", displayName: captainName.isEmpty ? "Captain" : captainName, role: .captain)
        var others: [TowerMember] = []
        if !coCaptainName.isEmpty { others.append(TowerMember(id: "M-CO", displayName: coCaptainName, role: .coCaptain)) }
        tower = FlightTower.create(from: template, in: package, title: title.isEmpty ? nil : title,
                                   captain: captain, others: others, start: Date(), services: services)
        actingMemberId = captain.id
        save()
        version += 1
    }

    func resetJourney() {
        tower = nil
        try? FileManager.default.removeItem(at: towerURL)
        version += 1
    }

    /// Submits a proposal as the acting tower member (Captains commit at once).
    func propose(boardingPassId: String, message: String, change: StatusChange?) {
        perform { t in
            let p = t.submit(Proposal(boardingPassId: boardingPassId, authorId: actingMemberId, authorType: .member,
                                      reportedAt: Date(), message: message, statusChange: change))
            if p.status == .blocked { throw TowerError.invalid(p.decisionNote ?? "Blocked") }
        }
    }

    /// PluginEngine trigger onAppOpen: delay rules, flight checks and package plugins run when the app opens.
    func appOpened() {
        guard let tower else { return }
        tower.tick(trigger: .onAppOpen)
        save()
        version += 1
    }

    func runChecks() {
        perform { t in
            let findings = t.tick()
            let notable = findings.filter { $0.severity != .info }.count
            infoMessage = "Checks ran: \(findings.count) findings, \(notable) need attention"
        }
    }

    // MARK: Connectors

    func linkStorage(folder: URL) {
        perform("Storage folder linked") { t in
            let id = "C-\(UUID().uuidString.prefix(6))"
            try storage.storeBookmark(for: folder, connectorId: id)
            try t.linkConnector(Connector(id: id, type: .storage, provider: "Files", auth: "iOS Files",
                                          rootPath: folder.path, capabilities: ["read"]), by: actingMemberId)
            try t.addRepository(connectorId: id, path: folder.path, by: actingMemberId)
        }
    }

    func linkCalendar() async {
        let granted = await calendar.requestAccess()
        guard granted else { errorMessage = "Calendar access was not granted"; return }
        perform("Calendar linked") { t in
            try t.linkConnector(Connector(id: "C-CAL", type: .calendar, provider: "device calendar",
                                          auth: "device calendar", rootPath: "", capabilities: ["write"]), by: actingMemberId)
        }
    }

    // MARK: .avj files

    /// Writes a snapshot for one credential holder and returns the file to share.
    func exportSnapshot(credentialId: String) -> URL? {
        guard let tower else { return nil }
        do {
            let manifest = try tower.snapshotManifest(for: credentialId)
            let name = (manifest.recipient.name ?? "provider").replacingOccurrences(of: " ", with: "-")
            let url = FileManager.default.temporaryDirectory.appending(path: "Avalon-\(name).avj")
            try manifest.yaml().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// A proposal file goes to the tower; a snapshot file is kept for provider mode.
    func importManifest(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let manifest = try Manifest.fromYAML(String(contentsOf: url, encoding: .utf8))
            switch manifest.kind {
            case .proposal:
                perform { t in
                    let p = try t.receive(manifest)
                    infoMessage = "Proposal received: \(p.status.rawValue)"
                }
            case .snapshot:
                providerSnapshots.removeAll { $0.journeyId == manifest.journeyId && $0.credentialId == manifest.credentialId }
                providerSnapshots.append(manifest)
                saveSnapshots()
                infoMessage = "Snapshot added to Provider mode"
                version += 1
            }
        } catch {
            errorMessage = "Could not read that file: \(error.localizedDescription)"
        }
    }

    /// Provider mode: builds the reply file to send back to the Captain.
    func exportReply(to snapshot: Manifest, proposal: Proposal) -> URL? {
        do {
            let reply = snapshot.reply(with: proposal, sentAt: Date())
            let url = FileManager.default.temporaryDirectory.appending(path: "Avalon-reply-\(proposal.id).avj")
            try reply.yaml().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func removeSnapshot(_ manifest: Manifest) {
        providerSnapshots.removeAll { $0 == manifest }
        saveSnapshots()
        version += 1
    }

    // MARK: Persistence

    private func save() {
        guard let tower else { return }
        do { try tower.save().write(to: towerURL, options: .atomic) } catch { errorMessage = "Save failed: \(error.localizedDescription)" }
    }

    private func saveSnapshots() {
        if let data = try? JSONEncoder().encode(providerSnapshots) { try? data.write(to: snapshotsURL, options: .atomic) }
    }

    private func load() {
        if let data = try? Data(contentsOf: towerURL), let t = try? FlightTower.load(data, services: services) {
            tower = t
            actingMemberId = t.captain?.id ?? ""
        }
        if let data = try? Data(contentsOf: snapshotsURL),
           let list = try? JSONDecoder().decode([Manifest].self, from: data) {
            providerSnapshots = list
        }
    }
}
