import Foundation

/// Version numbers shown on the splash screen. Bump `core` with every engine change.
public enum AvalonVersion {
    /// Build number. Every pull request bumps it by 1 (see AGENTS.md). Shown on the splash screen.
    public static let build = 3
    /// AvalonCore engine version.
    public static let core = "0.3.2"
    /// Domain model / .avj schema version (matches spec/domain-model.md).
    public static let schema = "0.3"
}
