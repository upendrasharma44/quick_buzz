# ADR 0003: Firebase for accounts, session history and internet rooms

- Status: Proposed (to be confirmed at the start of Stage 6)
- Date: 2026-10-25

## Context

Stages 5–7 add a $0.99/year "Plus" tier with an email login, saved/previous sessions and
internet play between devices that are not on the same network. The project is a solo/side
project: minimal operations is the dominant requirement.

## Decision

Use **Firebase**: Authentication (email/password + email link), **Firestore** for users and session
history, **Cloud Functions** to verify App Store subscription status (App Store Server API) and
write the entitlement, and **Realtime Database** (or Cloud Run WebSocket if latency demands) as
the Stage 7 relay transport. Access goes through `SessionStore` / `AuthService` protocols in
`BuzzCloud` so the app never imports Firebase directly.

## Alternatives considered

- **Supabase** — Postgres/Auth/Realtime, good fit; smaller iOS ecosystem and the user preferred Firebase.
- **Custom Vapor server** — full control, but hosting, TLS, backups and uptime become the user's job.
- **CloudKit** — free and private, but no email login, no server-side receipt validation, no
  low-latency relay.

## Consequences

- Firebase iOS SDK is added via SPM in Stage 6 only; the free v1 app stays dependency-free.
- Subscription truth lives in StoreKit 2 on-device (Stage 5); the server copy only unlocks cloud
  features and enables cross-device state.
- Email/password alone does not trigger Apple's "Sign in with Apple" requirement; adding any
  third-party social login would.
- Account deletion must be implemented (App Store rule) — Cloud Function deleting user docs.
- Free tier limits (reads/writes) are far above expected usage; billing alerts to be set.
