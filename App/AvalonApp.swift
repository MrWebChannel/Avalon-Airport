import SwiftUI
import AvalonCore

@main
struct AvalonApp: App {
    @State private var model = AppModel()
    @State private var jet = JetStream()
    @State private var addressBook = AddressBook()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(model)
                .environment(jet)
                .environment(addressBook)
                .preferredColorScheme(.dark)
        }
    }
}

/// Shows the splash (with the build number) over the app on every launch.
struct AppShell: View {
    @Environment(AppModel.self) private var model
    @Environment(JetStream.self) private var jet
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    /// Set when the person taps "Not now" on first-run setup. The Lounge still offers setup later.
    @AppStorage("avalon.onboardingSkipped") private var onboardingSkipped = false
    /// Launch argument used by the GitHub screenshot check to keep the splash on screen.
    private let holdSplash = ProcessInfo.processInfo.arguments.contains("-holdSplash")

    var body: some View {
        ZStack {
            RootView()
                .onOpenURL { url in model.importManifest(from: url) }
                // First-run setup after the splash, until this device has a Jet-Stream account.
                .fullScreenCover(isPresented: Binding(get: { !showSplash && !jet.isSignedIn && !onboardingSkipped && !holdSplash },
                                                      set: { _ in })) {
                    OnboardingView(onSkip: { onboardingSkipped = true })
                }
                .task { model.appOpened() }
                // The default update check: pulls Jet-Stream packages once a minute while the app is active.
                // The Lounge tab checks every few seconds on its own while it is open.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await jet.check()
                        do { try await Task.sleep(for: .seconds(JetStreamConfig.backgroundCheckSeconds)) } catch { return }
                    }
                }
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
                    .onTapGesture { hideSplash() }
                    // Counts only while the app is actually on screen and active. If the app goes
                    // inactive (launching under Xcode, a system prompt), the countdown starts over.
                    .task(id: scenePhase) {
                        guard scenePhase == .active, !holdSplash else { return }
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        hideSplash()
                    }
            }
        }
    }

    private func hideSplash() {
        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(JetStream.self) private var jet

    var body: some View {
        TabView {
            NavigationStack { HubView() }
                .tabItem { Label("Hub", systemImage: "building.2") }
            NavigationStack { FlightTowerView() }
                .tabItem { Label("Tower", systemImage: "antenna.radiowaves.left.and.right") }
                .badge(model.pending.count)
            NavigationStack { JourneyMapView() }
                .tabItem { Label("Journey", systemImage: "map") }
            NavigationStack { LoungeView() }
                .tabItem { Label("Lounge", systemImage: "cup.and.saucer") }
                .badge(jet.unread)
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
                               description: Text("Open the Hub, choose a journey template, and approve it to start."))
    }
}

let shortDate: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()
