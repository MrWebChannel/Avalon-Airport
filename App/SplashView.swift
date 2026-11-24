import SwiftUI
import AvalonCore

/// Shown every time the app loads so the running version is always visible.
/// App version and build come from the Xcode target (General > Identity); engine and schema come from AvalonCore.
struct SplashView: View {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
    /// One line for the splash and the Tower tab, e.g. "v1.0 (7) · core 0.3.1 · schema 0.3".
    static var versionLine: String {
        "v\(appVersion) (\(buildNumber)) · core \(AvalonVersion.core) · schema \(AvalonVersion.schema)"
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(.blue)
                Text("Avalon Airport")
                    .font(.largeTitle.bold())
                Text("The client owns the airport")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    Text("Version \(Self.appVersion)  ·  Build \(Self.buildNumber)")
                        .font(.title3.monospacedDigit().bold())
                    Text("Core \(AvalonVersion.core)  ·  Schema \(AvalonVersion.schema)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
            }
        }
    }
}
