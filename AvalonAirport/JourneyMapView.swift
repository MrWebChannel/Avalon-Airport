import SwiftUI
import AvalonCore

/// The journey as a route: every flight in dependency order, ending at the Destination.
struct JourneyMapView: View {
    @Environment(JourneyStore.self) private var store
    let snapshot: JourneySnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.boardRows) { row in
                        FlightNode(row: row, snapshot: snapshot)
                    }
                    if let destination = snapshot.destination {
                        DestinationNode(destination: destination)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Journey Map")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            CompletionRing(value: snapshot.completion)
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.journey.title)
                    .font(.title2.bold())
                if let description = snapshot.journey.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                let delayed = store.boardRows.filter(\.isDelayed).count
                Text(delayed == 0 ? "All flights on schedule" : "\(delayed) delayed")
                    .font(.caption.bold())
                    .foregroundStyle(delayed == 0 ? Theme.onTime : Theme.delayed)
            }
        }
        .tvFocusable()
    }
}

private struct FlightNode: View {
    let row: BoardRow
    let snapshot: JourneySnapshot

    private var flight: Flight { row.flight }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: flight.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(row.status.tint))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(flight.code)
                        .font(.headline.monospaced())
                    StatusChip(status: row.status)
                }
                Text(flight.title)
                    .font(.body)
                HStack(spacing: 12) {
                    Label(row.operatorName, systemImage: flight.kind == .customs ? "person" : "building.columns")
                    if let eta = flight.eta {
                        Label(eta.boardString, systemImage: "calendar")
                            .foregroundStyle(row.etaSlipped ? Theme.delayed : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !flight.dependsOn.isEmpty {
                    let codes = flight.dependsOn.compactMap { snapshot.flight($0)?.code }
                    Text("After \(codes.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(row.remarks, id: \.self) { remark in
                    Label(remark, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.delayed)
                }
            }
            .padding(.bottom, 28)
            Spacer(minLength: 0)
        }
        .background(alignment: .topLeading) {
            // The route line down to the next stop.
            Rectangle()
                .fill(Theme.rail)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.top, 44)
                .padding(.leading, 20.5)
        }
        .tvFocusable()
    }
}

private struct DestinationNode: View {
    let destination: Destination

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.amber))
            VStack(alignment: .leading, spacing: 6) {
                Text("DESTINATION")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.amber)
                Text(destination.title)
                    .font(.headline)
                ForEach(destination.successCriteria, id: \.self) { criterion in
                    Label(criterion, systemImage: destination.status == .achieved ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .tvFocusable()
    }
}

struct StatusChip: View {
    let status: FlightStatus

    var body: some View {
        Text(status.boardLabel)
            .font(.caption2.bold().monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(status.tint)
            .background(Capsule().fill(status.tint.opacity(0.18)))
    }
}

struct CompletionRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.rail, lineWidth: 8)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Theme.amber, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))%")
                .font(.headline.monospacedDigit())
        }
        .frame(width: 76, height: 76)
        .accessibilityLabel("Journey \(Int((value * 100).rounded())) percent complete")
    }
}
