# Changelog

One entry per build, newest first. The build number matches `AvalonVersion.build` and the splash screen.

## Build 1 · 2026-11-23 · Claude

- Domain model v0.3: AvalonCore engine (FlightTower, PluginEngine, GroundCrew, default plugins Security, Flight checks and Delay), `.avj` manifests, sample hubs and the Protected Estate package.
- 23 tests and the `avalon-demo` walk-through.
- SwiftUI app: Board, Inbox, Documents, Packages, Tower, Provider tabs.
- Splash screen with version, build, core and schema.
- Repeatable process: `AGENTS.md`, `PROCESS.md`, pull request template, automatic checks on GitHub.
- **Test:** `cd AvalonCore && swift run avalon-demo && swift test`. In the app, start Protected Estate from Packages.
- **Not verified:** written without a Swift compiler; the GitHub check is the first real compile.
