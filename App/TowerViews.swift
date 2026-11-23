import SwiftUI
import UniformTypeIdentifiers
import AvalonCore

// MARK: - Inbox: proposals waiting for the Captain

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var rejecting: Proposal?
    @State private var rejectNote = ""

    var body: some View {
        List {
            Section("Waiting for you") {
                if model.pending.isEmpty { Text("Nothing to review").foregroundStyle(.secondary) }
                ForEach(model.pending) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        ProposalSummary(proposal: p)
                        HStack {
                            Button("Approve") {
                                model.perform("Approved") { t in _ = try t.approve(p.id, by: model.actingMemberId) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Reject", role: .destructive) { rejecting = p }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Section("Decided") {
                ForEach(model.decided.prefix(30)) { p in ProposalSummary(proposal: p) }
            }
        }
        .navigationTitle("Inbox")
        .toolbar {
            Button { importing = true } label: { Label("Import .avj", systemImage: "square.and.arrow.down") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.avalonManifest, .yaml, .plainText, .data]) { result in
            if case .success(let url) = result { model.importManifest(from: url) }
        }
        .alert("Reject proposal", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })) {
            TextField("Reason", text: $rejectNote)
            Button("Reject", role: .destructive) {
                if let p = rejecting {
                    let note = rejectNote.isEmpty ? "Rejected" : rejectNote
                    model.perform("Rejected") { t in _ = try t.reject(p.id, by: model.actingMemberId, note: note) }
                }
                rejecting = nil
                rejectNote = ""
            }
            Button("Cancel", role: .cancel) { rejecting = nil }
        }
    }
}

struct ProposalSummary: View {
    @Environment(AppModel.self) private var model
    let proposal: Proposal

    var body: some View {
        let journey = model.journey
        let code = proposal.boardingPassId.flatMap { journey?.boardingPass($0)?.code } ?? "Journey"
        let author = journey?.crewMember(proposal.authorId)?.displayName
            ?? journey?.member(proposal.authorId)?.displayName ?? proposal.authorId
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(code).font(.system(.subheadline, design: .monospaced).bold())
                Text(author).font(.subheadline)
                Spacer()
                Text(proposal.status.rawValue).font(.caption.bold())
                    .foregroundStyle(proposal.status == .blocked || proposal.status == .rejected ? Color.red : Color.secondary)
            }
            Text(proposal.message)
            if let sc = proposal.statusChange {
                let parts = [sc.status.map { "status \($0.rawValue)" }, sc.eta.map { "ETA \(shortDate.string(from: $0))" },
                             sc.reason.map { "reason: \($0)" }, sc.cause.map { "cause: \($0.rawValue)" },
                             sc.waitingOn.map { "waiting on \($0.kind.rawValue)" }].compactMap { $0 }
                if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
            if let notice = proposal.deliverableNotice {
                Label("\(notice.title) sent via \(notice.sentVia)", systemImage: "doc").font(.caption).foregroundStyle(.purple)
            }
            ForEach(proposal.actionRequests) { a in
                Label(a.type.rawValue, systemImage: "gearshape").font(.caption).foregroundStyle(.secondary)
            }
            if let note = proposal.decisionNote { Text(note).font(.caption).foregroundStyle(.red) }
        }
    }
}

// MARK: - Documents: the Captain reviews and files every deliverable

struct DeliverablesView: View {
    @Environment(AppModel.self) private var model
    @State private var filing: Deliverable?

    var body: some View {
        Group {
            if let journey = model.journey {
                List {
                    if journey.deliverables.isEmpty {
                        Text("Providers send documents to you through their own channel (portal, secure email, in person). They appear here when the provider tells the tower they sent one.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(journey.deliverables) { d in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(journey.boardingPass(d.boardingPassId)?.code ?? "").font(.system(.subheadline, design: .monospaced))
                                Text(d.title).font(.headline)
                                Spacer()
                                Text(d.status.rawValue).font(.caption.bold()).foregroundStyle(d.status == .filed ? Color.green : Color.purple)
                            }
                            if let via = d.sentVia { Text("Sent via \(via)").font(.caption).foregroundStyle(.secondary) }
                            if let path = d.filedPath { Text(path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                            if d.status != .filed {
                                HStack {
                                    if d.status == .sent {
                                        Button("Received") { mark(d, .received) }.buttonStyle(.bordered)
                                    }
                                    if d.status != .reviewed {
                                        Button("Reviewed") { mark(d, .reviewed) }.buttonStyle(.bordered)
                                    }
                                    Button("File it") { filing = d }.buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Documents")
                .fileImporter(isPresented: Binding(get: { filing != nil }, set: { if !$0 { filing = nil } }),
                              allowedContentTypes: [.item]) { result in
                    if case .success(let url) = result, let d = filing {
                        model.perform("Filed \(d.title)") { t in
                            try t.markDeliverable(d.id, as: .filed, filedPath: url.path, by: model.actingMemberId)
                        }
                    }
                    filing = nil
                }
            } else {
                NoJourneyView().navigationTitle("Documents")
            }
        }
    }

    private func mark(_ d: Deliverable, _ status: DeliverableStatus) {
        model.perform { t in try t.markDeliverable(d.id, as: status, by: model.actingMemberId) }
    }
}

// MARK: - Packages: approve and append a journey template

struct PackagesView: View {
    var body: some View {
        List {
            ForEach(SampleCatalog.hubs) { hub in
                let packages = SampleCatalog.packages.filter { $0.hubId == hub.id }
                Section {
                    if packages.isEmpty { Text("No packages yet").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(packages) { pkg in
                        ForEach(pkg.journeyTemplates) { template in
                            NavigationLink {
                                StartJourneyView(package: pkg, template: template)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(template.title).font(.headline)
                                    Text("\(pkg.title) · \(pkg.publisher)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(hub.name)
                } footer: {
                    Text(hub.summary)
                }
            }
        }
        .navigationTitle("Hubs")
    }
}

struct StartJourneyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let package: HubPackage
    let template: JourneyTemplate
    @State private var title = ""
    @State private var captainName = ""
    @State private var coCaptainName = ""
    @State private var confirmReplace = false

    var body: some View {
        Form {
            Section("Route") {
                ForEach(Array(template.steps.enumerated()), id: \.offset) { index, step in
                    let flight = step.flightId.flatMap { id in package.flights.first { $0.id == id } }
                    let airline = flight.flatMap { f in package.airlines.first { $0.id == f.airlineId } }
                    HStack {
                        Text("\(index + 1).")
                        VStack(alignment: .leading) {
                            Text(flight?.title ?? step.title ?? "Customs")
                            Text(step.kind == .customs ? "Customs: your decision" : (airline?.name ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Destination", value: template.destinationTitle)
            }
            if !package.plugins.isEmpty {
                Section("Package plugins") {
                    ForEach(package.plugins) { p in LabeledContent(p.name, value: p.type.rawValue) }
                }
            }
            Section("Your journey") {
                TextField("Journey name (optional)", text: $title)
                TextField("Captain (you)", text: $captainName)
                TextField("Co-Captain (optional)", text: $coCaptainName)
            }
            Button("Approve and start journey") {
                if model.journey != nil { confirmReplace = true } else { start() }
            }
        }
        .navigationTitle(template.title)
        .confirmationDialog("This replaces the journey on this device (MVP holds one journey).",
                            isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Replace journey", role: .destructive) { start() }
        }
    }

    private func start() {
        model.startJourney(template: template, package: package, title: title, captainName: captainName, coCaptainName: coCaptainName)
        dismiss()
    }
}

// MARK: - Tower: connectors, rules, plugins, audit trail

struct TowerView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingFolder = false

    var body: some View {
        @Bindable var model = model
        List {
            if let journey = model.journey {
                Section("Acting as") {
                    Picker("Member", selection: $model.actingMemberId) {
                        ForEach(journey.members.filter { $0.role.canCommit }) { m in Text("\(m.displayName) (\(m.role.rawValue))").tag(m.id) }
                    }
                }
                Section("Connectors") {
                    ForEach(model.connectors) { c in LabeledContent(c.type.rawValue, value: c.rootPath.isEmpty ? c.provider : c.rootPath) }
                    Button("Link a storage folder (Files)") { pickingFolder = true }
                    Button("Link my calendar") { Task { await model.linkCalendar() } }
                }
                Section("Storage grants (read-only)") {
                    if model.grants.isEmpty { Text("None").foregroundStyle(.secondary) }
                    ForEach(model.grants) { g in
                        LabeledContent(g.folderPath, value: g.status.rawValue)
                    }
                }
                Section("Credentials") {
                    ForEach(model.credentials) { c in
                        let name = journey.crewMember(c.recipientId)?.displayName ?? c.recipientId
                        HStack {
                            VStack(alignment: .leading) {
                                Text(name)
                                Text("key \(c.keyCode) · \(c.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if c.status == .active {
                                Menu("Actions") {
                                    if let bpId = c.scopeBoardingPassIds?.first, let repo = journey.repositories.first {
                                        Button("Share folder read-only") {
                                            model.perform { t in
                                                _ = try t.requestAction(ActionRequest(type: .shareFolderLink,
                                                                                  params: ["credentialId": c.id, "repositoryId": repo.id,
                                                                                           "folder": repo.path, "boardingPassId": bpId]),
                                                                    boardingPassId: bpId, by: model.actingMemberId,
                                                                    message: "Share \(repo.path) with \(name)")
                                            }
                                        }
                                    }
                                    Button("Revoke", role: .destructive) {
                                        model.perform("Credential revoked") { t in try t.revokeCredential(c.id, by: model.actingMemberId) }
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Plugins") {
                    if let tower = model.tower {
                        ForEach(tower.engine.loadedPluginIds, id: \.self) { id in
                            if let d = tower.engine.descriptor(id) {
                                LabeledContent(d.name, value: "\(d.type.rawValue) · \(d.tier.rawValue)")
                            }
                        }
                        Text("Run order: security, analytics, content-behavior").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Ground Crew") {
                    ForEach(model.actionRecords.prefix(20)) { r in
                        VStack(alignment: .leading) {
                            Text("\(r.type.rawValue): \(r.result.rawValue)").font(.subheadline)
                            Text(r.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Event log") {
                    if let tower = model.tower {
                        let broken = tower.state.log.verify()
                        Label(broken == nil ? "Chain intact (\(model.events.count) events)" : "Chain broken at \(broken!)",
                              systemImage: broken == nil ? "lock.shield" : "exclamationmark.octagon")
                            .foregroundStyle(broken == nil ? Color.green : Color.red)
                    }
                    ForEach(model.events.prefix(50)) { e in
                        VStack(alignment: .leading) {
                            Text(e.type.rawValue).font(.system(.caption, design: .monospaced))
                            Text(e.payload.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                Section {
                    Button("Delete this journey", role: .destructive) { model.resetJourney() }
                }
            } else {
                NoJourneyView()
            }
        }
        .navigationTitle("Flight Tower")
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.linkStorage(folder: url) }
        }
    }
}
