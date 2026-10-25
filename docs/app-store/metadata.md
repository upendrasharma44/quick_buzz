# App Store metadata — BuzzLight 1.0

Paste-ready text for App Store Connect. Character limits are Apple's; counts are noted where they
are tight. Screenshots: `docs/app-store/screenshots/` (regenerate with `scripts/screenshots.sh`).

## App information

| Field | Value |
|---|---|
| Name (≤ 30) | BuzzLight |
| Fallback names if taken | BuzzLight: Quiz Buzzer · BuzzLight – Party Buzzer |
| Subtitle (≤ 30) | Who buzzed first? Find out. |
| Bundle ID | `com.upendrasharma.buzzlight` |
| SKU | `buzzlight-ios` |
| Primary category | Games → Trivia |
| Secondary category | Games → Family |
| Content rights | No third-party content |
| Age rating | 4+ (answer "None" to every content question; no unrestricted web access; no user-generated content shared beyond the room) |
| Price | Free |
| Availability | All territories |
| Support URL | https://github.com/upendrasharma44/quick_buzz/issues |
| Marketing URL | https://github.com/upendrasharma44/quick_buzz (optional) |
| Privacy policy URL | https://github.com/upendrasharma44/quick_buzz/blob/main/docs/app-store/privacy-policy.md (or the GitHub Pages URL if Pages is enabled) |
| Copyright | © 2026 Upendra Sharma |

## Promotional text (≤ 170)

Turn every iPhone in the room into a game-show buzzer. One phone hosts, everyone else buzzes —
and the host's phone settles who was first, to the millisecond.

## Description (≤ 4000)

Quiz night, classroom, family game — whoever answers first has to buzz first. BuzzLight turns the
phones you already have into buzzers and settles the "I was first!" argument for good.

HOW IT WORKS
• One person taps Host a game. Everyone nearby taps Join a game and picks it from the list.
• The host asks a question and taps Arm buzzers.
• Everyone smashes their big red button. The host's phone shows who was first, second and third,
  and by how many milliseconds.
• Press too early and you're locked out for that round, so no buzzing before the question is done.
• The host awards points with a tap and moves on to the next round. Final scores at the end.

NO ACCOUNTS, NO INTERNET, NO ADS
• Every phone just needs Wi-Fi switched on — on the same network, or connected directly phone to
  phone where there's no network to share.
  <!-- Keep the second half only once connectivity matrix rows N2–N3 (docs/testing.md) pass on
       devices with the Network.framework transport; otherwise say "on the same Wi-Fi network". -->
• No sign-up and no data collected. Nothing leaves the room.
• Up to 8 phones in a game: one host and seven players.

MADE FOR THE ROOM YOU'RE IN
• Huge buzzer you can hit without looking, with sound and haptics.
• The screen stays awake while you play.
• If a phone drops off for a moment, it rejoins by itself and keeps its score.

## Keywords (≤ 100, comma-separated, no spaces after commas)

buzzer,quiz,trivia,game show,party,pub quiz,classroom,family,first,lockout,local,friends

(88 characters)

## What's New (1.0)

First release: host or join a buzzer game with phones nearby, live rankings to the millisecond,
early-press lockout, points and final scores.

## App Privacy (nutrition label)

- Data collection: **"No, we do not collect data from this app."** → label shows **Data Not Collected**.
- Tracking: none. No third-party SDKs.
- Display names and game messages travel only between nearby phones in the same game and are kept in
  memory for that game; the display name is also stored on the device. Neither is collected by the developer.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is set in Info.plist. The app uses only encryption built into
iOS (MultipeerConnectivity session encryption), which is exempt. Answer accordingly if asked.

## Screenshots (6.9" iPhone, 1320 × 2868)

| File | Shows | Suggested caption |
|---|---|---|
| `1-host-results.png` | Host console with a round's ranking and awards | See who buzzed first — to the millisecond |
| `2-player-winner.png` | Player buzzer after winning | Every phone becomes a buzzer |
| `3-player-live.png` | Player buzzer, buzzers live | Smash it the moment the host arms |
| `4-host-scores.png` | Second round results and scoreboard | Award points, run round after round |
| `5-join-list.png` | Join screen listing a nearby game | Join a game nearby — no accounts |
| `6-player-too-early.png` | Locked out for pressing early | Jump the gun and you sit the round out |
