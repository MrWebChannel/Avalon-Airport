# Changelog

One entry per build, newest first. The build number matches `AvalonVersion.build` and the splash screen.

## Build 5 · 2026-11-25 · Claude

- **Jet-Stream (Supabase) is live.** Avalon apps now exchange YAML packages through the Avalon-Airport Supabase project. Plain HTTPS, no new dependency; the sign-in session is kept in the Keychain.
- **Lounge is a real chat.** Create a Jet-Stream account (or sign in) in the Lounge tab, add people by email with the People button, and messages go to each of them. Bubbles show sent, then delivered once the other app has picked the message up. People who message you are added automatically so you can reply.
- **Update checks:** every 4 seconds while the Lounge is open, once a minute elsewhere while the app is active. New Lounge messages show as a badge on the Lounge tab.
- **App icon:** control tower with a plane on a dotted flight path (navy, matches the splash). Needed one new build setting, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- Engine (core 0.4.0): `JetStreamPackage`, the YAML format Jet-Stream carries. 2 new tests.
- The old on-device Lounge list is no longer shown; messages are now kept per device by Jet-Stream.
- **Before testing:** in the Supabase dashboard, Authentication → Sign In / Providers → Email, turn off **Confirm email** for the pilot. Otherwise each new account must click a confirmation email first.
- **Test:** splash shows **Build 5** and the home screen shows the tower icon. Run two simulators (or a simulator and your phone), create an account in each Lounge, add each other by email, and chat. Each message should arrive within about 4 seconds and change from sent to delivered.

## Build 4 · 2026-11-23 · Claude

- Dark mode throughout, including system screens.
- Launch screen is dark navy (no white flash) and leads straight into the splash.
- Splash fixed: the 3-second countdown only runs while the app is on screen and active, so a slow launch under Xcode no longer uses it up. Tap to skip.
- The notification permission prompt now appears when you start a journey, not over the splash.
- GitHub launches the app in an iPhone simulator on every pull request and records screenshots of the launch.
- **Test:** the splash should show **Build 4** for about 3 seconds after the navy launch screen.

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
