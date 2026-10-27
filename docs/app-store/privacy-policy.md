# BuzzLight Privacy Policy

_Last updated: 25 October 2026_

BuzzLight is a buzzer game for people in the same room. This policy covers the BuzzLight iOS app.

## The short version

BuzzLight does not collect, store on any server, sell or share your personal data. There are no
accounts, no analytics, no advertising and no third-party SDKs.

## What the app handles, and where it stays

| Data | Where it goes | How long |
|---|---|---|
| The display name you type | Saved on your device. Sent to the other phones in a game you host or join, so they can show it. | On your device until you change it or delete the app. On other phones only for that game. |
| A random player identifier | Created on your device and sent to the other phones in your game, so a player who briefly disconnects keeps their score. | On your device until you delete the app. On other phones only for that game. |
| Buzzes, rankings and scores | Exchanged between the phones in the game. | In memory for that game only; nothing is saved after it ends. |

All of this travels directly between nearby devices over Wi-Fi (your local network, or a direct
phone-to-phone Wi-Fi link) using Apple's Network framework, encrypted with TLS. None of it is sent
to the developer or to any server.

## Diagnostic log

Settings → Diagnostics → Record debug log is off unless you turn it on (it is only on by default in
development builds used for testing, which are not distributed through the App Store). When on, the app writes a log
of what the game does (connections, messages, timings, display names in the game) to a file **on your
phone**. It is never sent anywhere automatically; it only leaves the phone if you choose Share debug
log and send it to someone. You can clear it at any time in the same place.

## Local Network permission

iOS asks for Local Network access so BuzzLight can find nearby phones and connect to them. It is
used for nothing else. You can turn it off in Settings → Privacy & Security → Local Network; the
app then can't find other players.

## Children

BuzzLight is suitable for all ages and collects no personal data from anyone, including children.

## Changes

If a future version adds features that handle data differently (for example optional accounts),
this policy will be updated before that version is released, and the date above will change.

## Contact

Questions: open an issue at https://github.com/upendrasharma44/quick_buzz/issues
