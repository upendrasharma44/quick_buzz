# ADR 0005: Rank buzzes by host-converted press timestamps with per-player clock-offset estimation

- Status: Proposed
- Date: 2026-10-25
- Decision makers: @upendrasharma44
- Confidence: Medium — the method is standard (NTP-style offset estimation) but has not yet been
  measured over MultipeerConnectivity on physical devices; see *Re-evaluation triggers*.
- Target stage: 4 (Robustness & fairness polish). Until it ships, architecture rule 1 / CLAUDE.md
  rule 3 (arrival order, with arrival stamped per ADR 0004) remain in effect.

## Decision

**The host stays the single source of truth, but ranks on when each player *pressed*, not on when
the `buzz` frame *arrived*.** Each player stamps the press on its own monotonic clock and sends
that stamp with `buzz`. The host estimates every player's clock offset with NTP-style
four-timestamp exchanges, converts each press to host time, clamps it to the window in which the
press could have happened, and ranks by the converted time. Two presses closer together than the
combined measurement error are reported as a **tie**, not as a winner and a loser. A player with no
fresh, tight offset estimate falls back to arrival order and is marked low-confidence.

Rejected for this purpose: vector/Lamport/hybrid logical clocks, Raft-style consensus, and
peer-to-peer buzz broadcast (see *Alternatives considered*).

## Context

Arrival order at the host (architecture rule 1 / CLAUDE.md rule 3, stamped per ADR 0004) is
deterministic and cannot be gamed, but it carries a
built-in bias equal to the *difference in one-way latency* between players. MultipeerConnectivity
may link one player over infrastructure Wi-Fi and another over Bluetooth, so the player on the
slower path loses every close call even when they pressed first. Humans in a quiz routinely buzz
within the same tens of milliseconds, which is the same order as that bias.

Two players pressing independently are *concurrent* events in the distributed-systems sense: no
information flows between them before they press. Any mechanism that only tracks causality or
agreement therefore cannot order them. Recovering a physical order requires measuring time at the
source (the player's phone) and relating the two clocks, which is what this ADR does.

Constraints that shaped the design: engines in `BuzzCore` stay synchronous and transport-free
(CLAUDE.md rule 2); wall clocks are never used; the host remains the only arbiter; the result must
be honest about what it cannot resolve.

## How it works

1. **Clocks.** Both sides use `ContinuousClock` (keeps running through device sleep, never jumps).
   Instants are not encodable, so a player sends durations since a player-local epoch (its session
   start) as `Int64` nanoseconds. Offsets are relative, so the epoch is arbitrary; a reconnect
   (new `hello`) invalidates that player's offset samples.
2. **Press capture.** The player stamps the press on touch-down, synchronously in the gesture
   callback, before any async work or engine call is scheduled. The stamp travels in `buzz`.
3. **Offset estimation.** Host sends a sync frame at `t1`; the player stamps receipt `t2` and reply
   `t3`; the host stamps arrival `t4`. Then

   ```
   offset θ = ((t2 − t1) + (t3 − t4)) / 2        (player clock − host clock)
   rtt    δ = (t4 − t1) − (t3 − t2)              (player processing time removed)
   ```

   The host sends a burst per player at `hello` and again just before each `armed`, keeps the
   sample with the smallest `δ`, and treats `δ / 2` as that player's error bound. Sync frames are
   sent *unreliable* so a retransmission never pollutes a sample; `buzz` stays reliable.
4. **Ranking (in `HostEngine`).** `pressHost = pressedAt − θ`, clamped to
   `[armSentAt, receivedAt]` — nobody can press before being armed or after the host heard them.
   Sort by `pressHost`. If two neighbours differ by less than `(δ_A + δ_B) / 2` they are tied;
   `BuzzEntry` carries the tie flag and error bound so the UI can show it. A tie is resolved by the
   host (random pick, re-buzz or host decision), never by pretending the order is known.
5. **Fallback.** No sample, a sample older than the current round, or `δ` above a threshold ⇒ use
   `receivedAt` as today and flag the entry low-confidence. Arrival is always at or after the true
   press, so a fallback entry in a mixed ranking is biased late by its one-way latency; the flag
   tells the host so.
6. **Purity.** Offset maths is a pure value type (`ClockOffsetEstimator` or similar) fed with the
   four durations; the engine's buzz input gains the reported press duration, `arm()` gains an
   `at:` instant the engine stores as the clamp floor (`armSentAt`), and the offset table is engine
   state updated through inputs. Everything is unit-testable with fixed instants.

## Alternatives considered

- **Keep arrival order (status quo).** Simplest and non-gameable, but it bakes in link-asymmetry
  bias and has no notion of a tie. Stays as the fallback and as the pre-Stage-4 behaviour.
- **Vector clocks / Lamport timestamps / hybrid logical clocks.** They order *causally related*
  events and report independent events as concurrent. Two buzzes in a round have no happens-before
  edge, so every close call comes back "concurrent" — exactly the case that needs resolving.
  Hybrid logical clocks additionally lean on physical time, so the offset step is needed anyway.
- **Raft (or any consensus log).** Makes the group agree on *an* order; it does not choose the
  right one. The order is leader receipt order, which is the status quo with a replicated log and
  elections on top. What Raft buys is host failover, which is a separate Stage 4 item ("host
  handoff spike") and not a fairness mechanism.
- **Broadcast every buzz to every peer, with a "buzzes seen before I pressed" list.** This creates
  real causal edges, so the host can prove "B saw A before pressing ⇒ B is after A" and can prove a
  tie when neither saw the other. But the tie band equals the peer-to-peer one-way latency, which
  is wider than the error bound of the offset exchange, and more observers only average out
  jitter, not the systematic per-link bias. An explicit Bluetooth channel adds nothing: Multipeer
  already uses Bluetooth when it is the only path, and Core Bluetooth connection intervals and
  advertising cadence are coarser than the latencies being corrected. Kept in reserve as a cheat
  check (a reported press that precedes a buzz the player admits seeing is a lie).

## Evaluation

Not measured. Reasoning only: with one-way delays `d₁` (host→player) and `d₂` (player→host),
the estimate is `θ + (d₁ − d₂) / 2`, so the error is at most `δ / 2` of the best sample whatever
the asymmetry and near zero when the paths are symmetric. The asymmetry itself cannot be detected
by any two-party exchange. Stage 4
should measure best-sample `δ` and jitter on two physical devices over Wi-Fi and over Bluetooth
before this ADR is moved to *Accepted*, and record the numbers here.

## Consequences

- Removes the link-asymmetry bias from close calls and makes the residual uncertainty visible;
  the guarantee becomes: *correct order whenever the press gap exceeds the measured error bound,
  an explicit tie otherwise*.
- Protocol: `buzz` gains a required press timestamp, sync request/reply frames are added (or
  `ping`/`pong` grow timestamps), `BuzzEntry` gains tie/confidence fields. New cases and a required
  field are breaking under `docs/protocol.md` versioning rule 1 ⇒ `Envelope.currentVersion` bump,
  recorded there.
- Transport contract: `GameTransport.send`/`broadcast` gain a delivery mode (or a separate
  `sendUnreliable`); `MultipeerTransport` maps it to `MCSessionSendDataMode.unreliable`,
  `LoopbackTransport` treats both as reliable. `docs/protocol.md` (Discovery table, *Delivery*)
  and `docs/architecture.md` (*Transport contract*, *MultipeerTransport*) currently say every frame
  is sent `.reliable`; both are updated to exempt sync frames. The Stage 7 relay transport must
  honour the mode too.
- When implemented: CLAUDE.md rule 3 is reworded to "the host ranks on host-converted monotonic
  press times using host-measured offsets; wall clocks are never used; the host remains the only
  arbiter", and architecture rule 1 and the roadmap fairness rules are updated to match.
- `deltaMilliseconds` becomes a press-time delta rather than an arrival delta; the UI copy should
  say so.
- Trust: the host accepts a player's reported press within the clamp window, so a modified client
  can gain at most one one-way latency. Acceptable for a party game; the causal-list check above
  is the mitigation if it ever matters.
- Cost: one short burst of small unreliable frames per player before each round; negligible for
  the ≤ 8-peer sessions Multipeer supports.

## Re-evaluation triggers

- Two-device measurements show the best-sample error bound is not materially smaller than the
  arrival-order bias it replaces (no fairness gain for the added complexity).
- MultipeerConnectivity's unreliable mode proves unusable or its jitter makes `δ` thresholds trip
  constantly; a hand-written `Network.framework` transport (ADR 0001 alternative) would be the next
  step.
- Stage 7's internet relay transport: offsets over the internet are far noisier, so the policy may
  need to be per-transport.
- Evidence of players gaming the press timestamp ⇒ adopt the peer causal-list check.
