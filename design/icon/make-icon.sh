#!/usr/bin/env bash
# Renders the QuickBuzz app icon (light, dark, tinted) from one SVG template.
# Usage: design/icon/make-icon.sh        Requires: rsvg-convert (brew install librsvg)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../App/Resources/Assets.xcassets/AppIcon.appiconset"

# render <variant> <bg-top> <bg-bottom> <arc> <base-side> <base-top> <dome-light> <dome-dark> <bolt> <shine-opacity>
render() {
  local name=$1 bg1=$2 bg2=$3 arc=$4 side=$5 top=$6 dome1=$7 dome2=$8 bolt=$9 shine=${10}
  local svg="$HERE/AppIcon-$name.svg"
  cat > "$svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="$bg1"/>
      <stop offset="1" stop-color="$bg2"/>
    </linearGradient>
    <radialGradient id="dome" cx="0.38" cy="0.3" r="0.8">
      <stop offset="0" stop-color="$dome1"/>
      <stop offset="1" stop-color="$dome2"/>
    </radialGradient>
  </defs>

  <!-- Full-bleed square: iOS applies the corner mask. -->
  <rect width="1024" height="1024" fill="url(#bg)"/>

  <!-- Signal arcs: the buzz going out to everyone nearby. -->
  <g fill="none" stroke="$arc" stroke-width="38" stroke-linecap="round">
    <path d="M260.9,415 A290,290 0 0 1 389.4,297.2"/>
    <path d="M191.6,375 A370,370 0 0 1 355.6,224.7" opacity="0.6"/>
    <path d="M634.6,297.2 A290,290 0 0 1 763.1,415"/>
    <path d="M668.4,224.7 A370,370 0 0 1 832.4,375" opacity="0.6"/>
  </g>

  <!-- Shadow -->
  <ellipse cx="512" cy="790" rx="300" ry="52" fill="#000" opacity="0.18"/>

  <!-- Buzzer base -->
  <path d="M232,640 L232,745 A280,70 0 0 0 792,745 L792,640 Z" fill="$side"/>
  <ellipse cx="512" cy="640" rx="280" ry="70" fill="$top"/>

  <!-- Dome -->
  <path d="M302,630 A210,205 0 0 1 722,630 A210,52 0 0 1 302,630 Z" fill="url(#dome)"/>
  <ellipse cx="400" cy="510" rx="62" ry="34" fill="#fff" opacity="$shine" transform="rotate(-30 400 510)"/>

  <!-- Lightning bolt -->
  <path d="M535,438 L452,566 L506,566 L474,668 L580,516 L522,516 L566,438 Z"
        fill="$bolt" stroke-linejoin="round"/>
</svg>
SVG
  rsvg-convert -w 1024 -h 1024 "$svg" -o "$OUT/AppIcon-$name.png"
  echo "rendered $name"
}

#        variant  bg-top    bg-bottom arc      base-side base-top dome-light dome-dark bolt     shine
render   light    "#FF9A3D" "#FF3B5C" "#FFFFFF" "#23153A" "#3B2860" "#FF5A4F"  "#C8102E" "#FFD23F" 0.35
render   dark     "#24143A" "#120A1F" "#FF8A3D" "#0B0614" "#2E2050" "#FF5A4F"  "#B00D28" "#FFD23F" 0.30
render   tinted   "#000000" "#000000" "#FFFFFF" "#3A3A3A" "#6A6A6A" "#F2F2F2"  "#BDBDBD" "#3A3A3A" 0.55
