# Avalon Airport

SwiftUI app for iPhone, iPad and Apple TV. Apple frameworks plus [Yams](https://github.com/jpsim/Yams) only.
The domain model is defined in [`spec/domain-model.md`](spec/domain-model.md).

## Layout

| Path | What |
| --- | --- |
| `AvalonCore/` | Swift package: domain models, `.avj` loading/saving (Yams), event log, delay rule engine |
| `AvalonAirport/` | The app: Journey Map, Databoard, Airport Hub, update composer |
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

## Trying the delay rules

The sample's first ETA is 21 Nov 2026. In **Airport Hub → Flight Tower**, tap **Advance 1 day** until AH-101
flips to delayed. The Databoard then shows AH-201 to AH-401 as *Delayed by AH-101*. Then use
**Post an update** to move AH-101's ETA. The update is rejected unless it has both a reason and a cause.
