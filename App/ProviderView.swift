import SwiftUI
import UniformTypeIdentifiers
import AvalonCore

/// Provider mode: the same app used by an Airline's crew. Import the snapshot .avj the Captain sent,
/// propose an update, and send the reply .avj back. Nothing here changes the journey; the Captain's
/// FlightTower decides.
struct ProviderView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        List {
            if model.snapshots.isEmpty {
                Text("When a Captain sends you a .avj file, open it with Avalon or import it here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.snapshots, id: \.self) { m in
                if let s = m.snapshot {
                    NavigationLink {
                        ProviderJourneyView(manifest: m)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(s.title).font(.headline)
                            Text("Captain: \(s.captainName ?? "-") · as \(m.recipient.name ?? m.recipient.id)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { model.removeSnapshot(m) } }
                }
            }
        }
        .navigationTitle("Provider")
        .toolbar { Button { importing = true } label: { Label("Import .avj", systemImage: "square.and.arrow.down") } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.avalonManifest, .yaml, .plainText, .data]) { result in
            if case .success(let url) = result { model.importManifest(from: url) }
        }
    }
}

struct ProviderJourneyView: View {
    let manifest: Manifest

    var body: some View {
        let s = manifest.snapshot!
        List {
            Section("Your flights") {
                ForEach(s.boardingPasses.filter { $0.title != $0.code }) { bp in
                    NavigationLink {
                        ProviderComposeView(manifest: manifest, boardingPass: bp)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(bp.code) \(bp.title)").font(.headline)
                            Text("\(bp.status.rawValue) · ETA \(bp.eta.map { shortDate.string(from: $0) } ?? "-")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Other flights on this journey") {
                ForEach(s.boardingPasses.filter { $0.title == $0.code }) { bp in
                    LabeledContent(bp.code, value: "\(bp.status.rawValue) · \(bp.eta.map { shortDate.string(from: $0) } ?? "-")")
                }
            }
        }
        .navigationTitle(s.title)
    }
}

struct ProviderComposeView: View {
    @Environment(AppModel.self) private var model
    let manifest: Manifest
    let boardingPass: BoardingPass
    @State private var message = ""
    @State private var changeStatus = false
    @State private var status: FlightStatus = .departed
    @State private var changeEta = false
    @State private var eta = Date()
    @State private var reason = ""
    @State private var cause: WaitingCause = .passenger
    @State private var waiting = false
    @State private var waitingOn: WaitingCause = .passenger
    @State private var sentDeliverable = false
    @State private var deliverableTitle = ""
    @State private var sentVia = "secure email"
    @State private var shareItem: ShareItem?

    var body: some View {
        Form {
            Section("Update") {
                TextField("Message to the Captain", text: $message)
                Toggle("Change status", isOn: $changeStatus)
                if changeStatus {
                    Picker("Status", selection: $status) { ForEach(FlightStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                Toggle("Change ETA", isOn: $changeEta)
                if changeEta { DatePicker("New ETA", selection: $eta, displayedComponents: .date) }
            }
            Section("Reason (required if the flight is delayed)") {
                TextField("Reason", text: $reason)
                Picker("Cause", selection: $cause) { ForEach(WaitingCause.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            Section("Holding") {
                Toggle("We are waiting on someone", isOn: $waiting)
                if waiting {
                    Picker("Waiting on", selection: $waitingOn) { ForEach(WaitingCause.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
            }
            Section {
                Toggle("I sent a deliverable to the Captain", isOn: $sentDeliverable)
                if sentDeliverable {
                    TextField("Deliverable", text: $deliverableTitle)
                    TextField("Sent via (portal, secure email, in person)", text: $sentVia)
                }
            } header: {
                Text("Deliverable")
            } footer: {
                Text("Send the document itself through your own channel. Avalon only carries the notice; the Captain reviews and files it.")
            }
            Button("Create reply .avj") {
                let change = StatusChange(status: changeStatus ? status : nil, eta: changeEta ? eta : nil,
                                          reason: reason.isEmpty ? nil : reason, cause: reason.isEmpty ? nil : cause,
                                          waitingOn: waiting ? WaitingOn(kind: waitingOn, since: Date()) : nil)
                let hasChange = changeStatus || changeEta || waiting || !reason.isEmpty
                let proposal = Proposal(boardingPassId: boardingPass.id, authorId: manifest.recipient.id, authorType: .crew,
                                        reportedAt: Date(), message: message.isEmpty ? "Update on \(boardingPass.code)" : message,
                                        statusChange: hasChange ? change : nil,
                                        deliverableNotice: sentDeliverable && !deliverableTitle.isEmpty
                                            ? DeliverableNotice(title: deliverableTitle, sentVia: sentVia) : nil)
                shareItem = model.exportReply(to: manifest, proposal: proposal).map(ShareItem.init)
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle(boardingPass.code)
        .sheet(item: $shareItem) { item in ShareSheetView(url: item.url) }
    }
}
