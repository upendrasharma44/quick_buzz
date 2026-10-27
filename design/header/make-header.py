#!/usr/bin/env python3
"""Renders the optional App Store product page header for BuzzLight (21:9, 3840 x 1646).

Usage:  python3 design/header/make-header.py
Writes: design/header/ProductPageHeader-3840x1646.svg and .png (opaque, no alpha).
Needs:  rsvg-convert (brew install librsvg) and Xcode's `swift` (for scripts/flatten-png.swift).

Same artwork as the app icon (design/icon/make-icon.sh, light variant): the buzzer dome with its
bolt inside a tilted orbit ring with a cyan satellite orb, on a thruster glow, widened into a
starfield. Two phones on each side buzz towards it, so the purpose reads at a glance. No text,
prices, URLs, logos or copyright marks (Apple's creative-asset rules), so nothing to localize.
The buzzer stays inside the central third, which survives every device crop.
"""
import random
import subprocess
from pathlib import Path

W, H = 3840, 1646
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SVG = HERE / "ProductPageHeader-3840x1646.svg"
PNG = HERE / "ProductPageHeader-3840x1646.png"

# Icon palette (light variant in design/icon/make-icon.sh)
RING, ORB, GLOW = "#FFFFFF", "#4FE3FF", "#4FE3FF"
SIDE, TOP, DOME1, DOME2, BOLT = "#1B1038", "#3B2860", "#FF5A4F", "#C8102E", "#FFD23F"

rnd = random.Random(7)  # fixed seed: the starfield is identical on every run


def sparkle(cx, cy, r, opacity):
    k = r * 0.18
    return (f'<path d="M{cx},{cy - r} C{cx + k},{cy - k} {cx + k},{cy - k} {cx + r},{cy} '
            f'C{cx + k},{cy + k} {cx + k},{cy + k} {cx},{cy + r} C{cx - k},{cy + k} {cx - k},{cy + k} {cx - r},{cy} '
            f'C{cx - k},{cy - k} {cx - k},{cy - k} {cx},{cy - r} Z" fill="#FFFFFF" opacity="{opacity}"/>')


def stars():
    out = []
    for _ in range(260):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        r = rnd.choice([2, 2, 3, 3, 4, 5, 6])
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="#FFFFFF" opacity="{rnd.uniform(0.25, 0.9):.2f}"/>')
    for cx, cy, r, o in [(420, 260, 46, 0.95), (3420, 300, 54, 0.95), (1250, 180, 28, 0.8),
                         (2650, 150, 32, 0.85), (3650, 1250, 30, 0.7), (260, 1320, 26, 0.6),
                         (1600, 1480, 20, 0.5), (2350, 1500, 22, 0.55), (980, 820, 18, 0.6),
                         (2930, 860, 20, 0.6)]:
        out.append(sparkle(cx, cy, r, o))
    return "\n    ".join(out)


def phone(cx, cy, angle, toward):
    """A phone with a lit red buzzer on screen, plus buzz arcs pointing towards the centre."""
    w, h = 190, 380
    x, y = cx - w / 2, cy - h / 2
    arc_dir = 1 if toward == "right" else -1
    ax = cx + arc_dir * (w / 2 + 40)
    arcs = []
    for i, (r, o) in enumerate([(70, 0.95), (120, 0.6), (170, 0.35)]):
        sweep = 1 if arc_dir == 1 else 0
        arcs.append(f'<path d="M{ax},{cy - r} A{r},{r} 0 0 {sweep} {ax},{cy + r}" fill="none" '
                    f'stroke="#FFFFFF" stroke-width="16" stroke-linecap="round" opacity="{o}"/>')
    return f'''<g transform="rotate({angle} {cx} {cy})">
      <rect x="{x - 6}" y="{y - 6}" width="{w + 12}" height="{h + 12}" rx="40" fill="{GLOW}" opacity="0.35" filter="url(#soft)"/>
      <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="36" fill="{SIDE}" stroke="#CFF4FF" stroke-width="7"/>
      <rect x="{x + 14}" y="{y + 16}" width="{w - 28}" height="{h - 32}" rx="24" fill="#2E2050"/>
      <rect x="{cx - 28}" y="{y + 30}" width="56" height="14" rx="7" fill="{SIDE}"/>
      <circle cx="{cx}" cy="{cy + 20}" r="58" fill="{DOME2}" opacity="0.6" filter="url(#soft)"/>
      <circle cx="{cx}" cy="{cy + 20}" r="52" fill="url(#dome)"/>
      <path d="M{cx + 6},{cy - 12} L{cx - 14},{cy + 24} L{cx},{cy + 24} L{cx - 8},{cy + 52} L{cx + 18},{cy + 12} L{cx + 4},{cy + 12} L{cx + 14},{cy - 12} Z" fill="{BOLT}"/>
      {"".join(arcs)}
    </g>'''


def buzzer():
    """The icon's buzzer, ring and orb, in the icon's own 1024 coordinate space."""
    return f'''<ellipse cx="512" cy="760" rx="300" ry="70" fill="{GLOW}" opacity="0.75" filter="url(#blur)"/>
      <g transform="rotate(-16 512 545)" fill="none" stroke-linecap="round">
        <path d="M922,545 A410,118 0 0 0 102,545" stroke="{RING}" stroke-width="46" opacity="0.22"/>
        <path d="M922,545 A410,118 0 0 0 102,545" stroke="{RING}" stroke-width="24" opacity="0.9"/>
      </g>
      <ellipse cx="512" cy="790" rx="300" ry="52" fill="#000" opacity="0.22"/>
      <path d="M232,640 L232,745 A280,70 0 0 0 792,745 L792,640 Z" fill="{SIDE}"/>
      <ellipse cx="512" cy="640" rx="280" ry="70" fill="{TOP}"/>
      <ellipse cx="512" cy="640" rx="280" ry="70" fill="none" stroke="{GLOW}" stroke-width="6" opacity="0.55"/>
      <path d="M302,630 A210,205 0 0 1 722,630 A210,52 0 0 1 302,630 Z" fill="url(#dome)"/>
      <ellipse cx="400" cy="510" rx="62" ry="34" fill="#fff" opacity="0.35" transform="rotate(-30 400 510)"/>
      <path d="M535,438 L452,566 L506,566 L474,668 L580,516 L522,516 L566,438 Z" fill="{BOLT}"/>
      <g transform="rotate(-16 512 545)" fill="none" stroke-linecap="round">
        <path d="M922,545 A410,118 0 0 1 102,545" stroke="{RING}" stroke-width="46" opacity="0.22"/>
        <path d="M922,545 A410,118 0 0 1 102,545" stroke="{RING}" stroke-width="24" opacity="0.95"/>
        <circle cx="717" cy="647" r="44" fill="{ORB}" opacity="0.8" filter="url(#blurSmall)"/>
        <circle cx="717" cy="647" r="30" fill="url(#orbFill)"/>
      </g>'''


svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#150A33"/>
      <stop offset="0.5" stop-color="#2B1A6B"/>
      <stop offset="0.82" stop-color="#9C2F72"/>
      <stop offset="1" stop-color="#FF4D6D"/>
    </linearGradient>
    <radialGradient id="nebulaCyan" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{GLOW}" stop-opacity="0.32"/>
      <stop offset="1" stop-color="{GLOW}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="nebulaCoral" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FF6A88" stop-opacity="0.38"/>
      <stop offset="1" stop-color="#FF6A88" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="dome" cx="0.38" cy="0.3" r="0.8">
      <stop offset="0" stop-color="{DOME1}"/>
      <stop offset="1" stop-color="{DOME2}"/>
    </radialGradient>
    <radialGradient id="orbFill" cx="0.35" cy="0.35" r="0.7">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="0.45" stop-color="{ORB}"/>
      <stop offset="1" stop-color="{ORB}" stop-opacity="0.9"/>
    </radialGradient>
    <filter id="blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="26"/></filter>
    <filter id="blurSmall" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="14"/></filter>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="22"/></filter>
  </defs>

  <rect width="{W}" height="{H}" fill="url(#bg)"/>
  <ellipse cx="820" cy="520" rx="900" ry="620" fill="url(#nebulaCyan)"/>
  <ellipse cx="3150" cy="1200" rx="1000" ry="700" fill="url(#nebulaCoral)"/>
  <ellipse cx="1920" cy="860" rx="900" ry="560" fill="url(#nebulaCyan)" opacity="0.7"/>

  <g>
    {stars()}
  </g>

  <!-- Wide faint orbits that the phones sit on -->
  <g transform="rotate(-6 1920 880)" fill="none" stroke="#FFFFFF">
    <ellipse cx="1920" cy="880" rx="1560" ry="380" stroke-width="8" opacity="0.14"/>
    <ellipse cx="1920" cy="880" rx="1860" ry="520" stroke-width="6" opacity="0.08"/>
    <circle cx="560" cy="1010" r="14" fill="{ORB}" stroke="none" opacity="0.9"/>
    <circle cx="3330" cy="690" r="12" fill="{ORB}" stroke="none" opacity="0.9"/>
  </g>

  <!-- Players' phones buzzing towards the host's buzzer -->
  {phone(640, 1040, -12, "right")}
  {phone(940, 540, 9, "right")}
  {phone(2960, 540, -9, "left")}
  {phone(3200, 1040, 12, "left")}

  <!-- The buzzer from the icon, scaled 1.6x and centred -->
  <g transform="translate(1101,-150) scale(1.6)">
      {buzzer()}
  </g>
</svg>
'''

SVG.write_text(svg)
subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), str(SVG), "-o", str(PNG)], check=True)
subprocess.run(["swift", str(ROOT / "scripts" / "flatten-png.swift"), "--background", "150A33", str(PNG)], check=True)
print(f"rendered {PNG.relative_to(ROOT)}")
