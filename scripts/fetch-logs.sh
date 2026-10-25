#!/usr/bin/env bash
# Pulls BuzzLight debug logs from iPhones paired with this Mac (USB, or the same network with
# "Connect via network" on) and merges them into one timeline sorted by wall-clock time.
#
# Usage: scripts/fetch-logs.sh [device name or identifier ...]
#   default: every paired iOS device that isn't unavailable.
# Output: logs/<timestamp>/<device>/debug.log[.1] and logs/<timestamp>/merged.log
#
# The phones must run a build with Settings → Diagnostics → Record debug log on (or launched with
# -BLDebugLog YES), installed from Xcode (devicectl can only read development-signed app containers).
set -euo pipefail

BUNDLE=com.upendrasharma.buzzlight
SOURCE_DIR="Library/Application Support/DebugLog"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

devices=()
if [ $# -gt 0 ]; then
  devices=("$@")
else
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1
  while IFS= read -r id; do devices+=("$id"); done < <(python3 - "$json" <<'EOF'
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    c = d.get("connectionProperties", {})
    if d.get("hardwareProperties", {}).get("platform") == "iOS" \
       and c.get("pairingState") == "paired" and c.get("tunnelState") != "unavailable":
        print(d["identifier"])
EOF
)
  rm -f "$json"
fi
[ ${#devices[@]} -gt 0 ] || { echo "No reachable devices. Connect a phone or pass its name."; exit 1; }

fetched=0
for device in "${devices[@]}"; do
  # devicectl also prints text on stdout, so its JSON must go to a file.
  details="$(mktemp)"
  name="$(xcrun devicectl device info details --device "$device" --json-output "$details" >/dev/null 2>&1 \
          && python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["deviceProperties"]["name"])' "$details" 2>/dev/null \
          || echo "$device")"
  rm -f "$details"
  safe="$(echo "$name" | tr -c 'A-Za-z0-9-' '_' | sed 's/_*$//')"
  mkdir -p "$OUT/$safe"
  got=0
  for file in debug.log.1 debug.log; do
    if xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
         --domain-identifier "$BUNDLE" --source "$SOURCE_DIR/$file" \
         --destination "$OUT/$safe/$file" --quiet --timeout 60 >/dev/null 2>&1; then
      got=1
    fi
  done
  if [ $got -eq 1 ]; then
    echo "✓ $name"
    fetched=$((fetched + 1))
  else
    echo "✗ $name: no log file (logging was off, nothing recorded yet, app not installed from Xcode, or phone unreachable)"
    rmdir "$OUT/$safe" 2>/dev/null || true
  fi
done

python3 - "$OUT" <<'EOF'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
lines = []
for folder in sorted(p for p in out.iterdir() if p.is_dir()):
    for name in ("debug.log.1", "debug.log"):
        f = folder / name
        if f.exists():
            for line in f.read_text(errors="replace").splitlines():
                if line.strip():
                    lines.append((line.split(" ", 1)[0], folder.name, line))
lines.sort(key=lambda t: t[0])  # ISO-8601 wall-clock timestamps sort as text
width = max((len(d) for _, d, _ in lines), default=0)
(out / "merged.log").write_text("".join(f"{d:<{width}} | {l}\n" for _, d, l in lines))
print(f"merged {len(lines)} lines → {out / 'merged.log'}")
EOF
[ $fetched -gt 0 ] || exit 1
