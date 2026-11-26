# Rules for any AI working on Avalon Airport

These rules apply to Claude, ChatGPT, Gemini or any other agent. `CLAUDE.md` and `GEMINI.md` point here.

## The loop (one build = one pull request)

1. **Start from the latest `main`.** Never commit to `main` directly.
2. **Make a branch** named `<agent>/build-<N>`, for example `claude/build-7`, `chatgpt/build-8`, `gemini/build-9`. N is the next build number (see step 3).
3. **Bump the build number** in `AvalonCore/Sources/AvalonCore/Version.swift`: `build` goes up by 1. Change `core` when the engine changes and `schema` only when the data model changes. The splash screen shows these, so the owner can see which build is running.
4. **Add an entry at the top of `CHANGELOG.md`**: build number, date, agent, what changed, how to test it.
5. **Keep `spec/domain-model.md` in step with the code.** If the Miro board's domain model changed, update the spec in the same pull request.
6. **Run the checks** if you can: `cd AvalonCore && swift build && swift test`. If you cannot compile, say so in the pull request. GitHub runs the same checks on every pull request (`.github/workflows/test.yml`).
7. **Open a pull request** into `main` using the template. Say what changed, how to test it, and anything you could not verify.
8. **Wait.** The owner reviews and merges. Only the owner merges into `main`.

If the checks fail, fix them on the same branch; do not open a new pull request.

**App files:** `AvalonApp/Avalon.xcodeproj` syncs the `App/` folder automatically, so new `.swift` files there are included without touching the project. Do not edit `project.pbxproj` unless the change needs a new setting, and say so in the pull request.

**Navigation (bottom tabs):** Hub, Tower, Journey, Lounge. The Tower holds Dashboard, Inbox, Documents, Atlas and Settings.

## Design rules (from the domain model)

- The client owns the airport. Only the FlightTower persists Journey state; everyone else proposes.
- Humans retain authority. Agents provide recommendations. A human reviews every document.
- Plugins return Findings only. Run order: security, analytics, contentBehavior. Package plugins never get native bridges.
- No Airline, Pilot or agent gets write access to the Captain's storage.
- Avalon carries status, not substance. Never put documents or personal contact details in a `.avj` file. A Hub, Airport or Airline business card (`BusinessContact`) is allowed; Passenger and member contact details are not. Photos travel only as https links.
- Keep third-party dependencies to a minimum. The only one today is Yams (YAML).

## Layout

```
spec/domain-model.md        source of truth for the model
AvalonCore/                 Swift package: engine, tests, demo (swift run avalon-demo)
App/                        SwiftUI app sources
AvalonApp/                  Xcode project (open Avalon.xcodeproj)
CHANGELOG.md                one entry per build
PROCESS.md                  the owner's steps (plain language)
```
