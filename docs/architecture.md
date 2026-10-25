# Architecture

QuickBuzz is a host-authoritative, peer-to-peer buzzer game. One device is the **host**
(coordinator); every other device is a **player**. All game logic runs in pure Swift packages;
the app target contains SwiftUI views only.

## Module map

```
┌──────────────────────── App (SwiftUI, iOS 18) ────────────────────────┐
│  Onboarding · Home · Lobby · Round · Settings    (views + session glue) │
└───────────────┬───────────────────────────────┬────────────────────────┘
                │                               │
     ┌──────────▼──────────┐          ┌─────────▼──────────┐
     │ BuzzMultipeer       │          │ BuzzCore           │
     │ MultipeerTransport  │─ conforms│ GameTransport      │
     │ (MCSession etc.)    │   to ───▶│ LoopbackTransport  │
     └─────────────────────┘          │ GameMessage/Codec  │
                                      │ HostEngine         │
     later: BuzzRelay (internet),     │ PlayerEngine       │
            BuzzStore (StoreKit 2),   │ Models             │
            BuzzCloud (Firebase)      └────────────────────┘
```

| Module | Depends on | Responsibility |
|---|---|---|
| `BuzzCore` | Foundation, Observation | Models, wire protocol, `GameTransport` contract, host/player state machines, in-process loopback transport. No UIKit, no networking. |
| `BuzzMultipeer` | BuzzCore, MultipeerConnectivity | `MultipeerTransport`: discovery and messaging over Wi-Fi / peer-to-peer Wi-Fi / Bluetooth. Stage 2. |
| `App` | BuzzCore, BuzzMultipeer | Views, navigation, persistence of display name / `PlayerID`, the session object that pumps transport events into an engine and delivers the engine's `[Outbound]`. |

Decisions are recorded in `docs/adr/`.

## Data flow

```
 transport.events ──▶ Session (app) ──▶ engine.receive(message, from:, at:) ──▶ [Outbound]
                                                                                │
 transport.deliver(outbounds)  ◀────────────────────────────────────────────────┘
```

Engines are **synchronous and pure with respect to I/O**: every input (transport event or user
action) returns the list of messages to send. The session layer is the only async code and is
trivial. This is what makes buzz arbitration deterministic and unit-testable
(`Packages/BuzzCore/Tests/BuzzCoreTests/HostEngineTests.swift`).

### Identity

- `PeerID` — transport-level identity of a connected device (e.g. `MCPeerID.displayName`).
- `PlayerID` — stable UUID generated once per install and persisted by the app. Sent in `hello`.
  The host keeps `PeerID ⇄ PlayerID` maps so a player who reconnects keeps their identity.

## Host state machine (`HostEngine`)

```
                     arm()                    first accepted buzz
   ┌──────┐ ───────────────────▶ ┌───────┐ ─────────────────────▶ ┌──────────┐
   │ idle │                      │ armed │                        │ resolved │
   └──────┘ ◀─────────────────── └───────┘ ◀──────────────────────└──────────┘
      ▲          reset()  (new RoundID, clears ranking + lockouts)
      │
      └── buzz while idle ⇒ player added to round.lockedOut, host sends `lockout` to that peer
```

Rules (all enforced in `HostEngine.handleBuzz`):
1. Ranking = order in which `buzz` messages **arrive at the host**. The caller passes
   `ContinuousClock.Instant` of arrival; deltas are milliseconds after the winner. Device clocks
   are never compared.
2. A buzz whose `RoundID` ≠ current round is ignored (stale).
3. A buzz from a peer that never sent `hello` is ignored.
4. One buzz per player per round; duplicates are dropped.
5. A buzz while `idle` is "too early": the player is locked out for that round and told so.
6. `resolved` still accepts buzzes so the full ranking (2nd, 3rd…) is available.
7. `nextRound()` = `reset()` + `arm()`.
8. `end()` makes every later input a no-op.

`HostEngine` is `@MainActor @Observable`; views read `players`, `round`, `scores` directly.

## Player state (`PlayerEngine.status`)

```
 joining ──welcome──▶ waiting ──armed──▶ ready ──buzz()──▶ buzzed ──result(me)──▶ ranked(pos, Δms)
                        │                                     ▲
                        │ buzz() while waiting (sent to host) │ result(not me) keeps buzzed/ready
                        └──lockout──▶ lockedOut ──reset──▶ waiting
 kick ⇒ kicked, end / transport loss ⇒ ended  (terminal; later messages do not resurrect)
```

An early press is still **sent** to the host so that the lockout is recorded authoritatively.

## Transport contract (`GameTransport`)

```swift
var localPeer: PeerID
var events: AsyncStream<TransportEvent>     // hostFound/hostLost/peerConnected/peerDisconnected/message/failed
func startHosting(sessionName:) / startBrowsing() / connect(to:) / send(_:to:) / broadcast(_:) / stop()
```

Implementations:
- `LoopbackTransport` + `LoopbackNetwork` actor — in-process routing for tests and SwiftUI previews.
  `stop()` on a host emits `.hostLost` to everyone, then `.peerDisconnected` on each link.
- `MultipeerTransport` — Stage 2. Service type `quickbuzz`; discovery info carries the session name.
- Relay transport — Stage 7 (internet rooms).

## Concurrency model

Swift 6 language mode, strict concurrency. Engines are `@MainActor`. Transports are `Sendable`
and push events through an `AsyncStream` (single consumer: the session object). Loopback uses an
actor for the shared network and a lock for the tiny per-transport flag.

## Persistence (later stages)

- Stage 3: in-memory scores only.
- Stage 6: `SessionStore` protocol with `LocalSessionStore` (SwiftData) and `CloudSessionStore` (Firestore).
