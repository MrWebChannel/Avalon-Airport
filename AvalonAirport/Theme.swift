import SwiftUI
import AvalonCore

enum Theme {
    static let boardBackground = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let boardRow = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.0)
    static let onTime = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let delayed = Color(red: 1.0, green: 0.30, blue: 0.27)
    static let rail = Color.gray.opacity(0.35)
}

extension FlightStatus {
    var tint: Color {
        switch self {
        case .proposed: return .gray
        case .scheduled: return Theme.onTime
        case .boarding: return Theme.amber
        case .departed, .inFlight: return .cyan
        case .holding: return .orange
        case .delayed: return Theme.delayed
        case .landed, .closed: return .blue
        case .cancelled: return .secondary
        }
    }
}

extension Flight {
    var symbolName: String {
        if kind == .customs { return "checkmark.shield" }
        switch status {
        case .landed, .closed: return "airplane.arrival"
        case .departed, .inFlight: return "airplane"
        default: return "airplane.departure"
        }
    }
}

extension View {
    /// Lets the Siri Remote move focus onto (and scroll to) otherwise passive rows.
    @ViewBuilder
    func tvFocusable() -> some View {
        #if os(tvOS)
        self.focusable()
        #else
        self
        #endif
    }
}
