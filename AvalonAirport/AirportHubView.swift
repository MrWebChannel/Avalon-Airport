import SwiftUI
import AvalonCore

/// The client's airport: destination, people, providers, documents, tower controls and the event log.
struct AirportHubView: View {
    @Environment(JourneyStore.self) private var store
    let snapshot: JourneySnapshot

    var body: some View {
        List {
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

            Section {
                LabeledContent("Tower clock") {
                    Text(store.now, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
                Button("Advance 1 day") { store.advanceClock(days: 1) }
                Button("Advance 1 week") { store.advanceClock(days: 7) }
                if store.clockOffsetDays != 0 {
                    Button("Back to real time") { store.resetClock() }
                }
            } header: {
                Text("Flight Tower")
            } footer: {
                Text("Flights flip to delayed once their ETA day passes. Delays already logged stay in the log.")
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

            Section {
                Button("Reload sample journey", role: .destructive) { store.loadSample() }
            }
        }
        .navigationTitle("Airport Hub")
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
