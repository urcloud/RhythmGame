class_name ScoreCalculator
extends RefCounted


static func build_judgment_objects(notes: Array, timing: Timing) -> Array:
	## Each object: { id, note_index, kind: "hit"|"release", lane, time_ms }
	var objs: Array = []
	for i in range(notes.size()):
		var note: Dictionary = notes[i]
		var lane := int(note["position"])
		var start_ms := timing.beat_to_ms(float(note["start"]))
		objs.append({
			"id": objs.size(),
			"note_index": i,
			"kind": "hit",
			"lane": lane,
			"time_ms": start_ms,
			"is_long": str(note["type"]) == "long",
		})
		if str(note["type"]) == "long":
			var end_ms := timing.beat_to_ms(float(note["end"]))
			objs.append({
				"id": objs.size(),
				"note_index": i,
				"kind": "release",
				"lane": lane,
				"time_ms": end_ms,
				"is_long": true,
			})

	objs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["time_ms"]), float(b["time_ms"])):
			if int(a["lane"]) == int(b["lane"]):
				# long start before end at same visual edge cases
				if str(a["kind"]) != str(b["kind"]):
					return str(a["kind"]) == "hit"
			return int(a["lane"]) < int(b["lane"])
		return float(a["time_ms"]) < float(b["time_ms"])
	)
	# reassign perfect-score order ids after sort
	for i in range(objs.size()):
		objs[i]["order"] = i
	return objs


static func perfect_points(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if n <= 0:
		return out
	var base := int(1_000_000 / n)
	var remainder := 1_000_000 - base * n
	out.resize(n)
	for i in range(n):
		out[i] = base + (1 if i < remainder else 0)
	return out


static func contribution(perfect: int, grade: Judge.Grade) -> int:
	return int(floor(float(perfect) * Judge.weight(grade)))
