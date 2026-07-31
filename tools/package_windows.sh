#!/usr/bin/env bash
# Build a Windows release folder: exe + loose chart/sample (not packed into the exe).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/game"
GODOT="${GODOT:-$ROOT/tools/godot}"
OUT="${1:-$ROOT/dist/RhythmGame}"
EXPORT_EXE="$GAME/build/windows/RhythmGame.exe"

if [[ ! -x "$GODOT" ]]; then
  echo "Godot binary not found at $GODOT" >&2
  echo "Set GODOT=/path/to/godot or place tools/godot" >&2
  exit 1
fi

mkdir -p "$GAME/build/windows"
echo "==> Exporting Windows Desktop preset..."
# Export needs the Windows export template installed in the Godot editor once.
"$GODOT" --headless --path "$GAME" --export-release "Windows Desktop" "$EXPORT_EXE"

if [[ ! -f "$EXPORT_EXE" ]]; then
  echo "Export failed: missing $EXPORT_EXE" >&2
  echo "In Godot Editor: Editor → Manage Export Templates → Download/Install, then retry." >&2
  exit 1
fi

echo "==> Assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"

cp -f "$EXPORT_EXE" "$OUT/RhythmGame.exe"
# Console wrapper is useful for crash logs; copy if Godot emitted one.
if [[ -f "$GAME/build/windows/RhythmGame.console.exe" ]]; then
  cp -f "$GAME/build/windows/RhythmGame.console.exe" "$OUT/"
fi

# Loose content next to the exe (same layout as the repo).
# Copy only — never move/rename files under $ROOT/chart or $ROOT/sample.
mkdir -p "$OUT/chart" "$OUT/sample"
shopt -s nullglob
chart_files=("$ROOT"/chart/*.json)
if ((${#chart_files[@]})); then
  cp -f "${chart_files[@]}" "$OUT/chart/"
fi
sample_mp3=("$ROOT"/sample/*.mp3)
if ((${#sample_mp3[@]})); then
  cp -f "${sample_mp3[@]}" "$OUT/sample/"
fi
shopt -u nullglob

cat > "$OUT/README.txt" <<'EOF'
RhythmGame (Windows)

Layout:
  RhythmGame.exe   - game
  chart/           - song charts (*.json) — add more anytime
  sample/          - mp3 files referenced by charts

Charts use meta.audio as a path relative to the chart file.
Current charts expect:  ../sample/YourSong.mp3

Settings (keys, scroll speed, chart_dir) are saved per-user under
%APPDATA%\Godot\app_userdata\RhythmGame\config.json
EOF

echo "==> Done: $OUT"
ls -la "$OUT" "$OUT/chart" "$OUT/sample" 2>/dev/null || ls -la "$OUT"
