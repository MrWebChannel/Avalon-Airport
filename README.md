# Avalon Airport

SwiftUI app for iPhone, iPad and Apple TV. Apple frameworks plus [Yams](https://github.com/jpsim/Yams) only.
The domain model is defined in [`spec/domain-model.md`](spec/domain-model.md).

## Layout

| Path | What |
| --- | --- |
| `AvalonCore/` | Swift package: domain models, `.avj` loading/saving (Yams), event log, delay rule engine |
| `AvalonAirport/` | The app: Journey Map, Databoard, Airport Hub (Flight Tower, Lounge, Atlas), update composer |
| `samples/anti-hustle.avj` | Starting journey, bundled into the app |
| `AvalonAirport.xcodeproj` | One app target, built for iOS and tvOS |

## Build

Requires Xcode 16 or later (iOS 17 / tvOS 17 deployment targets).

1. Open `AvalonAirport.xcodeproj`. Xcode fetches Yams automatically.
2. Pick an iPhone, iPad or Apple TV simulator and run the `AvalonAirport` scheme.

To run the engine tests:

```bash
cd AvalonCore && swift test
```

## What works

- **Flight Tower** (Airport Hub): delay rules, simulated clock, **Read journey YAML** (the live `.avj`),
  **Append YAML** (paste or open an update package; the delay rules accept or reject it), tower YAML, share `journey.avj` (iPhone/iPad).
- **Lounge**: private notes, decisions, Concierge access toggle.
- **Atlas**: mark the destination achieved, which logs `destination_achieved` and records the trip.
- Everything is saved on the device (`Application Support/Journeys/journey.avj` and `tower.yaml`; caches on Apple TV)
  and reopened on launch. **Reset to sample journey** in Flight Tower starts over.

## Trying the delay rules

In **Airport Hub → Flight Tower**, tap **Advance 1 day** until AH-101 flips to delayed. The Databoard then shows
AH-201 to AH-401 as *Delayed by AH-101*. Then open **Append YAML**, change `eta:` in the template and tap
**Append to journey**: it is rejected until both `reason:` and `cause:` are filled in.
