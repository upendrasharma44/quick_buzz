# BuzzLight product page header

Optional App Store creative asset: the header across the top of the product page on iOS 27 and
later. Leaving it out does not block submission.

```sh
python3 design/header/make-header.py   # writes ProductPageHeader-3840x1646.svg and .png
```

Needs `rsvg-convert` (`brew install librsvg`) and Xcode's `swift`, which runs
`scripts/flatten-png.swift` to remove the alpha channel; App Store Connect rejects images with alpha.

## Spec

| Item | Value | Source |
|---|---|---|
| Aspect ratio, size | 21:9, 3840 × 1646 px | Apple [creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications) |
| Format | PNG, opaque, no alpha | same |
| Upload | App Store Connect → version → Product Page Information → Header and Search Results → Header | — |

## Design

The app icon's artwork (`design/icon/make-icon.sh`, light palette) widened to a banner: the buzzer
dome and bolt inside the tilted orbit ring with its cyan satellite orb, centred on a thruster glow,
over a starfield with cyan and coral nebula glows. Two phones on each side show a lit buzzer and
send buzz arcs towards the centre, so the purpose of the app reads at a glance.

The buzzer stays inside the central square (1646 × 1646), so it survives the narrowest crop;
the phones and outer orbits are decoration that may be cropped. Check it with the Preview button
in App Store Connect after uploading.

Apple's [asset best practices](https://developer.apple.com/app-store/asset-best-practices/) that
shaped it:

- One clear idea, no clutter.
- No text, so nothing to localise; no prices, URLs, copyright symbols, awards or other platforms' logos.
- Content suitable for a 4+ rating.

The starfield uses a fixed random seed, so a re-run without edits reproduces the same image.
Edit the script, not the generated SVG or PNG.
