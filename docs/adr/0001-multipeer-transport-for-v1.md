# ADR 0001: MultipeerConnectivity behind a transport protocol for v1

- Status: Accepted
- Date: 2026-10-25

## Context

v1 must let iPhones on the same Wi-Fi discover each other and exchange small messages with no
server. Candidates: Apple's MultipeerConnectivity (MC), or Bonjour + `Network.framework`
(`NWListener`/`NWConnection`) written by hand. Later stages add an internet transport, so the
game logic must not depend on the first choice.

## Decision

Use **MultipeerConnectivity** for discovery and messaging in v1, wrapped in the `GameTransport`
protocol defined in `BuzzCore`. Engines never see MC types.

## Alternatives considered

- **Bonjour + Network.framework** — more control over wire format and timing, Wi-Fi only,
  roughly 3× the code (listener, connection pool, framing, reconnection). Deferred; it can be
  added as another `GameTransport` if MC latency or reliability disappoints.
- **Cloud relay from day one** — needs accounts/infra, contradicts "free, local, no server" v1.

## Consequences

- Discovery, invitations, session management and reliable framing come for free.
- MC also works over peer-to-peer Wi-Fi and Bluetooth, so "no router" play is a documentation
  item, not a feature.
- Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_quickbuzz._tcp`,
  `_quickbuzz._udp`) in Info.plist; without them discovery fails silently.
- MC sessions suspend when the app is backgrounded; the session layer must handle reconnects
  (Stage 2) and `hello` must be idempotent (it is).
- MC is practically ~8 peers per session; fine for a party game, documented as a limit.
- Cannot be tested in CI; `LoopbackTransport` exists so engines and views are testable anyway.
