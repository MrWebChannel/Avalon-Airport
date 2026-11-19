import SwiftUI
import AvalonCore

/// Where you have been: completed journeys, and the button that lands the current one.
struct AtlasView: View {
    @Environment(JourneyStore.self) private var store
    private let fallback: JourneySnapshot
    /// Read live from the store so this screen reflects changes made on it.
    private var snapshot: JourneySnapshot { store.snapshot ?? fallback }

    init(snapshot: JourneySnapshot) {
        fallback = snapshot
    }

    @State private var summary = ""
    @State private var confirming = false

    private var openFlights: Int {
        snapshot.flights.filter { !$0.status.isComplete && $0.status != .cancelled }.count
    }

    var body: some View {
        List {
            if let destination = snapshot.destination {
                Section {
                    HStack(spacing: 16) {
                        CompletionRing(value: snapshot.completion)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(destination.title).font(.headline)
                            Text(snapshot.journey.title).font(.subheadline).foregroundStyle(.secondary)
                            Text(destination.status == .achieved ? "Arrived" : "En route")
                                .font(.caption.bold())
                                .foregroundStyle(destination.status == .achieved ? Theme.onTime : Theme.amber)
                        }
                    }
                    .tvFocusable()

                    if destination.status != .achieved {
                        TextField("Summary of the trip", text: $summary)
                        Button("Mark destination achieved") { confirming = true }
                    }
                } header: {
                    Text("Current journey")
                } footer: {
                    if destination.status != .achieved && openFlights > 0 {
                        Text("\(openFlights) flights have not landed yet.")
                    }
                }
            }

            Section("Atlas") {
                if snapshot.atlas.isEmpty {
                    Text("No completed journeys yet. Arrivals are recorded here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.atlas.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title ?? entry.id).font(.headline)
                        if let started = entry.startedAt, let completed = entry.completedAt {
                            Text("\(started.formatted(date: .abbreviated, time: .omitted)) to \(completed.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let summary = entry.summary {
                            Text(summary).font(.subheadline)
                        }
                        ForEach(entry.repositoryIds, id: \.self) { id in
                            if let repository = snapshot.repositories.first(where: { $0.id == id }) {
                                Label("\(repository.provider.displayName) \(repository.path)", systemImage: "folder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Atlas")
        .confirmationDialog("Mark the destination achieved?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Arrive") {
                let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                store.arrive(summary: text.isEmpty ? nil : text)
                summary = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This logs destination_achieved, sets the journey to arrived and adds it to the Atlas. It cannot be undone.")
        }
    }
}
