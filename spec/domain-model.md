# Avalon Airport — Domain Model v0.3

Baseline: v0.2 (2026-11-18), revised with Claude on 2026-11-22 to match the "Domain Model v0.3" area of the Miro board.
This file is the single source of truth. Code, prompts and other AI tools read from it. Code lives in `AvalonCore/`.

## Principles

1. **The client owns the airport.** Airlines (service providers) operate flights; they never own journeys.
2. **Only the FlightTower persists Journey state.** It lives on the active controller's device. Everyone else proposes.
3. **Humans retain authority. Agents provide recommendations.** Captains and Co-Captains commit; crew, plugins and the Concierge submit Proposals.
4. **A human reviews every document.** Providers send deliverables to the Captain through their own channel. Avalon carries only the notice. No Airline, Pilot or agent gets write access to the Captain's storage.
5. **Nothing is overwritten.** Every change is an Event in a hash-chained, append-only log.
6. **Bottlenecks are always visible.** Every delay names who or what is holding the flight, including the Captain.
7. **Built for agents too.** A crew member may be a person or an AI agent acting for its Airline. Both only propose.

## Hierarchy

Hub (subject domain) → Airport (trusted ecosystem) → Airline (service provider, the firm) → Flight (reusable service offering) → BoardingPass (one instance of a Flight inside a Journey).

HCS hubs: Business Accelerators, Human Transformation, Society and Technology, Organizational Navigators. A PSF hub has the same structure (e.g. Financial Freedom, Physical Health, Home Repair).

## The pipeline

Plugin → Finding → Proposal → Captain approves (or an auto-approve rule) → GroundCrew runs the action → ActionRecord → Event.

## Roles

| Role | Lives on | Can propose | Can commit / write |
|---|---|---|---|
| Captain | FlightTower | Yes | Yes |
| Co-Captain | FlightTower | Yes | Yes |
| Passenger | FlightTower | No | No |
| Observer | FlightTower | No | No |
| Pilot | BoardingPass (crew) | Yes | No |
| Co-Pilot | BoardingPass (crew) | Yes | No |
| Crew | BoardingPass (crew) | Yes (limited) | No |

Crew `kind`: human or agent.

## Objects (see `AvalonCore/Sources/AvalonCore/Models.swift` for every field)

**Product (sellable):** HubPackage (content refs, JourneyTemplates, Flights, plugins, Airports, Airlines, customizedFor), JourneyTemplate (ordered steps: an Airline's Flight or a Customs step), Flight (template), Plugin (PluginDescriptor).

**Journey:** Journey, Destination, BoardingPass (kind flight or customs; status, ETAs, waitingOn, dependsOn, crew, waypoints, deliverables, pluginIds), Waypoint, Deliverable (sent → received → reviewed → filed), Repository (a folder in the Captain's storage, via a Connector), Lounge (members only), AtlasEntry (reserved).

**Governance (device only):** FlightTower (controllers, autoApproveRules, hosts PluginEngine and GroundCrew), Credential (journey access: permissions read/propose/invite/observe, scope, keyCode, expiry), StorageGrant (read-only folder access tied to a Credential, expires at landing), Connector (storage or calendar; MVP uses the iOS Files app and the device calendar), Proposal (replaces Update), ActionRequest.

**Log:** Event (immutable, hash-chained), StatusChange, ActionRecord, Finding, Manifest (`.avj`, renamed from JourneyPackage).

**Transport:** JetStreamPackage (one small YAML package carried by Jet-Stream; kind `lounge` in build 5).

## Plugins

- One **PluginEngine** inside the FlightTower. It verifies package plugin signatures, loads the plugins of the boarding pass being evaluated (plugins ride on one Flight), runs them on triggers (onProposal, onEvent, onAppOpen, onSchedule) and collects Findings.
- **PluginType** and run order: security → analytics → contentBehavior.
  - security: block, warning, info
  - analytics: warning, info, may raise a Proposal
  - contentBehavior: info and recommendation only
- Once a security plugin blocks, later types do not run.
- **Tiers:** default (ships in the app, always wins) and package (arrives in a HubPackage). A package plugin can add rules but never replace or weaken a default.
- **Defaults:** Security (permissions, credentials, access control, delay accountability), Flight checks (pre-flight, in-flight, landing; security type because it holds flights), Delay rules (analytics; settings graceHours, staleContactDays).
- Package plugins are YAML settings plus a JavaScript `evaluate(context)` function run in JavaScriptCore with nothing bridged in. They return Findings only.

## Delay rules (default Delay plugin)

1. Past ETA + graceHours and not landed, closed or cancelled: the plugin raises a Proposal to mark the flight delayed; the `delayRule` auto-approves it.
2. No update for staleContactDays: "No contact from aircraft."
3. Changing the ETA of a delayed flight, or clearing the delay, needs a reason and a cause (enforced by the Security plugin, which may block).
4. Blame follows waitingOn, not the airline by default.
5. Every flight downstream on the dependsOn chain shows "Delayed by XX-nnn".

## Flight checks (default plugin)

- Pre-flight: previous flights landed, their deliverables filed by the Captain, a Pilot assigned, an ETA set.
- In-flight: overdue waypoints.
- Landing: deliverable sent; Captain review pending.

## Handoff rule

A deliverable that changes firms or needs the Captain's approval is a new BoardingPass or a Customs step. Progress inside one firm is a Waypoint. When a deliverable is sent, the flights that depend on it wait on the Captain until she files it.

## Storage and privacy

- StorageGrants are read-only, folder-scoped, created only by GroundCrew after approval, expire when their boarding pass lands, and every grant and revocation is an Event.
- Agents the Captain points at her own storage (Dash or others) are her choice, outside Avalon.
- Snapshots sent to providers never include the Lounge, member contacts, credentials or grants. Other airlines' flights show code, status and ETA only, never titles.

## Actions (GroundCrew catalog)

notify, addCalendarEvent, updateEta, remindCustoms, verifyDeliverable, shareFolderLink, revokeFolderLink, issueCredential, revokeCredential. Only approved actions run, re-running one is harmless, and access actions can only come from a Captain or Co-Captain.

## Manifest (`.avj`)

YAML file traded by Messages, email or AirDrop. `snapshot` goes from the tower to a credential holder, filtered by that credential. `proposal` comes back carrying the credential id and key code; the tower takes identity from the credential, not from the file.

## Jet-Stream (transport)

Jet-Stream is a Supabase project that carries YAML packages between Avalon apps. It is a plain transport, not a routing or permission layer.

- Every account is just a user. There are no crew or client roles on the server.
- The sending app decides who receives a package (from the boarding pass, or the people added to the Lounge) and sends one copy per recipient in a single request.
- The server guarantees only the envelope: the sender cannot be faked, only the addressee (and sender) can read a package, the YAML cannot change after sending, and the server records a SHA-256 of each package.
- The `messages` table is the queue: a package stays `sent` until the recipient's app marks it `applied`. The sender sees `applied` as delivered.
- Every app runs an update check once a minute while open; the Lounge checks every few seconds while it is on screen. Realtime and push are not used.
- Packages of a kind an app does not know are left `sent` for a newer build.
- Accounts are email and password; the session is kept in the device Keychain. People are added to the Lounge by exact email (no browsable directory).
- Lounge messages are stored on each device; airlines never receive them. They are not end-to-end encrypted yet; add that before health, legal or financial journeys use the Lounge.
- Enterprise may later move roles, fan-out (one package to many) and persistence to the server.

## MVP limits

- One active BoardingPass per Journey at a time (dependsOn kept for later parallel flights).
- One Hub per Journey; mixing Hubs comes later.
- Folder shares: the iOS Files connector cannot create provider share links, so the Captain is asked to share the folder in her storage app; the grant is still recorded, expires and is logged.
