# Architecture

QuickBuzz is a host-authoritative, peer-to-peer buzzer game. One device is the **host**
(coordinator); every other device is a **player**. All game logic, including the session
lifecycle, runs in pure Swift packages; the app target contains SwiftUI views and small services.

## Module map

```
┌──────────────────────────── App (SwiftUI, iOS 18) ─────────────────────────────┐
│ Onboarding · Home · Lobby (Host/Join flows) · Settings · Shared                │
│ Services: Profile (name + PlayerID) · AppServices (transport factory) · DemoHub │
└───────────────┬───────────────────────────────────┬────────────────────────────┘
                │ makeTransport()                   │ HostSession / PlayerSession
     ┌──────────▼──────────┐              ┌─────────▼──────────────┐
     │ BuzzMultipeer       │              │ BuzzCore               │
     │ MultipeerTransport  │── conforms ─▶│ GameTransport          │
     │ PeerRegistry        │    to        │ HostSession  PlayerSession │
     │ DiscoveryInfo       │              │ HostEngine   PlayerEngine  │
     └─────────────────────┘              │ GameMessage/Codec · Models │
                                          │ LoopbackTransport/Network  │
     later: BuzzRelay (internet),         └────────────────────────────┘
            BuzzStore (StoreKit 2), BuzzCloud (Firebase)
```

| Module | Depends on | Responsibility |
|---|---|---|
| `BuzzCore` | Foundation, Observation, os | Models, wire protocol, `GameTransport` contract, host/player engines, **host/player sessions** (connection lifecycle), in-process loopback transport. No UIKit, no networking framework. |
| `BuzzMultipeer` | BuzzCore, MultipeerConnectivity | `MultipeerTransport`: discovery and messaging over Wi-Fi / peer-to-peer Wi-Fi / Bluetooth. |
| `App` | BuzzCore, BuzzMultipeer | Views and navigation; `Profile` persistence; `AppServices.makeTransport` (Multipeer, or loopback in demo mode); DEBUG demo mode. |

Decisions are recorded in `docs/adr/` (session layer and connection lifecycle: ADR 0004;
proposed Stage 4 ranking by clock-offset-corrected press timestamps: ADR 0005).

## Layers and data flow

```
 MC delegate queue            any task                 @MainActor
 ─────────────────            ────────                 ──────────
 MultipeerTransport ──events──▶ AsyncStream ──▶ HostSession / PlayerSession ──▶ HostEngine / PlayerEngine
   (stamps receivedAt)                                  │        ▲                     │ [Outbound]
                                                        │        └─────────────────────┘
                                transport.deliver(...) ◀┘
```

- **Engines** (`HostEngine`, `PlayerEngine`) are synchronous and pure with respect to I/O: every
  input returns the messages to send. Buzz arbitration is deterministic and unit-tested.
- **Sessions** (`HostSession`, `PlayerSession`) own one transport each, consume its `events`
  stream on a main-actor task, feed the engine, deliver its `[Outbound]`, and run the connection
  lifecycle (join, timeouts, reconnect, end). Views observe `session.phase` and `session.engine`.
- **Transports** only move bytes and report connectivity. `receivedAt` is stamped on the
  transport's callback thread before decoding, so main-thread load never distorts buzz deltas.

### Identity

- `PeerID` — local handle minted by a transport (`"<displayName>#<n>"`), unique per transport
  instance, never sent over the wire. Two players named "Sam" are two different `PeerID`s.
  `MultipeerTransport` keeps a `PeerRegistry` mapping `MCPeerID ⇄ PeerID`; the same `MCPeerID`
  seen again (e.g. after a browser restart) maps to the same `PeerID`.
- `PlayerID` — stable UUID generated once per install by `Profile` and sent in `hello`. The host
  keeps `PeerID ⇄ PlayerID` maps so a reconnecting player keeps their identity and score.

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
1. Ranking = order in which `buzz` messages **arrive at the host**. The session passes the
   transport's `receivedAt`; deltas are milliseconds after the winner. Device clocks are never compared.
2. A buzz whose `RoundID` ≠ current round is ignored (stale).
3. A buzz from a peer that never sent `hello` is ignored.
4. One buzz per player per round; duplicates are dropped.
5. A buzz while `idle` is "too early": the player is locked out for that round and told so.
6. `resolved` still accepts buzzes so the full ranking (2nd, 3rd…) is available.
7. `nextRound()` = `reset()` + `arm()`.
8. `end()` makes every later input a no-op.

A disconnected player is removed from `players`; their `scores` entry is kept, so a reconnect
(same `PlayerID`) restores them with their points.

## Player state (`PlayerEngine.status`)

```
 joining ──welcome──▶ waiting ──armed──▶ ready ──buzz()──▶ buzzed ──result(me)──▶ ranked(pos, Δms)
                        │                                     ▲
                        │ buzz() while waiting (sent to host) │ result(not me) keeps buzzed/ready
                        └──lockout──▶ lockedOut ──reset──▶ waiting
 kick ⇒ kicked, end / transport loss ⇒ ended  (terminal; later messages do not resurrect)
```

An early press is still **sent** to the host so that the lockout is recorded authoritatively.

## Session lifecycle

### `HostSession.phase`

```
 idle ──start()──▶ hosting ──end()──▶ ended
```

`end()` sends `end` to everyone, waits `flushDelay` (300 ms) so the frame leaves the device, then
stops the transport. `kick(_:)` sends `kick` to that player and a new roster to everyone;
MultipeerConnectivity cannot drop a single peer, so the kicked player disconnects itself.
The host needs no scene-phase handling: MultipeerConnectivity pauses advertising in the
background and resumes it by itself, and players reconnect on their own.

### `PlayerSession.phase`

```
 idle ─start()─▶ browsing ─join(host)─▶ connecting ─peerConnected─▶ joined ◀────────────┐
                    ▲                       │                          │ peerDisconnected  │ peerConnected
                    └── connectionFailed ───┘                          ▼                   │ (re-sends hello)
                        or connectTimeout (20 s)                  reconnecting ────────────┘
                                                                       │ reconnectTimeout (30 s)
 ended(reason) ◀── leave() · kick · host `end` · version mismatch ─────┴─▶ ended(.connectionLost)
```

- `joined` stops browsing (saves radio time). On a drop, `reconnecting` clears the (stale) host
  list, starts browsing again and asks the transport to connect right away; the transport holds the
  invitation until the host is found. It is re-requested whenever the host is re-found and after
  each failure (`retryDelay`, 1 s).
- On reconnect the player sends `hello` again; the host re-maps the peer and replies `welcome`
  with a full snapshot, so the screen catches up.
- The reconnect deadline only counts foreground time: `sceneDidEnterBackground()` pauses it and
  `sceneDidBecomeActive()` starts a fresh one and retries immediately. (`Task.sleep` keeps counting
  while the app is suspended, so without this a player who glanced at another app for 30 s would be
  sent home the moment they returned.)
- A player addresses everything to the host, whatever the engine's recipients say: the session
  mesh also links players to each other (see below). Frames and version errors from peers other
  than the host are ignored.
- Hosts advertising another protocol version show as not joinable (`DiscoveredHost.isCompatible`).
- End reasons: `left`, `hostEnded`, `kicked`, `connectionLost`, `incompatibleVersion` (only when the
  *host* speaks another version).

## Transport contract (`GameTransport`)

```swift
var localPeer: PeerID
var events: AsyncStream<TransportEvent>   // finishes after stop()
func startHosting(sessionName:)           // no-op while advertising
func startBrowsing() / stopBrowsing()     // no-op while browsing; restart after stop re-reports hosts
func connect(to:)                         // requires browsing; waits for discovery; result via
                                          // .peerConnected (immediate if already connected) / .failed(.connectionFailed)
func send(_:to:) / broadcast(_:) / stop() // stop is idempotent
```

`TransportEvent`: `hostFound`, `hostLost`, `peerConnected`, `peerDisconnected`,
`message(_, from:, receivedAt:)`, `failed(TransportError)`.
`TransportError`: `notConnected`, `peerUnknown`, `connectionFailed`, `incompatibleVersion(_, from:)`, `underlying`.

### `MultipeerTransport`

- Service type `quickbuzz` (`NSBonjourServices`: `_quickbuzz._tcp`, `_quickbuzz._udp`).
- Discovery info: `session` = session name (≤ 120 bytes), `v` = protocol version → `DiscoveredHost.isCompatible`.
- `MCPeerID.displayName` = the user's name, trimmed, ≤ 63 UTF-8 bytes, `"Player"` if empty.
- Encryption `.required`; data sent `.reliable` as `GameMessageCodec` JSON.
- Host auto-accepts invitations whose context carries the same protocol version, until
  `maxPlayers` (7: an `MCSession` holds 8 peers incl. host). Accepted-but-not-yet-connected
  invitations count against the cap, so simultaneous joins cannot overfill the session.
- Delegate callbacks arrive on MultipeerConnectivity's queues; state is guarded by one lock and
  events are yielded under it so their order matches the callbacks. No MC API is called with the
  lock held. After `stop()` no further events are emitted; callbacks from a replaced browser or
  advertiser are ignored.

MultipeerConnectivity behaviours the transport works around (each verified with real MC on macOS;
the first has a live regression test):

| Behaviour | Handling |
|---|---|
| An invitation sent through a browser that has not reported that peer is **silently dropped** (no `.connecting`, no `.notConnected`). | `connect(to:)` defers the invitation until the *current* browser finds the peer. Every pending invitation expires after 18 s (`invitationExpiry`, > the 15 s MC timeout, < the 20 s session timeout) with `.connectionFailed`. Repeat requests while pending are ignored. |
| Advertising and browsing pause in the background and **resume by themselves** in the foreground. | `startHosting`/`startBrowsing` never replace a running advertiser/browser (replacing one would trigger the dropped-invitation problem). |
| A session **links all members to each other**, not just to the host. | Players address the host explicitly (`PlayerSession.deliver`); the host's `broadcast` is the only fan-out. Version errors carry the sending peer. |
| A link can complete after the player gave up on it. | `connect(to:)` on an already-connected peer re-emits `.peerConnected`, so the next join succeeds instead of hanging. |

### `LoopbackTransport`

In-process routing through a `LoopbackNetwork` actor, used by tests, previews and demo mode.
`stop()` on a host emits `.hostLost` to everyone, then `.peerDisconnected` on each link.
`dropLink(between:and:)` simulates a transient drop for reconnect tests.

## App layer

| Piece | Role |
|---|---|
| `Profile` | `@Observable`; `PlayerID` (created once) and display name (trimmed, whitespace collapsed, ≤ 24 chars) in `UserDefaults` keys `profile.playerID` / `profile.name`. |
| `AppServices` | Injected via environment. `makeTransport(name)` returns a `MultipeerTransport`, or a loopback transport in demo mode. |
| `RootView` | `NameEntryView` until a name exists, then `HomeView`. |
| `HostFlowView` / `JoinFlowView` | Create the session in `.task`, end/leave on exit, keep the screen awake. `JoinFlowView` forwards `scenePhase` `.background`/`.active` to the session. Back button hidden: exit goes through End/Leave so the session is always closed. |
| `JoinBrowserView` rows | Hosts on another protocol version are shown disabled with "Needs the same QuickBuzz version". |
| `HostLobbyView` | Session name, live roster, swipe/context-menu kick, disabled "Start round" (Stage 3). |
| `JoinBrowserView` | Nearby games, per-row connecting spinner, failed-join notice, Local Network troubleshooting after 8 s. |
| `PlayerWaitingView` / `SessionEndedView` | Joined state with roster and reconnect banner; end reasons with a way home. |
| `DemoHub` | DEBUG demo mode (`-QBDemo YES`): loopback network, a joinable "Quiz Night (demo)" game, and simulated players that join the user's game. |

## Concurrency model

Swift 6 language mode, strict concurrency. Engines and sessions are `@MainActor @Observable`.
Transports are `Sendable` classes guarded by a lock (Multipeer, Loopback) or an actor
(`LoopbackNetwork`), and push events through an `AsyncStream` with a single consumer: the session.

## Persistence (later stages)

- Stage 3: in-memory scores only.
- Stage 6: `SessionStore` protocol with `LocalSessionStore` (SwiftData) and `CloudSessionStore` (Firestore).
