# App Review notes — BuzzLight 1.0

Paste into App Store Connect → App Review Information → Notes.

---

BuzzLight is a buzzer for in-person quiz games. It has no accounts, no server and no in-app
purchases. A game needs **at least two iOS devices** near each other with **Wi-Fi switched on**.
The simplest setup is both devices on the same Wi-Fi network. There is no demo account because there
is nothing to sign in to.

To test:
1. On both devices, open BuzzLight and enter any name.
2. When asked, allow **Local Network** access (this is how phones find each other).
3. Device A: tap **Host a game**.
4. Device B: tap **Join a game**, then tap "<name>'s game" in the list. Device B now appears on
   Device A's screen.
5. Device A: tap **Arm buzzers**. Device B's big button turns red ("BUZZ!").
6. Device B: tap the red button. Device A shows Device B as first, with timing in milliseconds.
   Tap **+** to award a point, then **Next round**.
7. Pressing Device B's button *before* step 5 locks it out for that round ("Too early").
8. Device A: tap **End** → **End game** to see final scores on both devices.

The Local Network permission is only used to discover and talk to the other phones in the same
game, using Apple's Network framework (Bonjour). No data leaves the devices.

---

If only one device is available for review, the reviewer will see the Join screen's
"Looking for games…" state; please use two devices.
