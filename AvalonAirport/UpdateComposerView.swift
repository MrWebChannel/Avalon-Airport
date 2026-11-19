import SwiftUI
import AvalonCore

/// Posts an Update to a flight, as its airline (or customs holder) would.
/// The delay engine rejects it if a delayed flight's change lacks a reason or cause (rule 3).
struct UpdateComposerView: View {
    @Environment(JourneyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let snapshot: JourneySnapshot

    @State private var flightId: String
    @State private var message = ""
    @State private var status: FlightStatus? = nil
    @State private var etaShiftDays = 0
    @State private var reason = ""
    @State private var cause: WaitingCause? = nil
    @State private var errorMessage: String? = nil

    init(snapshot: JourneySnapshot) {
        self.snapshot = snapshot
        _flightId = State(initialValue: snapshot.orderedFlights.first?.id ?? "")
    }

    /// Read live from the store so the form reflects updates already applied.
    private var flight: Flight? { store.snapshot?.flight(flightId) }

    private var newEta: CalendarDay? {
        guard etaShiftDays != 0, let eta = flight?.eta else { return nil }
        return eta.adding(days: etaShiftDays)
    }

    private var needsJustification: Bool {
        guard let flight else { return false }
        if flight.status == .delayed { return newEta != nil || (status != nil && status != .delayed) }
        return status == .delayed
    }

    var body: some View {
        Form {
            Section("Flight") {
                Picker("Flight", selection: $flightId) {
                    ForEach(snapshot.orderedFlights) { flight in
                        Text("\(flight.code) · \(flight.title)").tag(flight.id)
                    }
                }
                if let flight {
                    LabeledContent("Status", value: flight.status.displayName)
                    LabeledContent("ETA", value: flight.eta?.boardString ?? "None")
                }
            }

            Section("Message") {
                TextField("What happened?", text: $message)
            }

            Section("Status change") {
                Picker("New status", selection: $status) {
                    Text("No change").tag(FlightStatus?.none)
                    ForEach(FlightStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(FlightStatus?.some(status))
                    }
                }
                LabeledContent("New ETA", value: newEta?.boardString ?? "No change")
                Button("Move ETA 1 day later") { etaShiftDays += 1 }
                Button("Move ETA 1 day earlier") { etaShiftDays -= 1 }
            }

            Section {
                TextField("Reason", text: $reason)
                Picker("Cause", selection: $cause) {
                    Text("None").tag(WaitingCause?.none)
                    ForEach(WaitingCause.allCases, id: \.self) { cause in
                        Text(cause.displayName).tag(WaitingCause?.some(cause))
                    }
                }
            } header: {
                Text("Justification")
            } footer: {
                Text(needsJustification
                     ? "Required: this change affects a delayed flight, so it needs a reason and a cause."
                     : "Only needed when a flight is delayed.")
            }

            Section {
                Button("Send update", action: submit)
                    .disabled(flight == nil)
            }
        }
        .navigationTitle("Post Update")
        .onChange(of: flightId) {
            etaShiftDays = 0
            status = nil
        }
        .alert("Update rejected", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func submit() {
        guard let flight else { return }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasChange = status != nil || newEta != nil || !trimmedReason.isEmpty || cause != nil
        let update = Update(
            id: "UP-\(UUID().uuidString.prefix(8))",
            journeyId: snapshot.journey.id,
            flightId: flight.id,
            author: author(for: flight),
            reportedAt: store.now,
            message: message.isEmpty ? nil : message,
            statusChange: hasChange
                ? StatusChange(status: status, eta: newEta,
                               reason: trimmedReason.isEmpty ? nil : trimmedReason, cause: cause)
                : nil)
        do {
            try store.submit(update)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func author(for flight: Flight) -> ActorRef {
        if let airlineId = flight.airlineId {
            return ActorRef(kind: .airline, id: airlineId, operatedBy: .human)
        }
        return flight.holder ?? ActorRef(kind: .passenger, id: snapshot.journey.passengerIds.first, operatedBy: .human)
    }
}
