#!/usr/bin/env python3
"""Derive easier/medium charts by keeping notes on a beat subdivision grid."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from osu_to_chart import MIN_HOLD_MS, sanitize_notes


def snap_to_grid(beat: float, grid: int) -> float:
    return round(beat * grid) / grid


def near_grid(beat: float, grid: int, tol: float) -> bool:
    return abs(beat - snap_to_grid(beat, grid)) <= tol


def simplify_notes(
    notes: list[dict],
    bpm: float,
    offset_beats: float,
    *,
    beat_tol: float = 0.12,
    stride: int = 1,
    grid: int = 1,
) -> list[dict]:
    """Keep notes on a subdivision grid and snap them.

    grid=1 → quarter (main) beats
    grid=2 → eighths
    grid=4 → sixteenths
    stride keeps every Nth grid step after snapping.
    """
    if grid < 1:
        raise ValueError("grid must be >= 1")
    ms_per_beat = 60000.0 / bpm
    step = 1.0 / grid

    def dur_ms(start: float, end: float) -> float:
        return (end - start) * ms_per_beat

    chosen: dict[tuple[float, int], dict] = {}

    for note in notes:
        start = float(note["start"])
        if not near_grid(start, grid, beat_tol):
            continue
        snapped = snap_to_grid(start, grid)
        if snapped < 0:
            continue
        # stride in grid units (0, stride, 2*stride, ...)
        grid_index = int(round(snapped * grid))
        if stride > 1 and grid_index % stride != 0:
            continue
        pos = int(note["position"])
        key = (snapped, pos)

        if note["type"] == "long":
            end = float(note["end"])
            end_snap = max(snapped + step * stride, math.ceil((end - beat_tol) * grid) / grid)
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
        if prev["type"] == "single" and candidate["type"] == "long":
            chosen[key] = candidate
        elif prev["type"] == "long" and candidate["type"] == "long":
            if float(candidate["end"]) > float(prev["end"]):
                chosen[key] = candidate

    simplified = list(chosen.values())
    simplified.sort(key=lambda n: (n["start"], n["position"], 0 if n["type"] == "single" else 1))
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
    grid: int = 1,
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
        grid=grid,
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
        help="Max distance from a grid beat to keep a note (in beats)",
    )
    parser.add_argument(
        "--stride",
        type=int,
        default=1,
        help="Keep every Nth grid step (1=all grid beats)",
    )
    parser.add_argument(
        "--grid",
        type=int,
        default=1,
        help="Subdivision grid: 1=quarters, 2=eighths, 4=sixteenths",
    )
    args = parser.parse_args()

    # Slightly tighter default tol for denser grids so off-grid 16ths don't leak in.
    tol = args.tol
    if args.grid >= 2 and abs(args.tol - 0.12) < 1e-9:
        tol = 0.08 / args.grid + 0.04  # ~0.08 for grid=2

    chart = json.loads(args.input.read_text(encoding="utf-8"))
    out_chart = simplify_chart(
        chart,
        difficulty=args.difficulty,
        beat_tol=tol,
        stride=args.stride,
        grid=args.grid,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(out_chart, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    src_n = len(chart.get("notes", []))
    dst_n = len(out_chart["notes"])
    print(
        f"Wrote {args.output} ({dst_n} notes, was {src_n}) "
        f"difficulty={out_chart['meta']['difficulty']} grid={args.grid} stride={args.stride}"
    )


if __name__ == "__main__":
    main()
