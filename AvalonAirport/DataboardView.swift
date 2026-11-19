import SwiftUI
import AvalonCore

/// Airport departure board: one line per flight, amber on black.
struct DataboardView: View {
    @Environment(JourneyStore.self) private var store
    let snapshot: JourneySnapshot

    var body: some View {
        GeometryReader { geo in
            let layout = BoardLayout(width: geo.size.width)
            VStack(spacing: 0) {
                BoardHeader(title: snapshot.journey.title, now: store.now, offsetDays: store.clockOffsetDays)
                BoardColumnHeader(layout: layout)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(store.boardRows) { row in
                            BoardLine(row: row, layout: layout)
                                .tvFocusable()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, layout.gutter)
        }
        .background(Theme.boardBackground.ignoresSafeArea())
        .foregroundStyle(Theme.amber)
    }
}

/// Column widths as fractions of the board, wide (iPad / TV) or compact (iPhone).
struct BoardLayout {
    let width: CGFloat
    var gutter: CGFloat { wide ? 24 : 10 }
    var wide: Bool { width > 640 }
    private var usable: CGFloat { max(0, width - gutter * 2 - 24) }

    var eta: CGFloat { usable * (wide ? 0.10 : 0.0) }
    var flight: CGFloat { usable * (wide ? 0.11 : 0.24) }
    var title: CGFloat { usable * (wide ? 0.30 : 0.46) }
    var airline: CGFloat { usable * (wide ? 0.17 : 0.0) }
    var status: CGFloat { usable * (wide ? 0.13 : 0.30) }
    var remarks: CGFloat { usable * (wide ? 0.19 : 0.0) }
}

private struct BoardHeader: View {
    let title: String
    let now: Date
    let offsetDays: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "airplane.departure")
            Text("DEPARTURES")
                .font(.title.bold().monospaced())
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.headline.monospaced())
                Text(offsetDays == 0 ? title.uppercased() : "SIMULATED +\(offsetDays)D · \(title.uppercased())")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .opacity(0.7)
            }
        }
        .padding(.vertical, 12)
    }
}

private struct BoardColumnHeader: View {
    let layout: BoardLayout

    var body: some View {
        HStack(spacing: 4) {
            if layout.wide { cell("ETA", layout.eta) }
            cell("FLIGHT", layout.flight)
            cell("DESTINATION", layout.title)
            if layout.wide { cell("OPERATOR", layout.airline) }
            cell("STATUS", layout.status)
            if layout.wide { cell("REMARKS", layout.remarks) }
        }
        .font(.caption.bold().monospaced())
        .opacity(0.6)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func cell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .leading)
    }
}

private struct BoardLine: View {
    let row: BoardRow
    let layout: BoardLayout

    private var statusText: String {
        if row.flight.status == .delayed { return "DELAYED" }
        if row.delayedBy != nil && !row.status.isTerminal { return "AT RISK" }
        return row.status.boardLabel
    }

    private var statusColor: Color {
        if row.isDelayed || row.delayedBy != nil { return Theme.delayed }
        switch row.status {
        case .scheduled, .boarding, .departed, .inFlight: return Theme.onTime
        default: return Theme.amber
        }
    }

    private var remarkText: String {
        row.remarks.joined(separator: " · ").uppercased()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if layout.wide {
                Text(row.flight.eta?.boardString ?? "--")
                    .frame(width: layout.eta, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.code).bold()
                if !layout.wide, let eta = row.flight.eta {
                    Text(eta.boardString).font(.caption.monospaced()).opacity(0.75)
                }
            }
            .frame(width: layout.flight, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.flight.title.uppercased())
                    .lineLimit(layout.wide ? 1 : 2)
                if !layout.wide, !remarkText.isEmpty {
                    Text(remarkText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.delayed)
                        .lineLimit(2)
                }
            }
            .frame(width: layout.title, alignment: .leading)

            if layout.wide {
                Text(row.operatorName.uppercased())
                    .lineLimit(1)
                    .frame(width: layout.airline, alignment: .leading)
            }

            Text(statusText)
                .bold()
                .foregroundStyle(statusColor)
                .frame(width: layout.status, alignment: .leading)

            if layout.wide {
                Text(remarkText)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.delayed)
                    .lineLimit(2)
                    .frame(width: layout.remarks, alignment: .leading)
            }
        }
        .font(.system(.body, design: .monospaced))
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.boardRow))
        .accessibilityElement(children: .combine)
    }
}
