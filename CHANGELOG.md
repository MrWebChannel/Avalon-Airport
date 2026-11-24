# Changelog

One entry per build, newest first. The build number matches `AvalonVersion.build` and the splash screen.

## Build 3 · 2026-11-23 · Claude

- The Xcode project now lives in the repo: `AvalonApp/Avalon.xcodeproj`. Open it instead of creating one by hand. It syncs the `App/` folder automatically, links AvalonCore, and includes the calendar permission and the `.avj` file type.
- Xcode's Integrate → Pull now works, because the project is inside the repo.
- GitHub builds this exact Xcode project for iOS on every pull request.
- **Test:** open `AvalonApp/Avalon.xcodeproj`, Cmd-R, splash says Build 3.

## Build 2 · 2026-11-23 · Claude

- Splash screen: fixed colors (white on dark blue) so the text is always visible, and the build number is now the largest line.
- Bottom navigation is now **Hub, Tower, Journey, Lounge**.
  - Hub: the Airport Hub (hubs and packages) plus Provider mode.
  - Tower: Dashboard (flight board), Inbox, Documents, Atlas and Settings, switched at the top.
  - Journey: the journey map, each flight as a stop on the way to the destination.
  - Lounge: private conversation for tower members; airlines never see it.
- Engine (core 0.3.2): Atlas entries recorded at arrival, Lounge posting for members only. 25 tests.
- **Test:** pull, run, check the splash says Build 2; open each tab.
- **No new files in App/.**

## Build 1 · 2026-11-23 · Claude

- Domain model v0.3: AvalonCore engine (FlightTower, PluginEngine, GroundCrew, default plugins Security, Flight checks and Delay), `.avj` manifests, sample hubs and the Protected Estate package.
- 23 tests and the `avalon-demo` walk-through.
- SwiftUI app: Board, Inbox, Documents, Packages, Tower, Provider tabs.
- Splash screen with version, build, core and schema.
- Repeatable process: `AGENTS.md`, `PROCESS.md`, pull request template, automatic checks on GitHub.
- **Test:** `cd AvalonCore && swift run avalon-demo && swift test`. In the app, start Protected Estate from Packages.
- **Not verified:** written without a Swift compiler; the GitHub check is the first real compile.
