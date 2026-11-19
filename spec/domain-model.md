# Avalon Airport — Domain Model v0.2

Baseline: Copilot "Domain Model v0.1", revised with Claude on 2026-11-18.
This file is the single source of truth. Code, prompts and other AI tools read from it.

## Principles

1. **The client owns the airport.** Providers (Airlines) operate flights; they never own journeys.
2. **One writer.** Exactly one device, the active controller's, writes the journey. Everyone else sends updates to it.
3. **Status, not substance.** Avalon carries status, ETAs and references. Documents stay in the client's own storage (Dropbox, Box, Google Drive, iCloud).
4. **Nothing is overwritten.** Every change is an Event in a hash-chained, append-only log.
5. **Bottlenecks are always visible.** Every delay names who or what is holding the flight.
6. **Built for agents too.** A provider may be a person or an AI agent acting for the firm. Both use the same `.avj` files.

## MVP objects

Implemented now: Journey, Destination, Passenger, FlightTower, BoardingPass, Flight, Event, Update, Repository, Lounge, Atlas, JourneyPackage.
Defined but light: Airport, Airline, Hub, Route, Concierge.

### Journey

```yaml
journey:
  id: J-001
  title: Anti-Hustle Handbook
  description: Condense the rough draft into a companion handbook
  destinationId: D-001
  status: active            # active | paused | arrived | abandoned
  flightTowerId: FT-001
  passengerIds: [P-001, P-002]
  flightIds: [FL-101, FL-201, FL-301, FL-401]
  airportIds: []
  repositoryIds: [R-001]
  loungeId: LG-001
  createdAt: 2026-11-18T18:00:00-08:00
  updatedAt:
# completion % is COMPUTED from flight states, never stored
```

### Destination

```yaml
destination:
  id: D-001
  title: Handbook Manuscript Ready
  description:
  successCriteria: []
  status: active            # active | achieved
  achievedAt:
  image:                    # photo or generated image shown on arrival
```

### Passenger

A human on the journey. Roles here describe relationship only; control lives in FlightTower.

```yaml
passenger:
  id: P-001
  displayName:
  role: passenger           # passenger | observer | family | caregiver
  identityProvider: { type: apple }
  contact: { email:, phone: }   # never sent to providers unless the tower allows it
  boardingPassIds: []
```

### FlightTower

Governance for one journey. Replaces "owner." **Lives only on the active controller's device. Never written to a repository and never included in a package.**

```yaml
flightTower:
  id: FT-001
  journeyId: J-001
  controllerIds: [P-001]        # one or more co-owners
  activeControllerId: P-001     # the single device that writes
  boardingPassIds: [BP-001, BP-002]
  visibility:                   # per boarding pass, see BoardingPass.visibility
    default: restricted
  delayRules:
    graceHours: 0               # flight flips to delayed this long after ETA passes
    staleContactDays: 7         # "no contact from aircraft" after this many days without an update
  notificationPolicy: { enabled: true }
  repositoryPolicy: { mode: read-only }
```

### BoardingPass

Invitation and permission grant, issued by the tower. Delivered as a link or a flight ID plus key code.

```yaml
boardingPass:
  id: BP-002
  issuedBy: FT-001
  journeyId: J-001
  recipient:
    kind: airline               # passenger | airline
    id: AL-001
  permissions: [read, update]   # read | update | invite | observe
  visibility:                   # what this recipient's packages contain
    flights: [FL-101, FL-201, FL-301]   # or "all"
    showOtherAirlines: names-only       # none | names-only | status
    showPassengerContact: false
    lounge: false               # airlines can never see the Lounge
  keyCode:
  expiresAt:
  status: active                # active | revoked | expired
```

### Flight

A unit of responsibility and progress.

```yaml
flight:
  id: FL-201
  journeyId: J-001
  code: AH-201                  # shown on the flight board
  title: Triage draft
  airlineId: AL-001
  kind: flight                  # flight | customs (a checkpoint held by a passenger or authority)
  status: scheduled
  originalEta: 2026-11-25
  eta: 2026-11-25
  departedAt:
  landedAt:
  lastContactAt:
  dependsOn: [FL-101]           # flights that must land first
  waitingOn:                    # who or what is holding this flight right now; null when moving
    kind:                       # passenger | document | flight | airline | external
    ref:
    since:
  deliverables: []              # references into the Repository
```

**Flight states:** proposed, scheduled, boarding, departed, in-flight, holding, delayed, landed, closed, cancelled.

### Delay rules (run on the controller's device)

1. If `now > eta + graceHours` and the status is not landed, closed or cancelled, the flight becomes **delayed**. The tower records a `flight_delayed` event with actor `tower`.
2. If `now - lastContactAt > staleContactDays`, the board shows **"No contact from aircraft."**
3. **A provider cannot change the ETA of a delayed flight, or clear the delay, without:**
   - `reason`: free text, required
   - `cause`: one of passenger, document, flight, airline, external, required
   The update is rejected if either is missing.
4. The blame shown on the board follows `waitingOn`, not the airline by default. A flight waiting on the client shows the client as the bottleneck.
5. Every flight on a delayed flight's `dependsOn` chain shows **"Delayed by AH-xxx"**.

### Event

Immutable history. Never edited, never deleted.

```yaml
event:
  id: EV-0007
  journeyId: J-001
  flightId: FL-201
  actor: { kind: airline, id: AL-001, operatedBy: agent }   # operatedBy: human | agent | tower
  type: eta_changed
  reportedAt: 2026-11-26T09:12:00-08:00   # when the sender says it happened
  receivedAt: 2026-11-26T09:14:31-08:00   # when the controller's device logged it
  payload:
    previousEta: 2026-11-25
    newEta: 2026-11-28
    reason: Waiting on chapter files from client
    cause: passenger
  previousEventHash:
  eventHash:
  signature:
```

**Event types:** journey_created, flight_created, flight_assigned, flight_departed, eta_changed, flight_delayed, flight_landed, flight_cancelled, waiting_on_changed, boarding_pass_issued, boarding_pass_revoked, airline_joined, tower_transferred, destination_achieved.

### Update

A human-readable message. May carry a status change, which produces Events.

```yaml
update:
  id: UP-001
  journeyId: J-001
  flightId: FL-201
  author: { kind: airline, id: AL-001, operatedBy: agent }
  reportedAt:
  message: |
    Triage complete for chapters 1–6.
  statusChange:                 # optional
    status:
    eta:
    reason:                     # required when the flight is delayed
    cause:                      # required when the flight is delayed
```

### Repository

```yaml
repository:
  id: R-001
  provider: dropbox             # dropbox | box | gdrive | onedrive | icloud
  path: /Avalon/AntiHustle
  mode: read-only               # for providers
  ownerPassengerId: P-001
```

### Lounge

Private space for passengers. Airlines never see it.

```yaml
lounge:
  id: LG-001
  journeyId: J-001
  memberIds: [P-001, P-002]
  conciergeAccess: false        # client opts in
  conversations: []
  decisions: []                 # { id, title, rationale, approvedBy, at }
```

### Atlas and AtlasEntry

```yaml
atlasEntry:
  id: AE-001
  journeyId: J-001
  destinationId: D-001
  title:
  startedAt:
  completedAt:
  summary:
  repositoryIds: []
```

### JourneyPackage (`.avj`)

The file traded between devices by Messages, email or AirDrop. Each package is filtered by the recipient's BoardingPass.

```yaml
journeyPackage:
  schemaVersion: 0.2
  kind: snapshot                # snapshot (controller → others) | update (provider → controller)
  journeyId: J-001
  sender: { kind:, id: }
  recipient: { kind:, id: }
  sentAt:
  lastEventHash:                # lets the receiver detect gaps
  body: {}                      # snapshot: filtered journey; update: one Update
```

### Light objects (reserved)

```yaml
airline:  { id:, name:, type:, contact: { email:, phone: } }
airport:  { id:, name:, ownerAirlineId:, airlineIds: [] }
hub:      { id:, name:, airportIds: [] }
route:    { id:, sourceAirportId:, destinationAirportId:, relationshipType: }
concierge:{ id:, enabled: false, capabilities: [] }
```
