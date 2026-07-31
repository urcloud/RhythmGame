#!/usr/bin/env python3
"""Convert osu! mania .osu beatmap to RhythmGame chart JSON (format v1)."""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path


def parse_osu(text: str) -> dict:
    sections: dict[str, list[str]] = {}
    current = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(line)
    return sections


def parse_kv(lines: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in lines:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        out[key.strip()] = value.strip()
    return out


def primary_bpm_and_offset(timing_lines: list[str]) -> tuple[float, float]:
    """Return (bpm, offset_ms) from the first uninherited timing point."""
    for line in timing_lines:
        parts = line.split(",")
        if len(parts) < 7:
            continue
        time_ms = float(parts[0])
        beat_length = float(parts[1])
        uninherited = int(float(parts[6]))
        if uninherited == 1 and beat_length > 0:
            bpm = 60000.0 / beat_length
            return bpm, time_ms
    raise ValueError("No uninherited timing point found in .osu")


def mania_column(x: float, keycount: int) -> int:
    col = int(x * keycount / 512)
    return max(0, min(keycount - 1, col))


def convert_osu_to_chart(
    osu_path: Path,
    audio_relpath: str,
    *,
    keycount: int = 3,
    difficulty: int = 5,
    title_override: str | None = None,
    artist_override: str | None = None,
) -> dict:
    text = osu_path.read_text(encoding="utf-8", errors="replace")
    sections = parse_osu(text)
    general = parse_kv(sections.get("General", []))
    metadata = parse_kv(sections.get("Metadata", []))
    difficulty_sec = parse_kv(sections.get("Difficulty", []))

    cs = difficulty_sec.get("CircleSize")
    if cs is not None:
        keycount = int(float(cs))

    if keycount != 3:
        raise ValueError(f"Expected 3-key mania chart, got keycount={keycount}")

    mode = int(float(general.get("Mode", "3")))
    if mode != 3:
        raise ValueError(f"Expected mania Mode=3, got Mode={mode}")

    bpm, offset_ms = primary_bpm_and_offset(sections.get("TimingPoints", []))
    offset_beats = offset_ms * (bpm / 60000.0)

    notes: list[dict] = []
    for line in sections.get("HitObjects", []):
        parts = line.split(",")
        if len(parts) < 5:
            continue
        x = float(parts[0])
        time_ms = float(parts[2])
        obj_type = int(parts[3])
        position = mania_column(x, keycount)
        start_beat = time_ms * (bpm / 60000.0) - offset_beats
        if start_beat < -1e-9:
            continue
        start_beat = max(0.0, start_beat)

        is_hold = bool(obj_type & 128)
        if is_hold:
            # hold: endTime:hitSound:...
            end_field = parts[5] if len(parts) > 5 else ""
            end_ms = float(end_field.split(":")[0])
            end_beat = end_ms * (bpm / 60000.0) - offset_beats
            if end_beat <= start_beat:
                continue
            notes.append(
                {
                    "type": "long",
                    "start": round(start_beat, 6),
                    "end": round(end_beat, 6),
                    "position": position,
                }
            )
        else:
            notes.append(
                {
                    "type": "single",
                    "start": round(start_beat, 6),
                    "position": position,
                }
            )

    notes.sort(key=lambda n: (n["start"], n["position"], 0 if n["type"] == "single" else 1))
    notes = dedupe_and_trim_overlaps(notes)

    title = title_override or metadata.get("Title") or metadata.get("TitleUnicode") or osu_path.stem
    artist = artist_override or metadata.get("Artist") or metadata.get("ArtistUnicode") or "Unknown"
    if not artist:
        artist = "Unknown"

    return {
        "formatVersion": 1,
        "meta": {
            "title": title,
            "artist": artist,
            "audio": audio_relpath,
            "bpm": round(bpm, 6),
            "offsetBeats": round(offset_beats, 6),
            "difficulty": difficulty,
        },
        "notes": notes,
    }


def dedupe_and_trim_overlaps(notes: list[dict]) -> list[dict]:
    """Enforce SPEC invariants: no duplicate (start, position); no long overlaps."""
    seen: set[tuple[float, int]] = set()
    cleaned: list[dict] = []
    # Track active long intervals per lane: list of (start, end)
    longs: dict[int, list[tuple[float, float]]] = {0: [], 1: [], 2: []}

    for note in notes:
        key = (note["start"], note["position"])
        if key in seen:
            continue
        pos = note["position"]
        if note["type"] == "long":
            start, end = note["start"], note["end"]
            # Trim or skip overlapping longs (touching end==start allowed)
            for a, b in longs[pos]:
                if start < b and end > a and not math.isclose(start, b) and not math.isclose(end, a):
                    # overlap: shorten current note to start at previous end if possible
                    if start < b:
                        start = b
                    break
            if end <= start:
                continue
            note = {
                "type": "long",
                "start": round(start, 6),
                "end": round(end, 6),
                "position": pos,
            }
            longs[pos].append((note["start"], note["end"]))
            seen.add((note["start"], pos))
            cleaned.append(note)
        else:
            seen.add(key)
            cleaned.append(note)
    return cleaned


def find_osu_files(path: Path) -> list[Path]:
    if path.is_file() and path.suffix.lower() == ".osu":
        return [path]
    return sorted(path.rglob("*.osu"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("osu", type=Path, help=".osu file or directory containing .osu")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output .chart.json path")
    parser.add_argument(
        "--audio",
        required=True,
        help="Audio path relative to the output chart file",
    )
    parser.add_argument("--difficulty", type=int, default=5)
    parser.add_argument("--title", default=None)
    parser.add_argument("--artist", default=None)
    args = parser.parse_args()

    osu_files = find_osu_files(args.osu)
    if not osu_files:
        raise SystemExit(f"No .osu files found under {args.osu}")
    # Prefer a difficulty that mentions mania / generated, else first
    osu_path = osu_files[0]
    for candidate in osu_files:
        name = candidate.name.lower()
        if "mania" in name or "mapperatorinator" in name or "3k" in name:
            osu_path = candidate
            break

    chart = convert_osu_to_chart(
        osu_path,
        args.audio,
        difficulty=args.difficulty,
        title_override=args.title,
        artist_override=args.artist,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(chart, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.output} ({len(chart['notes'])} notes) from {osu_path}")


if __name__ == "__main__":
    main()
