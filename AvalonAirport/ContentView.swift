import SwiftUI
import AvalonCore

struct ContentView: View {
    @Environment(JourneyStore.self) private var store

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                TabView {
                    NavigationStack { JourneyMapView(snapshot: snapshot) }
                        .tabItem { Label("Journey Map", systemImage: "map") }
                    DataboardView(snapshot: snapshot)
                        .tabItem { Label("Databoard", systemImage: "airplane.departure") }
                    NavigationStack { AirportHubView(snapshot: snapshot) }
                        .tabItem { Label("Airport Hub", systemImage: "building.2") }
                }
                .task {
                    // Re-run the delay rules every minute while the app is open.
                    while !Task.isCancelled {
                        store.tick()
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No journey loaded", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(store.loadError ?? "")
                } actions: {
                    Button("Try again") { store.loadSample() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
