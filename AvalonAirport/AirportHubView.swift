import SwiftUI
import AvalonCore

/// The client's airport: destination, people, providers, documents, tower controls and the event log.
struct AirportHubView: View {
    @Environment(JourneyStore.self) private var store
    let snapshot: JourneySnapshot

    var body: some View {
        List {
            Section {
                HubButton(title: "Flight Tower", detail: "Rules, clock, read and append the journey YAML",
                          systemImage: "antenna.radiowaves.left.and.right") {
                    FlightTowerView(snapshot: snapshot)
                }
                HubButton(title: "Lounge", detail: "Private notes and decisions for passengers",
                          systemImage: "sofa") {
                    LoungeView(snapshot: snapshot)
                }
                HubButton(title: "Atlas", detail: "Arrive at the destination and keep the record",
                          systemImage: "globe.americas") {
                    AtlasView(snapshot: snapshot)
                }
            }

            if let destination = snapshot.destination {
                Section("Destination") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination.title).font(.headline)
                        Text(destination.status == .achieved ? "Achieved" : "In progress")
                            .font(.caption)
                            .foregroundStyle(destination.status == .achieved ? Theme.onTime : .secondary)
                    }
                    ForEach(destination.successCriteria, id: \.self) { criterion in
                        Label(criterion, systemImage: "checklist")
                    }
                }
            }

            Section("Journey") {
                LabeledContent("Status", value: snapshot.journey.status.rawValue.capitalized)
                LabeledContent("Complete", value: "\(Int((snapshot.completion * 100).rounded()))%")
                LabeledContent("Flights", value: "\(snapshot.flights.count)")
                LabeledContent("Delayed", value: "\(store.boardRows.filter(\.isDelayed).count)")
            }

            Section("Updates") {
                NavigationLink {
                    UpdateComposerView(snapshot: snapshot)
                } label: {
                    Label("Post an update", systemImage: "square.and.pencil")
                }
            }

            Section("Passengers") {
                ForEach(snapshot.passengers) { passenger in
                    LabeledContent(passenger.name, value: passenger.role.rawValue.capitalized)
                }
            }

            Section("Airlines") {
                ForEach(snapshot.airlines) { airline in
                    LabeledContent(airline.name, value: airline.type?.capitalized ?? "")
                }
            }

            Section("Repositories") {
                ForEach(snapshot.repositories) { repository in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.provider.displayName)
                        Text("\(repository.path) · \(repository.mode.rawValue)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Event log") {
                ForEach(snapshot.events.reversed()) { event in
                    EventRow(event: event, snapshot: snapshot)
                }
            }
        }
        .navigationTitle("Airport Hub")
    }
}

private struct HubButton<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    @ViewBuilder let destination: () -> Content

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amber))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct EventRow: View {
    let event: Event
    let snapshot: JourneySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(event.type.displayName).font(.subheadline.bold())
                if let code = snapshot.flight(event.flightId)?.code {
                    Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if let at = event.receivedAt ?? event.reportedAt {
                    Text(at, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let payload = event.payload {
                if let previous = payload.previousEta, let new = payload.newEta {
                    Text("ETA \(previous.boardString) → \(new.boardString)").font(.caption)
                }
                if let reason = payload.reason {
                    Text(payload.cause.map { "\(reason) (\($0.displayName))" } ?? reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text("\(event.id) · \(event.actor.kind.rawValue)")
                if let hash = event.eventHash {
                    Text("#\(hash.prefix(10))")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
        }
    }
}
