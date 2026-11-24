import SwiftUI
import AvalonCore

@main
struct AvalonApp: App {
    @State private var model = AppModel()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(model)
                    .onOpenURL { url in model.importManifest(from: url) }
                    .task { model.appOpened() }
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .onTapGesture { withAnimation { showSplash = false } }
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            NavigationStack { FlightBoardView() }
                .tabItem { Label("Board", systemImage: "airplane.departure") }
            NavigationStack { InboxView() }
                .tabItem { Label("Inbox", systemImage: "tray.full") }
                .badge(model.pending.count)
            NavigationStack { DeliverablesView() }
                .tabItem { Label("Documents", systemImage: "doc.text") }
            NavigationStack { PackagesView() }
                .tabItem { Label("Packages", systemImage: "shippingbox") }
            NavigationStack { TowerView() }
                .tabItem { Label("Tower", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { ProviderView() }
                .tabItem { Label("Provider", systemImage: "briefcase") }
        }
        .alert("Avalon", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .overlay(alignment: .bottom) {
            if let info = model.infoMessage {
                Text(info)
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 60)
                    .onTapGesture { model.infoMessage = nil }
                    .task(id: info) {
                        try? await Task.sleep(for: .seconds(3))
                        if model.infoMessage == info { model.infoMessage = nil }
                    }
            }
        }
    }
}

// MARK: - Shared bits

extension FlightStatus {
    var color: Color {
        switch self {
        case .delayed, .holding: return .red
        case .departed, .inFlight, .boarding: return .blue
        case .landed, .closed: return .green
        case .cancelled: return .gray
        case .proposed, .scheduled: return .secondary
        }
    }
}

extension FindingSeverity {
    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .block: return "hand.raised"
        }
    }
    var color: Color {
        switch self {
        case .info: return .secondary
        case .warning: return .orange
        case .block: return .red
        }
    }
}

struct NoJourneyView: View {
    var body: some View {
        ContentUnavailableView("No journey yet", systemImage: "airplane",
                               description: Text("Open Packages, choose a journey template, and approve it to start."))
    }
}

let shortDate: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()
