#!/usr/bin/env python3
"""Derive an easier chart by keeping only main-beat notes from an existing chart."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from osu_to_chart import MIN_HOLD_MS, sanitize_notes


def near_main_beat(beat: float, tol: float) -> bool:
    return abs(beat - round(beat)) <= tol


def simplify_notes(
    notes: list[dict],
    bpm: float,
    offset_beats: float,
    *,
    beat_tol: float = 0.12,
    stride: int = 1,
) -> list[dict]:
    """Keep notes whose start is on a main beat; snap to the beat grid.

    stride=1 keeps every beat; stride=2 keeps every other beat (1, 3, 5, ...).
    """
    ms_per_beat = 60000.0 / bpm

    def dur_ms(start: float, end: float) -> float:
        return (end - start) * ms_per_beat

    # Collect candidates snapped to integer beats (optionally strided).
    # key: (start_beat, position) -> note (prefer longer holds)
    chosen: dict[tuple[float, int], dict] = {}

    for note in notes:
        start = float(note["start"])
        if not near_main_beat(start, beat_tol):
            continue
        snapped = float(round(start))
        if stride > 1 and int(snapped) % stride != 0:
            continue
        if snapped < 0:
            continue
        pos = int(note["position"])
        key = (snapped, pos)

        if note["type"] == "long":
            end = float(note["end"])
            # Snap end to a later main beat; keep at least one beat of hold when possible.
            end_snap = float(max(snapped + stride, math.ceil(end - beat_tol)))
            if dur_ms(snapped, end_snap) < MIN_HOLD_MS:
                candidate = {"type": "single", "start": snapped, "position": pos}
            else:
                candidate = {
                    "type": "long",
                    "start": snapped,
                    "end": end_snap,
                    "position": pos,
                }
        else:
            candidate = {"type": "single", "start": snapped, "position": pos}

        prev = chosen.get(key)
        if prev is None:
            chosen[key] = candidate
            continue
        # Prefer long over single; if both long, keep the longer one.
        if prev["type"] == "single" and candidate["type"] == "long":
            chosen[key] = candidate
        elif prev["type"] == "long" and candidate["type"] == "long":
            if float(candidate["end"]) > float(prev["end"]):
                chosen[key] = candidate

    simplified = list(chosen.values())
    simplified.sort(key=lambda n: (n["start"], n["position"], 0 if n["type"] == "single" else 1))
    # Round for stable JSON
    out: list[dict] = []
    for n in simplified:
        if n["type"] == "long":
            out.append(
                {
                    "type": "long",
                    "start": round(float(n["start"]), 6),
                    "end": round(float(n["end"]), 6),
                    "position": int(n["position"]),
                }
            )
        else:
            out.append(
                {
                    "type": "single",
                    "start": round(float(n["start"]), 6),
                    "position": int(n["position"]),
                }
            )
    return sanitize_notes(out, bpm, offset_beats)


def simplify_chart(
    chart: dict,
    *,
    difficulty: int = 2,
    beat_tol: float = 0.12,
    stride: int = 1,
) -> dict:
    meta = dict(chart["meta"])
    bpm = float(meta["bpm"])
    offset_beats = float(meta["offsetBeats"])
    notes = simplify_notes(
        list(chart["notes"]),
        bpm,
        offset_beats,
        beat_tol=beat_tol,
        stride=stride,
    )
    meta["difficulty"] = difficulty
    return {
        "formatVersion": int(chart.get("formatVersion", 1)),
        "meta": meta,
        "notes": notes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Source .chart.json")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output .chart.json")
    parser.add_argument("--difficulty", type=int, default=2)
    parser.add_argument(
        "--tol",
        type=float,
        default=0.12,
        help="How close to an integer beat a note start must be (beats)",
    )
    parser.add_argument(
        "--stride",
        type=int,
        default=1,
        help="Keep every Nth beat (1=every beat, 2=every other beat)",
    )
    args = parser.parse_args()

    chart = json.loads(args.input.read_text(encoding="utf-8"))
    easy = simplify_chart(
        chart,
        difficulty=args.difficulty,
        beat_tol=args.tol,
        stride=args.stride,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(easy, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    src_n = len(chart.get("notes", []))
    dst_n = len(easy["notes"])
    print(
        f"Wrote {args.output} ({dst_n} notes, was {src_n}) "
        f"difficulty={easy['meta']['difficulty']} stride={args.stride}"
    )


if __name__ == "__main__":
    main()
