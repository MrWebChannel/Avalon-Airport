import Foundation
import Yams

// The Manifest (.avj) is the file traded between devices by Messages, email or AirDrop.
// Renamed from JourneyPackage in v0.3 so "Package" only means the sellable HubPackage.
// A snapshot goes from the FlightTower to someone holding a Credential, filtered to what that
// Credential may see. A proposal goes back to the FlightTower.

public enum ManifestKind: String, Codable, Sendable { case snapshot, proposal }

public struct ManifestParty: Codable, Hashable, Sendable {
    public var kind: String
    public var id: String
    public var name: String?
}

/// What a recipient may see of the journey. Other airlines' flights are reduced to code, status and ETA
/// so bottlenecks stay visible without revealing titles (a flight title alone can be sensitive).
public struct JourneySnapshot: Codable, Hashable, Sendable {
    public var journeyId: String
    public var title: String
    public var destinationTitle: String
    public var status: JourneyStatus
    public var captainName: String?
    public var boardingPasses: [BoardingPass]
    public var airlines: [Airline]
    public var crew: [CrewMember]
    public var deliverables: [Deliverable]
}

public struct Manifest: Codable, Hashable, Sendable {
    public var schemaVersion: String = "0.3"
    public var kind: ManifestKind
    public var journeyId: String
    public var sender: ManifestParty
    public var recipient: ManifestParty
    public var sentAt: Date
    public var lastEventHash: String?
    /// Lets the holder of a credential reply; the tower re-checks both on receipt.
    public var credentialId: String?
    public var keyCode: String?
    public var snapshot: JourneySnapshot?
    public var proposal: Proposal?

    public func yaml() throws -> String { try YAMLEncoder().encode(self) }
    public static func fromYAML(_ text: String) throws -> Manifest { try YAMLDecoder().decode(Manifest.self, from: text) }

    /// Builds the reply a provider sends back to the FlightTower.
    public func reply(with proposal: Proposal, sentAt: Date) -> Manifest {
        Manifest(kind: .proposal, journeyId: journeyId, sender: recipient, recipient: sender, sentAt: sentAt,
                 lastEventHash: lastEventHash, credentialId: credentialId, keyCode: keyCode,
                 snapshot: nil, proposal: proposal)
    }
}

public extension FlightTower {
    /// A snapshot filtered by a Credential. Never includes the Lounge, member contacts, credentials,
    /// storage grants or the tower's own settings.
    func snapshotManifest(for credentialId: String) throws -> Manifest {
        guard let cred = credential(credentialId), cred.isActive(at: now()) else {
            throw TowerError.notAuthorized("Credential is not active")
        }
        let j = journey
        let inScope = Set(j.boardingPasses.filter { cred.covers($0.id) }.map(\.id))
        let passes: [BoardingPass] = j.boardingPasses.map { bp in
            if inScope.contains(bp.id) { return bp }
            var r = bp
            r.title = bp.code
            r.crewIds = []; r.waypoints = []; r.deliverableIds = []; r.pluginIds = []; r.waitingOn = nil
            return r
        }
        let crew = j.crew.filter { c in j.boardingPasses.contains { inScope.contains($0.id) && $0.crewIds.contains(c.id) } }
            .map { c -> CrewMember in var x = c; x.contact = nil; return x }
        let snapshot = JourneySnapshot(
            journeyId: j.id, title: j.title, destinationTitle: j.destination.title, status: j.status,
            captainName: captain?.displayName, boardingPasses: passes, airlines: j.airlines, crew: crew,
            deliverables: j.deliverables.filter { inScope.contains($0.boardingPassId) })
        let recipientName = j.crewMember(cred.recipientId)?.displayName ?? j.member(cred.recipientId)?.displayName
        return Manifest(kind: .snapshot, journeyId: j.id,
                        sender: ManifestParty(kind: "tower", id: state.activeControllerId, name: captain?.displayName),
                        recipient: ManifestParty(kind: cred.recipientKind.rawValue, id: cred.recipientId, name: recipientName),
                        sentAt: now(), lastEventHash: state.log.lastHash, credentialId: cred.id, keyCode: cred.keyCode,
                        snapshot: snapshot, proposal: nil)
    }

    /// Receives a provider's reply. Identity comes from the credential, not from what the file claims.
    @discardableResult
    func receive(_ manifest: Manifest) throws -> Proposal {
        guard manifest.kind == .proposal, var proposal = manifest.proposal else {
            throw TowerError.invalid("Not a proposal manifest")
        }
        guard manifest.journeyId == journey.id else { throw TowerError.invalid("Manifest is for another journey") }
        guard let credId = manifest.credentialId, let cred = credential(credId), cred.keyCode == manifest.keyCode else {
            throw TowerError.notAuthorized("Unknown credential or wrong key code")
        }
        proposal.authorId = cred.recipientId
        proposal.authorType = cred.recipientKind == .crew ? .crew : .member
        return submit(proposal, credentialId: cred.id)
    }
}
