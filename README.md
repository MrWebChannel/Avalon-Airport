# Avalon Airport

The client owns the airport; providers operate flights. Domain model v0.3 — see `spec/domain-model.md` and the "Domain Model v0.3" area of the Avalon Airport Miro board.

```
spec/domain-model.md      single source of truth (v0.3)
AvalonCore/               Swift package: model, FlightTower, PluginEngine, GroundCrew, .avj manifests, tests, demo
App/                      SwiftUI app sources (iPhone and iPad)
AvalonApp/                the Xcode project (open Avalon.xcodeproj)
samples/                  sample files (anti-hustle.avj is still in the v0.2 format)
```

## 1. Test the engine in Terminal (2 minutes)

Needs Xcode 15.3 or later on the Mac. The first build downloads Yams (the one dependency, for YAML).

```bash
cd AvalonCore
swift run avalon-demo      # walks the Protected Estate journey end to end
swift test                 # tests covering the v0.3 rules
```

The demo shows, in order: a package approved into a journey, crew credentials, a filtered `.avj` snapshot, a `.avj` reply round trip, pre-flight checks holding a flight, a deliverable notice and the Captain filing it, a read-only folder grant, an AI agent blocked from granting itself access, the Delay plugin auto-delaying an overdue flight, delay accountability (reason and cause), the HCS content plugin running in JavaScriptCore, a grant expiring at landing, customs, arrival, and the hash-chained audit trail.

## 2. Run the app on the simulator or your iPhone/iPad

1. In Finder, open the repo folder → **AvalonApp** → double-click **Avalon.xcodeproj**.
2. Pick a simulator at the top of the Xcode window and press **Cmd-R**.
3. To run on your own iPhone or iPad: click the blue **Avalon** project → target **Avalon** → **Signing & Capabilities** → choose your Team.

The project is in the repo, so Xcode's **Integrate → Pull** brings every new build. New files in `App/` are picked up automatically.

### Trying it

- **Hub**: open Financial Freedom → Protected Estate → Approve and start journey.
- **Tower → Dashboard**: tap a flight → add a Pilot → "Send .avj" shares that provider's filtered snapshot. Pull down to run the plugins.
- **Hub → Provider mode** (the same app acts as the airline): import the snapshot, compose an update, "Create reply .avj".
- **Tower → Inbox**: import the reply; approve or reject. Blocked proposals show the plugin's reason.
- **Tower → Docs**: mark received, reviewed, then "File it". The next flight is held until you do.
- **Tower → Atlas / Settings**: completed journeys; connectors, grants, plugins, Ground Crew and the event log.
- **Journey**: the route as a map of stops. **Lounge**: private messages for tower members.

For a two-device test (you and your HCS partner): run the app on both, start the journey on yours, add your partner as crew, send them the `.avj`, they reply from their Provider tab.

## Version tracking and the build loop

The splash screen shows the build number on every launch (also at the top of the Tower tab). Every change arrives as a pull request that bumps it. See `PROCESS.md` for your steps and `AGENTS.md` for the rules every AI follows.

## MVP limits

One journey per device; one active flight at a time; one hub per journey. The Files connector cannot create provider share links, so a folder share asks you to share it in Dropbox/Box/Drive and the grant is still recorded and expires at landing. Package plugin signatures are SHA-256 checks standing in for real code signing.
