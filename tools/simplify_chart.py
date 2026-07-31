#!/usr/bin/env python3
"""Derive Easy/Normal charts from denser source charts.

Applies rhythm-game charting principles adapted from osu!mania Easy/Normal
ranking criteria (3-key): musical emphasis, BPM-scaled density, readable
chords, LN hygiene, lane balance, and jack avoidance.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path

from osu_to_chart import MIN_HOLD_MS, sanitize_notes

LANES = (0, 1, 2)
# Adjacent pairs preferred for 3-key jumps; avoid awkward spreads when possible.
PREFERRED_JUMPS = ((0, 1), (1, 2), (0, 2))


@dataclass(frozen=True)
class DifficultyProfile:
    name: str
    difficulty: int
    # Comfortable onset gap target in milliseconds (active sections).
    target_onset_ms: float
    # Hard floor for onset gaps (ms). Nothing closer than this.
    min_onset_ms: float
    max_chord: int
    min_ln_beats: float
    min_ln_release_gap_beats: float
    max_dense_chain: int  # consecutive onsets at the dense (secondary) snap
    chord_min_gap_beats: float  # min gap between chords
    allow_notes_during_ln: bool
    # How aggressively to keep weak-beat filler (0..1).
    filler_keep: float
    # Keep dense (secondary) onsets at/above this score percentile (0..1).
    dense_score_percentile: float
    # Same-lane minimum gap as a multiple of secondary snap.
    same_lane_gap_factor: float
    # Max empty gap to tolerate in active music, in primary snaps.
    max_active_gap_primaries: float


PROFILES: dict[str, DifficultyProfile] = {
    "easy": DifficultyProfile(
        name="easy",
        difficulty=2,
        target_onset_ms=420.0,
        min_onset_ms=300.0,
        max_chord=2,
        min_ln_beats=1.0,
        min_ln_release_gap_beats=1.0,
        max_dense_chain=4,
        chord_min_gap_beats=1.0,
        allow_notes_during_ln=False,
        filler_keep=0.50,
        dense_score_percentile=0.55,
        same_lane_gap_factor=2.0,  # ≈ primary when secondary = primary/2
        max_active_gap_primaries=3.0,
    ),
    "medium": DifficultyProfile(
        name="medium",
        difficulty=3,
        target_onset_ms=240.0,
        min_onset_ms=150.0,
        max_chord=2,
        min_ln_beats=0.5,
        min_ln_release_gap_beats=0.5,
        max_dense_chain=7,
        chord_min_gap_beats=0.5,
        allow_notes_during_ln=False,
        filler_keep=0.90,
        dense_score_percentile=0.30,
        same_lane_gap_factor=1.0,
        max_active_gap_primaries=2.0,
    ),
}


def snap_to_grid(beat: float, grid: float) -> float:
    if grid <= 0:
        raise ValueError("grid must be > 0")
    return round(beat / grid) * grid


def near_grid(beat: float, grid: float, tol: float) -> bool:
    return abs(beat - snap_to_grid(beat, grid)) <= tol


def snaps_for_bpm(bpm: float, profile: DifficultyProfile) -> tuple[float, float]:
    """Return (primary_snap, secondary_snap) in beats, BPM-scaled.

    Ranking criteria assume ~180 BPM. Higher BPM → larger beat snaps;
    lower BPM → denser snaps (down to 1/4 for Easy only when very slow).
    """
    primary_beats = profile.target_onset_ms * bpm / 60000.0
    secondary_beats = profile.min_onset_ms * bpm / 60000.0

    candidates = (0.25, 0.5, 1.0, 2.0)

    def nearest(value: float, allowed: tuple[float, ...]) -> float:
        return min(allowed, key=lambda c: (abs(c - value), -c))

    # Easy: never primary on 1/4; secondary 1/4 only when BPM is very low
    # (Scaling BPM: below ~90–100, Easy may introduce rare denser snaps).
    if profile.name == "easy":
        primary_allowed = (0.5, 1.0, 2.0)
        secondary_allowed = (0.5, 1.0, 2.0) if bpm >= 95 else (0.25, 0.5, 1.0, 2.0)
    else:
        primary_allowed = candidates
        secondary_allowed = candidates

    primary = nearest(primary_beats, primary_allowed)
    secondary = nearest(secondary_beats, secondary_allowed)
    if secondary > primary:
        secondary = primary
    # Keep secondary strictly denser when possible.
    denser = [c for c in secondary_allowed if c < primary]
    if denser and secondary >= primary:
        secondary = denser[-1]
    return primary, secondary


def detect_grid_phase(events: list[Event], primary: float) -> float:
    """Find beat-phase offset so the primary grid matches the source chart.

    Converted charts are often shifted by 1/4 relative to barline-aligned 0.
    Without this, Easy filtering keeps only sparse on-phase leftovers.
    """
    if not events or primary <= 0:
        return 0.0
    step = 0.25
    offsets: list[float] = []
    o = 0.0
    while o < primary - 1e-9:
        offsets.append(round(o, 6))
        o += step

    best_o = 0.0
    best_key = (-1, -1.0)
    for offset in offsets:
        n = 0
        weight = 0.0
        for ev in events:
            if near_grid(ev.time - offset, primary, primary * 0.12):
                n += 1
                weight += ev.score
        key = (n, weight)
        if key > best_key:
            best_key = key
            best_o = offset
    return best_o


def measure_strength(beat: float, phase: float = 0.0) -> float:
    """Downbeat / backbeat weight in 4/4, relative to detected phase."""
    pos = (beat - phase) % 4.0
    q = round(pos * 4) / 4
    if math.isclose(q, 0.0, abs_tol=1e-6) or math.isclose(q, 4.0, abs_tol=1e-6):
        return 3.0
    if math.isclose(q, 2.0, abs_tol=1e-6):
        return 2.0
    if math.isclose(q, 1.0, abs_tol=1e-6) or math.isclose(q, 3.0, abs_tol=1e-6):
        return 1.0
    if math.isclose(q % 1.0, 0.5, abs_tol=1e-6):
        return 0.45
    return 0.2


@dataclass
class Event:
    time: float
    notes: list[dict]
    score: float
    density: float


def build_events(notes: list[dict], bpm: float, phase: float = 0.0) -> list[Event]:
    """Group source notes by snapped 1/4 onset and score musical importance."""
    _ = bpm
    by_time: dict[float, list[dict]] = {}
    for note in notes:
        t = snap_to_grid(float(note["start"]), 0.25)
        if t < 0:
            continue
        by_time.setdefault(t, []).append(note)

    times = sorted(by_time)
    # Local density: notes in ±1 beat window (source).
    density_at: dict[float, float] = {}
    for t in times:
        window = sum(
            len(by_time[u]) for u in times if abs(u - t) <= 1.0 + 1e-9
        )
        density_at[t] = float(window)

    events: list[Event] = []
    for t in times:
        group = by_time[t]
        chord = len({int(n["position"]) for n in group})
        longs = sum(1 for n in group if n["type"] == "long")
        long_span = 0.0
        for n in group:
            if n["type"] == "long":
                long_span = max(long_span, float(n["end"]) - float(n["start"]))
        dens = density_at[t]
        score = (
            measure_strength(t, phase) * 2.2
            + chord * 1.8
            + longs * 1.4
            + min(long_span, 4.0) * 0.35
            + min(dens, 8.0) * 0.55
        )
        events.append(Event(time=t, notes=group, score=score, density=dens))
    return events


def phase_from_notes(notes: list[dict], primary: float) -> float:
    """Detect phase using lightweight unscored events."""
    rough: list[Event] = []
    seen: set[float] = set()
    for note in notes:
        t = snap_to_grid(float(note["start"]), 0.25)
        if t < 0 or t in seen:
            continue
        seen.add(t)
        rough.append(Event(time=t, notes=[], score=1.0, density=1.0))
    return detect_grid_phase(rough, primary)


def _percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, max(0, int(round((len(ordered) - 1) * p))))
    return ordered[idx]


def _gap_fit(gap: float, unit: float, tol_ratio: float = 0.28) -> bool:
    """True if gap is near 1..4 units of the given snap."""
    if gap <= 0 or unit <= 0:
        return False
    k = round(gap / unit)
    if k < 1 or k > 4:
        return False
    return abs(gap - k * unit) <= unit * tol_ratio


def select_onsets(
    events: list[Event],
    profile: DifficultyProfile,
    primary: float,
    secondary: float,
    phase: float,
) -> list[Event]:
    """Pick musically important onsets with BPM-aware relative spacing.

    Uses gaps from the previous kept note (not a single global beat phase),
    because converted charts often drift / change phase across sections.
    """
    if not events:
        return []

    score_values = [e.score for e in events]
    median = _percentile(score_values, 0.50)
    high = _percentile(score_values, 0.72)
    dense_cut = _percentile(score_values, profile.dense_score_percentile)

    selected: list[Event] = []
    last_t = -1e9
    dense_chain = 0

    for ev in events:
        t = ev.time
        gap = t - last_t
        if gap + 1e-9 < secondary:
            continue

        strength = measure_strength(t, phase)
        fits_primary = _gap_fit(gap, primary) or gap >= primary * 0.85
        fits_secondary = _gap_fit(gap, secondary) and gap + 1e-9 < primary * 0.85
        # First note, or after a long break: always eligible.
        after_break = gap >= primary * profile.max_active_gap_primaries

        if after_break or last_t < 0:
            selected.append(ev)
            last_t = t
            dense_chain = 0
            continue

        if fits_secondary:
            if dense_chain >= profile.max_dense_chain:
                continue
            # Easy: 1/2 (or denser) only as occasional accents, not streams.
            if profile.name == "easy":
                if strength < 2.0 and ev.score < high:
                    continue
                if dense_chain >= 2:
                    continue
            elif ev.score < dense_cut and strength < 1.0 and ev.density < 3.0:
                continue
            dense_chain += 1
            selected.append(ev)
            last_t = t
            continue

        if fits_primary or gap >= primary:
            if (
                ev.score < median * 0.85
                and strength < 1.0
                and gap < primary * 1.35
                and ev.density < 3.0
            ):
                keep_roll = (int(round(t * 1000)) % 100) / 100.0
                if keep_roll > profile.filler_keep:
                    continue
            if strength <= 0.2 and gap < primary * 1.1 and ev.score < high:
                continue
            if gap + 1e-9 >= primary:
                dense_chain = 0
            else:
                dense_chain += 1
            selected.append(ev)
            last_t = t
            continue

        # Odd gap but source is busy — Normal only; Easy waits for primary fit.
        if (
            profile.name == "medium"
            and gap >= secondary
            and ev.density >= 3.0
            and ev.score >= median
            and dense_chain < profile.max_dense_chain
        ):
            dense_chain += 1
            selected.append(ev)
            last_t = t

    selected = fill_active_gaps(selected, events, primary, secondary, profile)
    if profile.name == "medium" and secondary < primary - 1e-9:
        selected = pack_secondary(selected, events, primary, secondary, dense_cut)
    return selected


def pack_secondary(
    selected: list[Event],
    candidates: list[Event],
    primary: float,
    secondary: float,
    dense_cut: float,
) -> list[Event]:
    """Insert additional denser onsets for Normal where music supports it."""
    chosen = {e.time: e for e in selected}
    times = sorted(chosen)
    for a, b in zip(times, times[1:]):
        if b - a < primary * 1.5 - 1e-9:
            continue
        # Pick best candidate near the midpoint / secondary steps.
        t = a + secondary
        while t < b - secondary * 0.49:
            best = None
            for cand in candidates:
                if abs(cand.time - t) <= secondary * 0.35:
                    if best is None or cand.score > best.score:
                        best = cand
            if (
                best is not None
                and best.time not in chosen
                and best.score >= dense_cut
                and best.density >= 1.0
                and best.time - a >= secondary - 1e-9
                and b - best.time >= secondary - 1e-9
            ):
                chosen[best.time] = best
            t += secondary
    merged = list(chosen.values())
    merged.sort(key=lambda e: e.time)
    return merged


def fill_active_gaps(
    selected: list[Event],
    candidates: list[Event],
    primary: float,
    secondary: float,
    profile: DifficultyProfile,
) -> list[Event]:
    """If source has notes but Easy left a long hole, reintroduce accents."""
    if not candidates:
        return selected
    chosen = {e.time: e for e in selected}
    times = sorted(chosen)
    max_gap = primary * profile.max_active_gap_primaries

    for a, b in zip(times, times[1:]):
        if b - a <= max_gap + 1e-9:
            continue
        # Repeatedly insert the best candidate in the largest remaining hole.
        guard = 0
        left, right = a, b
        while right - left > max_gap + 1e-9 and guard < 12:
            guard += 1
            mid = (left + right) / 2.0
            best = None
            for cand in candidates:
                if cand.time in chosen:
                    continue
                if cand.time - left < secondary - 1e-9:
                    continue
                if right - cand.time < secondary - 1e-9:
                    continue
                dens_ok = cand.density >= (1.0 if profile.name == "medium" else 1.2)
                if not dens_ok and cand.score < 5.0:
                    continue
                # Prefer near midpoint, then by score.
                dist = abs(cand.time - mid)
                key = (-cand.score, dist)
                if best is None or key < best[0]:
                    best = (key, cand)
            if best is None:
                break
            ev = best[1]
            chosen[ev.time] = ev
            # Split hole at inserted note; continue on the larger side next loop
            # by resetting to full scan via outer zip — break inner and rely on
            # a second outer pass below.
            left = ev.time

    # Second sweep after insertions.
    times = sorted(chosen)
    for a, b in zip(times, times[1:]):
        if b - a <= max_gap + 1e-9:
            continue
        mid = (a + b) / 2.0
        best = None
        for cand in candidates:
            if cand.time in chosen:
                continue
            if not (a + secondary <= cand.time <= b - secondary):
                continue
            if cand.density < 1.2 and cand.score < 5.0:
                continue
            key = (-cand.score, abs(cand.time - mid))
            if best is None or key < best[0]:
                best = (key, cand)
        if best is not None:
            chosen[best[1].time] = best[1]

    merged = list(chosen.values())
    merged.sort(key=lambda e: e.time)
    return merged


def pick_lanes_for_event(
    ev: Event,
    *,
    last_lanes: set[int],
    lane_counts: dict[int, int],
    active_ln_lanes: set[int],
    profile: DifficultyProfile,
    want_chord: bool,
) -> list[tuple[int, dict]]:
    """Choose 1–2 lanes from source notes with balance and jack avoidance."""
    # Best representative note per lane.
    best: dict[int, dict] = {}
    for note in ev.notes:
        pos = int(note["position"])
        if pos not in LANES:
            continue
        prev = best.get(pos)
        if prev is None:
            best[pos] = note
            continue
        # Prefer long over single; longer LN wins.
        if prev["type"] == "single" and note["type"] == "long":
            best[pos] = note
        elif prev["type"] == "long" and note["type"] == "long":
            if float(note["end"]) > float(prev["end"]):
                best[pos] = note

    if not best:
        return []

    blocked = set(active_ln_lanes) if not profile.allow_notes_during_ln else set()
    available = [p for p in best if p not in blocked]
    if not available:
        # If everything is blocked by LN, skip event.
        return []

    total = max(1, sum(lane_counts.values()))
    avg = total / 3.0

    def lane_cost(pos: int) -> float:
        # Balance toward equal lane usage; punish overused lanes hard.
        overuse = max(0.0, lane_counts[pos] - avg)
        cost = float(lane_counts[pos]) * 1.1 + overuse * 2.4
        if pos in last_lanes:
            cost += 5.0  # strongly avoid jack / same-hand repeat
        # Prefer source-authentic lanes lightly (only among available).
        cost -= 0.25
        return cost

    # If source lanes are all overused relative to a missing lane, allow
    # inventing a single on the underused empty lane only when source had
    # a chord (musical accent) — otherwise stay faithful to source columns.
    available.sort(key=lane_cost)
    chosen_positions: list[int] = [available[0]]

    if want_chord and profile.max_chord >= 2 and len(available) >= 2:
        # Prefer a preferred jump pair including first choice.
        first = chosen_positions[0]
        partner = None
        for a, b in PREFERRED_JUMPS:
            if first == a and b in available and b not in last_lanes:
                partner = b
                break
            if first == b and a in available and a not in last_lanes:
                partner = a
                break
        if partner is None:
            for pos in available[1:]:
                if pos not in last_lanes:
                    partner = pos
                    break
        if partner is not None:
            chosen_positions.append(partner)

    return [(pos, best[pos]) for pos in chosen_positions]


def materialize_notes(
    selected: list[Event],
    profile: DifficultyProfile,
    primary: float,
    bpm: float,
    phase: float,
) -> list[dict]:
    """Turn selected events into singles/longs with Easy/Normal constraints."""
    ms_per_beat = 60000.0 / bpm
    min_ln = max(profile.min_ln_beats, (MIN_HOLD_MS + 1.0) / ms_per_beat)

    out: list[dict] = []
    last_lanes: set[int] = set()
    last_chord_t = -1e9
    lane_counts = {0: 0, 1: 0, 2: 0}
    active_lns: list[tuple[float, float, int]] = []  # start, end, pos
    last_release_t = -1e9
    dense_chord_pending_end = False
    prev_t = -1e9

    recent_ln_start = -1e9

    for idx, ev in enumerate(selected):
        t = max(0.0, float(ev.time))
        # Expire LNs
        active_lns = [ln for ln in active_lns if ln[1] > t + 1e-9]
        active_ln_lanes = {ln[2] for ln in active_lns}

        gap = t - prev_t
        is_dense = gap + 1e-9 < primary
        chord_size_src = len({int(n["position"]) for n in ev.notes})
        strong = (
            measure_strength(t, phase) >= 2.0
            or ev.score >= 8.0
            or chord_size_src >= 2
        )

        # Chords: emphasize strong moments; never mid dense stream.
        want_chord = False
        if (
            profile.max_chord >= 2
            and strong
            and (t - last_chord_t) >= profile.chord_min_gap_beats - 1e-9
        ):
            if not is_dense or dense_chord_pending_end:
                want_chord = True

        picks = pick_lanes_for_event(
            ev,
            last_lanes=last_lanes,
            lane_counts=lane_counts,
            active_ln_lanes=active_ln_lanes,
            profile=profile,
            want_chord=want_chord,
        )
        if not picks:
            continue

        # Mid-dense-stream: force singles even if we wanted a chord.
        if is_dense and not dense_chord_pending_end and len(picks) > 1:
            picks = picks[:1]

        placed_lanes: set[int] = set()
        placed_any = False
        for pos, src in picks:
            if pos in active_ln_lanes and not profile.allow_notes_during_ln:
                continue

            if src["type"] == "long":
                end = float(src["end"])
                # Snap end; keep at least min_ln.
                end = max(t + min_ln, snap_to_grid(end, 0.25))
                # Cap extreme LNs a bit for readability on Easy.
                if profile.name == "easy":
                    end = min(end, t + max(4.0, primary * 4))
                # Easy: avoid LN streams (release/press every beat is exhausting).
                ln_stream = (
                    profile.name == "easy"
                    and t - recent_ln_start < primary * 1.5 + 1e-9
                )
                # Release spacing.
                if ln_stream or end - last_release_t < profile.min_ln_release_gap_beats - 1e-9:
                    # Demote to single rather than pile releases.
                    note = {"type": "single", "start": t, "position": pos}
                elif end - t < min_ln - 1e-9:
                    note = {"type": "single", "start": t, "position": pos}
                else:
                    # Ensure no overlap with existing LN in lane.
                    conflict = False
                    for a, b, p in active_lns:
                        if p == pos and t < b and end > a:
                            conflict = True
                            break
                    if conflict:
                        note = {"type": "single", "start": t, "position": pos}
                    else:
                        note = {
                            "type": "long",
                            "start": t,
                            "end": end,
                            "position": pos,
                        }
                        active_lns.append((t, end, pos))
                        last_release_t = end
                        recent_ln_start = t
            else:
                note = {"type": "single", "start": t, "position": pos}

            out.append(note)
            placed_lanes.add(pos)
            lane_counts[pos] += 1
            placed_any = True

        if not placed_any:
            continue

        if len(placed_lanes) >= 2:
            last_chord_t = t
            dense_chord_pending_end = False
        elif is_dense:
            dense_chord_pending_end = True
        else:
            dense_chord_pending_end = False

        last_lanes = placed_lanes
        prev_t = t

        # Lookahead: if next event ends a dense chain, allow chord there.
        if idx + 1 < len(selected):
            nxt = selected[idx + 1]
            if (nxt.time - t) >= primary - 1e-9:
                dense_chord_pending_end = True

    return out


def enforce_ln_isolation(notes: list[dict], profile: DifficultyProfile) -> list[dict]:
    """Drop notes that fall inside LN holds (Easy/Normal guideline)."""
    if profile.allow_notes_during_ln:
        return notes
    longs = [
        (float(n["start"]), float(n["end"]), int(n["position"]))
        for n in notes
        if n["type"] == "long"
    ]
    kept: list[dict] = []
    for note in notes:
        t = float(note["start"])
        pos = int(note["position"])
        blocked = False
        for a, b, lp in longs:
            if a < t < b:
                # Any column during LN hold is blocked on Easy/Normal here.
                # (RC allows opposite hand in some tutorials; for 3-key beginners
                # full isolation is clearer and safer.)
                blocked = True
                break
            if note["type"] == "long" and lp == pos and a < t < b:
                blocked = True
                break
        if not blocked:
            kept.append(note)
    return kept


def enforce_no_jacks(notes: list[dict], min_gap: float) -> list[dict]:
    """Relocate or drop same-lane repeats that are too close."""
    notes = sorted(notes, key=lambda n: (float(n["start"]), int(n["position"])))
    last_time_in_lane = {-1: -1e9, 0: -1e9, 1: -1e9, 2: -1e9}
    result: list[dict] = []

    for note in notes:
        t = float(note["start"])
        pos = int(note["position"])
        if t - last_time_in_lane[pos] < min_gap - 1e-9:
            # Try relocate to a free lane at same time.
            occupied = {
                int(n["position"])
                for n in result
                if math.isclose(float(n["start"]), t, abs_tol=1e-6)
            }
            relocated = None
            for cand in sorted(
                LANES,
                key=lambda p: (t - last_time_in_lane[p] < min_gap, last_time_in_lane[p]),
            ):
                if cand in occupied:
                    continue
                if t - last_time_in_lane[cand] >= min_gap - 1e-9:
                    relocated = cand
                    break
            if relocated is None:
                continue  # drop
            note = dict(note)
            note["position"] = relocated
            pos = relocated
        result.append(note)
        last_time_in_lane[pos] = t
        if note["type"] == "long":
            # Holding a lane also "uses" it through the hold for jack purposes
            # at the start; release handled separately.
            pass
    return result


def trim_chord_size(notes: list[dict], max_chord: int) -> list[dict]:
    by_t: dict[float, list[dict]] = {}
    for n in notes:
        by_t.setdefault(round(float(n["start"]), 6), []).append(n)
    out: list[dict] = []
    for t in sorted(by_t):
        group = by_t[t]
        if len(group) <= max_chord:
            out.extend(group)
            continue
        # Keep longs first, then prefer outer/center balance by position diversity.
        group.sort(
            key=lambda n: (
                0 if n["type"] == "long" else 1,
                abs(int(n["position"]) - 1),
                int(n["position"]),
            )
        )
        out.extend(group[:max_chord])
    return out


def rebalance_lanes(notes: list[dict], min_same_lane_gap: float) -> list[dict]:
    """Move singles from overused lanes to underused ones when safe."""
    notes = [dict(n) for n in notes]
    notes.sort(key=lambda n: (float(n["start"]), int(n["position"])))
    if not notes:
        return notes

    def counts() -> dict[int, int]:
        c = {0: 0, 1: 0, 2: 0}
        for n in notes:
            c[int(n["position"])] += 1
        return c

    # Occupancy timeline per lane for conflict checks.
    def lane_busy(pos: int, t: float, ignore_idx: int) -> bool:
        for i, n in enumerate(notes):
            if i == ignore_idx or int(n["position"]) != pos:
                continue
            start = float(n["start"])
            if n["type"] == "long":
                if start - 1e-9 <= t <= float(n["end"]) + 1e-9:
                    return True
            elif abs(start - t) <= 1e-9:
                return True
            if abs(start - t) < min_same_lane_gap - 1e-9:
                return True
        return False

    # Redistribute until lanes are roughly even or no safe move remains.
    for _ in range(64):
        c = counts()
        total = sum(c.values())
        avg = total / 3.0
        rich = max(LANES, key=lambda p: c[p])
        poor = min(LANES, key=lambda p: c[p])
        if c[rich] - c[poor] <= max(3, int(avg * 0.15)):
            break
        moved = False
        for i, n in enumerate(notes):
            if n["type"] != "single" or int(n["position"]) != rich:
                continue
            t = float(n["start"])
            if lane_busy(poor, t, i):
                continue
            if any(
                j != i
                and abs(float(o["start"]) - t) <= 1e-9
                and int(o["position"]) == poor
                for j, o in enumerate(notes)
            ):
                continue
            n["position"] = poor
            moved = True
            break
        if not moved:
            break
    notes.sort(key=lambda n: (float(n["start"]), int(n["position"])))
    return notes


def simplify_notes(
    notes: list[dict],
    bpm: float,
    offset_beats: float,
    *,
    profile: DifficultyProfile,
) -> list[dict]:
    primary, secondary = snaps_for_bpm(bpm, profile)
    phase = phase_from_notes(notes, primary)
    events = build_events(notes, bpm, phase)
    # Refine phase with scored events, then rescore once.
    phase = detect_grid_phase(events, primary)
    events = build_events(notes, bpm, phase)
    selected = select_onsets(events, profile, primary, secondary, phase)
    raw = materialize_notes(selected, profile, primary, bpm, phase)
    raw = trim_chord_size(raw, profile.max_chord)
    raw = enforce_ln_isolation(raw, profile)
    same_lane_gap = max(secondary, secondary * profile.same_lane_gap_factor)
    # Easy: never jack faster than primary rhythm.
    if profile.name == "easy":
        same_lane_gap = max(same_lane_gap, primary)
    raw = enforce_no_jacks(raw, min_gap=same_lane_gap)
    raw = rebalance_lanes(raw, same_lane_gap)
    raw = enforce_no_jacks(raw, min_gap=same_lane_gap)
    raw = enforce_ln_isolation(raw, profile)
    # Round for stable JSON / sanitize.
    cleaned: list[dict] = []
    for n in raw:
        if n["type"] == "long":
            cleaned.append(
                {
                    "type": "long",
                    "start": round(float(n["start"]), 6),
                    "end": round(float(n["end"]), 6),
                    "position": int(n["position"]),
                }
            )
        else:
            cleaned.append(
                {
                    "type": "single",
                    "start": round(float(n["start"]), 6),
                    "position": int(n["position"]),
                }
            )
    cleaned.sort(key=lambda n: (n["start"], n["position"], 0 if n["type"] == "single" else 1))
    return sanitize_notes(cleaned, bpm, offset_beats)


def simplify_chart(
    chart: dict,
    *,
    profile: DifficultyProfile,
    difficulty: int | None = None,
) -> dict:
    meta = dict(chart["meta"])
    bpm = float(meta["bpm"])
    offset_beats = float(meta["offsetBeats"])
    notes = simplify_notes(
        list(chart["notes"]),
        bpm,
        offset_beats,
        profile=profile,
    )
    meta["difficulty"] = int(difficulty if difficulty is not None else profile.difficulty)
    return {
        "formatVersion": int(chart.get("formatVersion", 1)),
        "meta": meta,
        "notes": notes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Source .chart.json")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output .chart.json")
    parser.add_argument(
        "--preset",
        choices=sorted(PROFILES),
        default="easy",
        help="Charting preset (default: easy)",
    )
    parser.add_argument(
        "--difficulty",
        type=int,
        default=None,
        help="Override meta.difficulty (defaults to preset)",
    )
    args = parser.parse_args()

    profile = PROFILES[args.preset]
    chart = json.loads(args.input.read_text(encoding="utf-8"))
    bpm = float(chart["meta"]["bpm"])
    primary, secondary = snaps_for_bpm(bpm, profile)
    phase = phase_from_notes(list(chart.get("notes", [])), primary)
    out_chart = simplify_chart(chart, profile=profile, difficulty=args.difficulty)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(out_chart, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    src_n = len(chart.get("notes", []))
    dst_n = len(out_chart["notes"])
    print(
        f"Wrote {args.output} ({dst_n} notes, was {src_n}) "
        f"preset={profile.name} difficulty={out_chart['meta']['difficulty']} "
        f"primary={primary} secondary={secondary} phase={phase}"
    )


if __name__ == "__main__":
    main()
