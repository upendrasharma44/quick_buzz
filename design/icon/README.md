# BuzzLight app icon

`make-icon.sh` writes the three `AppIcon-*.svg` templates here and renders them to
`App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-{light,dark,tinted}.png` (1024×1024,
full-bleed; iOS applies the corner mask). Requires `rsvg-convert` (`brew install librsvg`).

```sh
design/icon/make-icon.sh                       # regenerate the asset catalog PNGs
PREVIEW_DIR=/tmp/icons design/icon/make-icon.sh  # also write 256 px and 64 px previews
```

## Concept

"BuzzLight" = buzzer + light-year. The game-show buzzer dome with its lightning bolt (the buzz)
is circled by a tilted orbit ring carrying one glowing satellite orb, and hovers on a cyan
thruster glow over a starfield with four-point sparkles (the light-year). The ring crosses in
front of the dome on the lower half and behind it on the upper half, so it reads as a planet
ring even at 64 px.

The artwork is original. Nothing from the Pixar character (suit, wings, colour blocking, face) is
used, so the icon is safe for the App Store.

| Variant | Background | Ring / orb | Notes |
|---|---|---|---|
| light | indigo → coral gradient | white ring, cyan orb and glow | default |
| dark | deep indigo → near-black | pale-cyan ring, cyan orb | iOS dark appearance |
| tinted | black | white ring and orb, greyscale buzzer | iOS tints it with the user's accent |

To change the look, edit the SVG template inside `render()` in `make-icon.sh` and the colour
table at the bottom; do not hand-edit the generated `AppIcon-*.svg` or the PNGs.
