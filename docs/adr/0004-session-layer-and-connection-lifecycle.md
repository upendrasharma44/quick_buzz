# ADR 0004: Session layer in BuzzCore; transport-stamped arrival times; reconnect policy

- Status: Accepted
- Date: 2026-10-25

## Context

Stage 2 connects the pure engines to a real transport. Something has to consume transport events,
feed the engines, deliver their replies, and handle the messy parts of a radio link: joining,
timeouts, the app being backgrounded, Wi-Fi blips, the host disappearing. Three questions came up:

1. Where does that code live — the app target or a package?
2. Where is a buzz's arrival time measured?
3. What happens when a player's connection drops?

## Decision

1. **`HostSession` and `PlayerSession` live in `BuzzCore`**, depend only on `GameTransport`, and are
   `@MainActor @Observable` so views bind to them directly. The app only creates them and forwards
   scene-phase changes.
2. **The transport stamps `receivedAt`** (`ContinuousClock.Instant`) in its receive callback,
   before decoding and before hopping to the main actor. `TransportEvent.message` carries it and
   `HostSession` passes it to `HostEngine.receive(_:from:at:)`.
3. **Players reconnect automatically** for 30 s of *foreground* time after an unexpected drop:
   browse again, ask the transport to connect (it waits until the host is re-found; retry every 1 s
   on failure), re-send `hello`, and let the host's `welcome` snapshot resynchronise the screen.
   The deadline pauses while the app is in the background and restarts when it is active again.
   After it expires the game ends with "Lost connection to the host". The host does nothing on
   scene changes: MultipeerConnectivity resumes advertising by itself.
4. **Players talk to the host only.** MultipeerConnectivity links every session member to every
   other, so player sessions address the host explicitly and ignore frames from other peers. The
   host rejects invitations from other protocol versions (invitation context), and players grey
   out such hosts (discovery info `v`).

## Alternatives considered

- **Sessions in the app target** — the original Stage 0 sketch. Rejected: the lifecycle logic is
  the most bug-prone part of Stage 2 and would only be testable through the simulator. In
  `BuzzCore` it runs in under a second against `LoopbackTransport` and a scripted transport
  (22 session tests) and against real MultipeerConnectivity in the opt-in live tests.
- **Stamp arrival on the main actor** — simpler, but any main-thread work (SwiftUI layout, an
  animation) between the callback and the engine would inflate later buzzes' deltas. Ordering would
  survive (the stream is FIFO); the milliseconds shown would not.
- **No auto-reconnect; send players home on any drop** — simplest, but MultipeerConnectivity drops
  sessions whenever an app is backgrounded even briefly, so a player checking a message would be
  thrown out mid-game.
- **Host-driven reconnect** — MultipeerConnectivity lets either side invite, but having the host
  invite every lost player complicates the star topology and invitation handling for no gain.

## Review findings folded in (2026-10-25)

An independent review with experiments against real MultipeerConnectivity found, and this ADR's
final shape fixes: invitations through a not-yet-reporting browser are silently dropped (the first
version restarted the browser on every foreground and could wedge reconnection); the session mesh
let one mismatched phone end the game for everyone; the reconnect deadline ran down while
suspended; simultaneous joins could exceed the 7-player cap. See `docs/architecture.md` →
*MultipeerConnectivity behaviours the transport works around*.

## Consequences

- `GameTransport` grew `stopBrowsing()`, `TransportError.connectionFailed` /
  `.incompatibleVersion(_, from:)`, `DiscoveredHost.isCompatible` and the `receivedAt` field;
  `stop()` finishes `events`; `startHosting`/`startBrowsing` are no-ops while running; `connect`
  waits for discovery and re-confirms existing links.
- A player who drops is removed from the host's roster and re-added on reconnect (at the end of
  the list); their score survives because `scores` is keyed by `PlayerID`.
- Timeouts are injectable (`connectTimeout`, `reconnectTimeout`, `retryDelay`, `flushDelay`) so
  tests run in milliseconds.
- Kicked players can rejoin by tapping the game again; blocking that is part of Stage 4's host
  approval work.
