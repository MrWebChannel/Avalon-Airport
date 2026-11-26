import SwiftUI
import AvalonCore

// MARK: - Flight board

struct FlightBoardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let journey = model.journey {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(journey.destination.title).font(.headline)
                            ProgressView(value: journey.completion)
                            Text("\(Int(journey.completion * 100))% complete · \(journey.status.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Flights") {
                        ForEach(model.board) { row in
                            NavigationLink(value: row.id) { FlightRowView(row: row) }
                        }
                    }
                }
                .navigationTitle(journey.title)
                .toolbar {
                    Button { model.runChecks() } label: { Label("Run checks", systemImage: "checkmark.shield") }
                }
                .refreshable { model.runChecks() }
            } else {
                NoJourneyView().navigationTitle("Dashboard")
            }
        }
    }
}

struct FlightRowView: View {
    let row: FlightBoardRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.code).font(.system(.headline, design: .monospaced))
                Text(row.title).font(.headline).lineLimit(1)
                Spacer()
                Text(row.status.rawValue.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(row.status.color)
            }
            HStack {
                Image(systemName: row.kind == .customs ? "person.badge.shield.checkmark" : "airplane")
                Text(row.operatedBy)
                Spacer()
                if let eta = row.eta { Text("ETA \(shortDate.string(from: eta))") }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let holding = row.holdingParty { Label(holding, systemImage: "hourglass").font(.caption).foregroundStyle(.orange) }
            if let delayedBy = row.delayedBy { Label("Delayed by \(delayedBy)", systemImage: "arrow.down.right").font(.caption).foregroundStyle(.red) }
            if row.noContact { Label("No contact from aircraft", systemImage: "antenna.radiowaves.left.and.right.slash").font(.caption).foregroundStyle(.red) }
            if row.deliverablesAwaitingReview > 0 {
                Label("\(row.deliverablesAwaitingReview) document(s) to review and file", systemImage: "doc.badge.clock")
                    .font(.caption).foregroundStyle(.purple)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Boarding pass detail

struct BoardingPassDetailView: View {
    @Environment(AppModel.self) private var model
    let boardingPassId: String
    @State private var shareItem: ShareItem?
    @State private var showAddCrew = false
    @State private var showStatus = false

    var body: some View {
        if let journey = model.journey, let bp = journey.boardingPass(boardingPassId) {
            List {
                Section("Flight") {
                    LabeledContent("Status", value: bp.status.rawValue)
                    LabeledContent("Operated by", value: bp.kind == .customs ? "You (customs)" : (journey.airline(bp.airlineId)?.name ?? "-"))
                    if let eta = bp.eta { LabeledContent("ETA", value: shortDate.string(from: eta)) }
                    if let original = bp.originalEta { LabeledContent("Original ETA", value: shortDate.string(from: original)) }
                    if !bp.dependsOn.isEmpty {
                        LabeledContent("Depends on", value: bp.dependsOn.compactMap { journey.boardingPass($0)?.code }.joined(separator: ", "))
                    }
                    if !bp.pluginIds.isEmpty { LabeledContent("Flight plugins", value: bp.pluginIds.joined(separator: ", ")) }
                    Button("Update status or ETA") { showStatus = true }
                }

                if bp.kind == .flight, let airline = journey.airline(bp.airlineId), let card = airline.contact, !card.isEmpty {
                    Section("Business card") {
                        BusinessCardView(card: card, caption: airline.name)
                    }
                }

                if bp.kind == .flight {
                    Section("Flight crew") {
                        ForEach(bp.crewIds, id: \.self) { id in
                            if let crew = journey.crewMember(id) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(crew.displayName)
                                        Text("\(crew.role.rawValue) · \(crew.kind.rawValue)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let cred = model.credentials.first(where: { $0.recipientId == id && $0.covers(bp.id) && $0.status == .active }) {
                                        Button("Send .avj") { shareItem = model.exportSnapshot(credentialId: cred.id).map(ShareItem.init) }
                                            .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        Button("Add Pilot, Co-Pilot or Crew") { showAddCrew = true }
                    }
                }

                let docs = journey.deliverables.filter { $0.boardingPassId == bp.id }
                if !docs.isEmpty {
                    Section("Deliverables") {
                        ForEach(docs) { d in LabeledContent(d.title, value: d.status.rawValue) }
                    }
                }

                Section("Findings") {
                    let findings = model.findings(for: bp.id)
                    if findings.isEmpty { Text("None yet. Run checks from the board.").foregroundStyle(.secondary) }
                    ForEach(findings) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(f.message, systemImage: f.severity.symbol).foregroundStyle(f.severity.color)
                            if let rec = f.recommendation { Text(rec).font(.caption).foregroundStyle(.secondary) }
                            Text("\(f.pluginId) · \(f.pluginType.rawValue)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("\(bp.code) \(bp.title)")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddCrew) { AddCrewView(boardingPass: bp) }
            .sheet(isPresented: $showStatus) { StatusChangeView(boardingPass: bp) }
            .sheet(item: $shareItem) { item in ShareSheetView(url: item.url) }
        } else {
            NoJourneyView()
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheetView: View {
    let url: URL
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up").font(.largeTitle)
            Text(url.lastPathComponent).font(.headline)
            Text("Send this file by Messages, email or AirDrop. It only contains what this credential may see.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium])
    }
}

struct AddCrewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let boardingPass: BoardingPass
    @State private var name = ""
    @State private var role: CrewRole = .pilot
    @State private var kind: CrewKind = .human

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Role", selection: $role) { ForEach(CrewRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Kind", selection: $kind) {
                    Text("Human").tag(CrewKind.human)
                    Text("AI agent").tag(CrewKind.agent)
                }
                Text("They get a credential scoped to \(boardingPass.code) only. They can propose updates; only you commit them.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Add crew")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let crew = CrewMember(id: "CW-\(UUID().uuidString.prefix(6))", displayName: name, role: role,
                                              kind: kind, airlineId: boardingPass.airlineId ?? "")
                        model.perform("\(name) added") { t in
                            _ = try t.addCrew(crew, to: boardingPass.id, by: model.actingMemberId)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

struct StatusChangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let boardingPass: BoardingPass
    @State private var status: FlightStatus = .scheduled
    @State private var changeEta = false
    @State private var eta = Date()
    @State private var reason = ""
    @State private var cause: WaitingCause = .passenger
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Status", selection: $status) { ForEach(FlightStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Change ETA", isOn: $changeEta)
                if changeEta { DatePicker("New ETA", selection: $eta, displayedComponents: .date) }
                Section("Reason (required when the flight is delayed)") {
                    TextField("Reason", text: $reason)
                    Picker("Cause", selection: $cause) { ForEach(WaitingCause.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                TextField("Note", text: $message)
            }
            .navigationTitle(boardingPass.code)
            .onAppear { status = boardingPass.status; eta = boardingPass.eta ?? Date() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") {
                        let change = StatusChange(status: status == boardingPass.status ? nil : status,
                                                  eta: changeEta ? eta : nil,
                                                  reason: reason.isEmpty ? nil : reason,
                                                  cause: reason.isEmpty ? nil : cause)
                        model.propose(boardingPassId: boardingPass.id, message: message.isEmpty ? "Status update" : message, change: change)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Journey map: are we getting closer, and what's holding us up?

struct JourneyMapView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let journey = model.journey {
                let rows = model.board
                let currentId = rows.first { !$0.status.isTerminal }?.id
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(journey.title).font(.title2.bold())
                            ProgressView(value: journey.completion)
                            Text("\(Int(journey.completion * 100))% of the way to \(journey.destination.title)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 20)

                        ForEach(rows) { row in
                            NavigationLink(value: row.id) {
                                JourneyStopView(row: row, isCurrent: row.id == currentId)
                            }
                            .buttonStyle(.plain)
                        }
                        DestinationStopView(destination: journey.destination)
                    }
                    .padding()
                }
                .navigationTitle("Journey")
                .navigationDestination(for: String.self) { id in BoardingPassDetailView(boardingPassId: id) }
            } else {
                NoJourneyView().navigationTitle("Journey")
            }
        }
    }
}

struct JourneyStopView: View {
    let row: FlightBoardRow
    let isCurrent: Bool

    private var done: Bool { row.status == .landed || row.status == .closed }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(done ? Color.green : (isCurrent ? Color.blue : Color(.systemGray5)))
                        .frame(width: 40, height: 40)
                    Image(systemName: done ? "checkmark" : (row.kind == .customs ? "signature" : "airplane"))
                        .foregroundStyle(done || isCurrent ? Color.white : Color.secondary)
                }
                Rectangle()
                    .fill(done ? Color.green : Color(.systemGray4))
                    .frame(width: 3, height: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.code).font(.system(.subheadline, design: .monospaced).bold())
                    Text(row.title).font(.headline)
                }
                Text(row.operatedBy).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(row.status.rawValue.uppercased()).font(.caption.bold()).foregroundStyle(row.status.color)
                    if let eta = row.eta { Text("ETA \(shortDate.string(from: eta))").font(.caption).foregroundStyle(.secondary) }
                }
                if let holding = row.holdingParty { Label(holding, systemImage: "hourglass").font(.caption).foregroundStyle(.orange) }
                if let delayedBy = row.delayedBy { Label("Delayed by \(delayedBy)", systemImage: "arrow.down.right").font(.caption).foregroundStyle(.red) }
            }
            .padding(.top, 8)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct DestinationStopView: View {
    let destination: Destination

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(destination.status == .achieved ? Color.green : Color.orange)
                    .frame(width: 40, height: 40)
                Image(systemName: "flag.checkered").foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.title).font(.headline)
                Text(destination.status == .achieved ? "Arrived" : "Destination")
                    .font(.caption.bold())
                    .foregroundStyle(destination.status == .achieved ? Color.green : Color.orange)
                ForEach(destination.successCriteria, id: \.self) { c in
                    Label(c, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }
}

// The Lounge moved to LoungeViews.swift (Jet-Stream chat) in build 5.
