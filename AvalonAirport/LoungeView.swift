import SwiftUI
import AvalonCore

/// Private space for passengers: notes, decisions, and whether the Concierge may look in.
/// Airlines never see the Lounge.
struct LoungeView: View {
    @Environment(JourneyStore.self) private var store
    private let fallback: JourneySnapshot
    /// Read live from the store so this screen reflects changes made on it.
    private var snapshot: JourneySnapshot { store.snapshot ?? fallback }

    init(snapshot: JourneySnapshot) {
        fallback = snapshot
    }

    @State private var note = ""
    @State private var decisionTitle = ""
    @State private var rationale = ""
    @State private var approvedBy = ""

    private var lounge: Lounge? { snapshot.lounge }
    private var members: [Passenger] {
        (lounge?.memberIds ?? snapshot.journey.passengerIds).compactMap { snapshot.passenger($0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    Label(member.name, systemImage: "person.fill")
                }
                Toggle("Concierge access", isOn: Binding(
                    get: { lounge?.conciergeAccess ?? false },
                    set: { store.setConciergeAccess($0) }
                ))
            } header: {
                Text("Members")
            } footer: {
                Text("Private to passengers. Airlines never see the Lounge, and it is left out of every package sent to them.")
            }

            Section("Notes") {
                if lounge?.conversations.isEmpty ?? true {
                    Text("No notes yet").foregroundStyle(.secondary)
                }
                ForEach(Array((lounge?.conversations ?? []).enumerated()), id: \.offset) { _, text in
                    Text(text)
                }
                TextField("Write a note for the passengers", text: $note)
                Button("Post note") {
                    store.addLoungeNote(note.trimmingCharacters(in: .whitespacesAndNewlines))
                    note = ""
                }
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Decisions") {
                if lounge?.decisions.isEmpty ?? true {
                    Text("No decisions recorded").foregroundStyle(.secondary)
                }
                ForEach(lounge?.decisions ?? []) { decision in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(decision.title).font(.headline)
                        if let rationale = decision.rationale {
                            Text(rationale).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text(decision.id)
                            if let by = snapshot.passenger(decision.approvedBy)?.name {
                                Text("approved by \(by)")
                            }
                            if let at = decision.at {
                                Text(at, format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            Section("Record a decision") {
                TextField("Decision", text: $decisionTitle)
                TextField("Why", text: $rationale)
                Picker("Approved by", selection: $approvedBy) {
                    Text("Nobody yet").tag("")
                    ForEach(members) { member in
                        Text(member.name).tag(member.id)
                    }
                }
                Button("Record decision") {
                    let why = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.addDecision(title: decisionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                      rationale: why.isEmpty ? nil : why,
                                      approvedBy: approvedBy.isEmpty ? nil : approvedBy)
                    decisionTitle = ""
                    rationale = ""
                    approvedBy = ""
                }
                .disabled(decisionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Lounge")
    }
}
