import SwiftUI

@main
struct AvalonAirportApp: App {
    @State private var store = JourneyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
