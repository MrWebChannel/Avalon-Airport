import SwiftUI
import AvalonCore

/// Shown every time the app loads so the running version is always visible.
/// App version comes from the Xcode target; build, engine and schema come from AvalonCore/Version.swift.
/// Colors are fixed (not light/dark adaptive) so the text is always readable.
struct SplashView: View {
    static let night = Color(red: 0.05, green: 0.14, blue: 0.32)

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    /// Comes from AvalonCore so every pull request's build number shows without touching Xcode settings.
    static var buildNumber: String { String(AvalonVersion.build) }
    /// One line for the splash and the Tower settings, e.g. "v1.0 · build 2 · core 0.3.2 · schema 0.3".
    static var versionLine: String {
        "v\(appVersion) · build \(buildNumber) · core \(AvalonVersion.core) · schema \(AvalonVersion.schema)"
    }

    var body: some View {
        ZStack {
            Self.night.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Color.white)
                Text("Avalon Airport")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.white)
                Text("The client owns the airport")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.75))
                VStack(spacing: 6) {
                    Text("Build \(Self.buildNumber)")
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.white)
                    Text("Version \(Self.appVersion)  ·  Core \(AvalonVersion.core)  ·  Schema \(AvalonVersion.schema)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .padding(.top, 24)
            }
            .padding()
        }
        .environment(\.colorScheme, .dark)
    }
}
