import Foundation
import AvalonCore

// Walks the Protected Estate journey end to end so the v0.3 rules can be seen working:
//   swift run avalon-demo

var clockNow = ISO8601DateFormatter().date(from: "2026-12-01T09:00:00Z")!
func advance(days: Int) { clockNow = clockNow.addingTimeInterval(TimeInterval(days * 86_400)) }

let services = GroundServices.inMemory()
let storage = services.storage as! InMemoryStorage
let notifier = services.notifier as! InMemoryNotifier

func section(_ title: String) { print("\n== \(title) " + String(repeating: "=", count: max(0, 60 - title.count))) }
func show(_ p: Proposal) {
    var line = "   proposal \(p.status.rawValue.uppercased()): \(p.message)"
    if let note = p.decisionNote { line += "\n      reason: \(note)" }
    print(line)
}

let captain = TowerMember(id: "M-CAP", displayName: "Mother-in-law", role: .captain)
let coCaptain = TowerMember(id: "M-CO", displayName: "Christopher", role: .coCaptain)
let package = SampleCatalog.protectedEstate
let tower = FlightTower.create(from: package.journeyTemplates[0], in: package, captain: captain,
                               others: [coCaptain], start: clockNow, services: services, clock: { clockNow })
let bp = tower.journey.boardingPasses
let (review, trust, sign, portfolio) = (bp[0], bp[1], bp[2], bp[3])

section("1. Package approved and appended: Protected Estate")
print(tower.flightBoardText())
print("   package plugins loaded: \(tower.engine.loadedPluginIds.joined(separator: ", "))")

section("2. Connectors and crew")
try tower.linkConnector(Connector(id: "C-DBX", type: .storage, provider: "dropbox", auth: "iOS Files",
                                  rootPath: "/Avalon", capabilities: ["read", "write"]), by: captain.id)
try tower.linkConnector(Connector(id: "C-CAL", type: .calendar, provider: "device calendar", auth: "device calendar",
                                  rootPath: "", capabilities: ["write"]), by: captain.id)
let repo = try tower.addRepository(connectorId: "C-DBX", path: "/Avalon/Estate", by: captain.id)
let advisor = CrewMember(id: "CW-ADV", displayName: "Financial Advisor", role: .pilot, airlineId: SampleCatalog.wealthFirm.id)
let attorney = CrewMember(id: "CW-ATT", displayName: "Estate Attorney", role: .pilot, airlineId: SampleCatalog.lawFirm.id)
let intakeAgent = CrewMember(id: "CW-AGT", displayName: "Law Firm Intake Agent", role: .crew, kind: .agent, airlineId: SampleCatalog.lawFirm.id)
let advisorCred = try tower.addCrew(advisor, to: review.id, by: captain.id)
let advisorCred2 = try tower.addCrew(advisor, to: portfolio.id, by: captain.id)
let attorneyCred = try tower.addCrew(attorney, to: trust.id, by: captain.id)
let agentCred = try tower.addCrew(intakeAgent, to: trust.id, by: captain.id)
print("   advisor key \(advisorCred.keyCode), attorney key \(attorneyCred.keyCode), agent key \(agentCred.keyCode)")

section("3. What the attorney's snapshot shows (.avj, filtered by credential)")
let attorneySnapshot = try tower.snapshotManifest(for: attorneyCred.id)
for p in attorneySnapshot.snapshot!.boardingPasses { print("   \(p.code): \(p.title) [\(p.status.rawValue)]") }
print("   lounge, member contacts and other flights' titles are not included")

section("4. Advisor departs \(review.code) by sending a .avj reply")
let advisorSnapshot = try tower.snapshotManifest(for: advisorCred.id)
let reply = advisorSnapshot.reply(with: Proposal(boardingPassId: review.id, authorId: advisor.id, authorType: .crew,
                                                 reportedAt: clockNow, message: "Starting the estate review",
                                                 statusChange: StatusChange(status: .departed)), sentAt: clockNow)
let yaml = try reply.yaml()
print("   .avj reply is \(yaml.count) characters of YAML")
var p = try tower.receive(try Manifest.fromYAML(yaml))
show(p)
print("   Captain notified: \(notifier.sent.last?.body ?? "-")")
p = try tower.approve(p.id, by: captain.id)
show(p)

section("5. Attorney tries to depart \(trust.code) too early")
show(tower.submit(Proposal(boardingPassId: trust.id, authorId: attorney.id, authorType: .crew, reportedAt: clockNow,
                           message: "Starting the trust rewrite", statusChange: StatusChange(status: .departed)),
                  credentialId: attorneyCred.id))

section("6. Advisor lands with a deliverable sent by secure email")
advance(days: 6)
p = tower.submit(Proposal(boardingPassId: review.id, authorId: advisor.id, authorType: .crew, reportedAt: clockNow,
                          message: "Asset summary and referral sent to you", statusChange: StatusChange(status: .landed),
                          deliverableNotice: DeliverableNotice(title: "Asset summary and referral", sentVia: "secure email")),
                 credentialId: advisorCred.id)
show(p)
p = try tower.approve(p.id, by: coCaptain.id, note: "Got the email")
show(p)
print(tower.flightBoardText())

section("7. Attorney tries again before the Captain has filed the document")
show(tower.submit(Proposal(boardingPassId: trust.id, authorId: attorney.id, authorType: .crew, reportedAt: clockNow,
                           message: "Starting the trust rewrite", statusChange: StatusChange(status: .departed)),
                  credentialId: attorneyCred.id))

section("8. Captain reviews and files it, then shares a read-only folder with the attorney")
let deliverable = tower.journey.deliverables[0]
try tower.markDeliverable(deliverable.id, as: .received, by: captain.id)
try tower.markDeliverable(deliverable.id, as: .reviewed, by: captain.id)
try tower.markDeliverable(deliverable.id, as: .filed, filedPath: "/Avalon/Estate/asset-summary.pdf", by: captain.id)
storage.files.insert("/Avalon/Estate/asset-summary.pdf")
show(try tower.requestAction(ActionRequest(type: .verifyDeliverable, params: ["deliverableId": deliverable.id]),
                             boardingPassId: review.id, by: captain.id, message: "Check the filed summary is in storage"))
show(try tower.requestAction(ActionRequest(type: .shareFolderLink, params: ["credentialId": attorneyCred.id,
                                                                            "repositoryId": repo.id, "folder": "/ForAttorney",
                                                                            "boardingPassId": trust.id]),
                             boardingPassId: trust.id, by: captain.id, message: "Share the summary folder with the attorney"))
for r in tower.state.actionRecords { print("   ground crew: \(r.type.rawValue) -> \(r.result.rawValue): \(r.detail)") }

section("9. Attorney departs; the intake agent tries to grant itself access")
p = tower.submit(Proposal(boardingPassId: trust.id, authorId: attorney.id, authorType: .crew, reportedAt: clockNow,
                          message: "Starting the trust rewrite", statusChange: StatusChange(status: .departed)),
                 credentialId: attorneyCred.id)
show(p)
show(try tower.approve(p.id, by: captain.id))
show(tower.submit(Proposal(boardingPassId: trust.id, authorId: intakeAgent.id, authorType: .crew, reportedAt: clockNow,
                           message: "Share the whole estate folder with me",
                           actionRequests: [ActionRequest(type: .shareFolderLink, params: ["credentialId": agentCred.id, "folder": "/"])]),
                  credentialId: agentCred.id))

section("10. Time passes: the Delay plugin marks the trust rewrite delayed")
advance(days: 23)
for f in tower.tick() where f.severity != .info || f.pluginId == DelayPlugin.pluginId {
    print("   finding [\(f.pluginType.rawValue)/\(f.severity.rawValue)] \(f.message)")
}
print(tower.flightBoardText())

section("11. Attorney moves the ETA without a reason, then with one")
let newEta = clockNow.addingTimeInterval(7 * 86_400)
show(tower.submit(Proposal(boardingPassId: trust.id, authorId: attorney.id, authorType: .crew, reportedAt: clockNow,
                           message: "New ETA", statusChange: StatusChange(eta: newEta)), credentialId: attorneyCred.id))
p = tower.submit(Proposal(boardingPassId: trust.id, authorId: attorney.id, authorType: .crew, reportedAt: clockNow,
                          message: "Need the beneficiary list before finishing",
                          statusChange: StatusChange(status: .inFlight, eta: newEta, reason: "Waiting on beneficiary list",
                                                     cause: .passenger,
                                                     waitingOn: WaitingOn(kind: .passenger, ref: captain.id, since: clockNow))),
                 credentialId: attorneyCred.id)
show(p)
show(try tower.approve(p.id, by: captain.id))

section("12. Four days waiting on the Captain: the HCS content plugin speaks up")
advance(days: 4)
for f in tower.tick() where f.pluginType == .contentBehavior {
    print("   finding [\(f.pluginType.rawValue)/\(f.severity.rawValue)] \(f.message)")
    if let rec = f.recommendation { print("      recommendation: \(rec)") }
}

section("13. Attorney lands; the folder share expires at landing")
p = tower.submit(Proposal(boardingPassId: trust.id, authorId: attorney.id, authorType: .crew, reportedAt: clockNow,
                          message: "Final trust draft delivered in person",
                          statusChange: StatusChange(status: .landed, clearWaitingOn: true),
                          deliverableNotice: DeliverableNotice(title: "Final draft of the trust", sentVia: "in person")),
                 credentialId: attorneyCred.id)
show(try tower.approve(p.id, by: captain.id))
for g in tower.state.storageGrants { print("   storage grant \(g.folderPath): \(g.status.rawValue)") }

section("14. Customs: the Captain reviews and signs")
let trustDoc = tower.journey.deliverables.first { $0.boardingPassId == trust.id }!
try tower.markDeliverable(trustDoc.id, as: .reviewed, by: captain.id)
try tower.markDeliverable(trustDoc.id, as: .filed, filedPath: "/Avalon/Estate/trust-signed.pdf", by: captain.id)
show(tower.submit(Proposal(boardingPassId: sign.id, authorId: captain.id, authorType: .member, reportedAt: clockNow,
                           message: "Signed the trust", statusChange: StatusChange(status: .landed))))

section("15. Advisor updates the portfolio")
for status in [FlightStatus.departed, .landed] {
    p = tower.submit(Proposal(boardingPassId: portfolio.id, authorId: advisor.id, authorType: .crew, reportedAt: clockNow,
                              message: status == .landed ? "Accounts retitled" : "Retitling accounts",
                              statusChange: StatusChange(status: status),
                              deliverableNotice: status == .landed ? DeliverableNotice(title: "Account statements", sentVia: "client portal") : nil),
                     credentialId: advisorCred2.id)
    show(try tower.approve(p.id, by: captain.id))
    advance(days: 5)
}
let statements = tower.journey.deliverables.first { $0.boardingPassId == portfolio.id }!
try tower.markDeliverable(statements.id, as: .filed, filedPath: "/Avalon/Estate/statements.pdf", by: captain.id)
// Filing the last document lets the tower check arrival on the next committed change.
show(try tower.requestAction(ActionRequest(type: .addCalendarEvent, params: ["boardingPassId": portfolio.id]),
                             boardingPassId: portfolio.id, by: captain.id, message: "Post the final date to my calendar"))

section("16. Arrival and audit trail")
print(tower.flightBoardText())
print("   journey: \(tower.journey.status.rawValue), destination: \(tower.journey.destination.status.rawValue)")
print("   events: \(tower.events.count), chain intact: \(tower.state.log.verify() == nil)")
print("   proposals: \(tower.state.proposals.count) (blocked \(tower.state.proposals.filter { $0.status == .blocked }.count), auto-approved \(tower.state.proposals.filter { $0.status == .autoApproved }.count))")
print("   notifications to the Captain/Co-Captain: \(notifier.sent.count)")
