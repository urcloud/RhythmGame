class_name ChartValidator
extends RefCounted


static func validate(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "root must be an object"
	var root: Dictionary = data

	for key in root.keys():
		if key not in ["formatVersion", "meta", "notes"]:
			return "unknown top-level field: %s" % key

	if not root.has("formatVersion") or not root.has("meta") or not root.has("notes"):
		return "missing required fields: formatVersion, meta, notes"

	if typeof(root["formatVersion"]) != TYPE_FLOAT and typeof(root["formatVersion"]) != TYPE_INT:
		return "formatVersion must be integer"
	if int(root["formatVersion"]) != 1:
		return "unsupported formatVersion (expected 1)"

	var meta_err := _validate_meta(root["meta"])
	if meta_err != "":
		return meta_err

	if typeof(root["notes"]) != TYPE_ARRAY:
		return "notes must be an array"

	var notes: Array = root["notes"]
	for i in range(notes.size()):
		var note_err := _validate_note(notes[i], i)
		if note_err != "":
			return note_err

	var semantic := _validate_semantics(notes)
	if semantic != "":
		return semantic

	return ""


static func _validate_meta(meta_v: Variant) -> String:
	if typeof(meta_v) != TYPE_DICTIONARY:
		return "meta must be an object"
	var meta: Dictionary = meta_v
	for key in meta.keys():
		if key not in ["title", "artist", "audio", "bpm", "offsetBeats", "difficulty"]:
			return "unknown meta field: %s" % key
	for req in ["title", "artist", "audio", "bpm", "offsetBeats", "difficulty"]:
		if not meta.has(req):
			return "meta missing field: %s" % req

	if typeof(meta["title"]) != TYPE_STRING or str(meta["title"]).is_empty():
		return "meta.title must be a non-empty string"
	if typeof(meta["artist"]) != TYPE_STRING or str(meta["artist"]).is_empty():
		return "meta.artist must be a non-empty string"
	if typeof(meta["audio"]) != TYPE_STRING or str(meta["audio"]).is_empty():
		return "meta.audio must be a non-empty string"
	if not str(meta["audio"]).to_lower().ends_with(".mp3"):
		return "meta.audio must be an .mp3 path"

	if not (typeof(meta["bpm"]) == TYPE_FLOAT or typeof(meta["bpm"]) == TYPE_INT):
		return "meta.bpm must be a number"
	if float(meta["bpm"]) <= 0.0:
		return "meta.bpm must be > 0"

	if not (typeof(meta["offsetBeats"]) == TYPE_FLOAT or typeof(meta["offsetBeats"]) == TYPE_INT):
		return "meta.offsetBeats must be a number"

	if typeof(meta["difficulty"]) != TYPE_FLOAT and typeof(meta["difficulty"]) != TYPE_INT:
		return "meta.difficulty must be an integer"
	var diff := int(meta["difficulty"])
	if diff < 1 or diff > 10:
		return "meta.difficulty must be between 1 and 10"
	return ""


static func _validate_note(note_v: Variant, index: int) -> String:
	if typeof(note_v) != TYPE_DICTIONARY:
		return "notes[%d] must be an object" % index
	var note: Dictionary = note_v
	for key in note.keys():
		if key not in ["type", "start", "end", "position"]:
			return "notes[%d] unknown field: %s" % [index, key]
	for req in ["type", "start", "position"]:
		if not note.has(req):
			return "notes[%d] missing field: %s" % [index, req]

	var ntype := str(note["type"])
	if ntype != "single" and ntype != "long":
		return "notes[%d] type must be single or long" % index

	if not (typeof(note["start"]) == TYPE_FLOAT or typeof(note["start"]) == TYPE_INT):
		return "notes[%d] start must be a number" % index
	if float(note["start"]) < 0.0:
		return "notes[%d] start must be >= 0" % index

	if typeof(note["position"]) != TYPE_FLOAT and typeof(note["position"]) != TYPE_INT:
		return "notes[%d] position must be an integer" % index
	var pos := int(note["position"])
	if pos < 0 or pos > 2:
		return "notes[%d] position must be 0, 1, or 2" % index

	if ntype == "single":
		if note.has("end"):
			return "notes[%d] single must not have end" % index
	else:
		if not note.has("end"):
			return "notes[%d] long requires end" % index
		if not (typeof(note["end"]) == TYPE_FLOAT or typeof(note["end"]) == TYPE_INT):
			return "notes[%d] end must be a number" % index
		if float(note["end"]) <= float(note["start"]):
			return "notes[%d] end must be > start" % index
	return ""


static func _validate_semantics(notes: Array) -> String:
	var starts: Dictionary = {}
	for i in range(notes.size()):
		var note: Dictionary = notes[i]
		var key := "%s:%s" % [str(float(note["start"])), str(int(note["position"]))]
		if starts.has(key):
			return "duplicate note at (start=%s, position=%s)" % [str(note["start"]), str(note["position"])]
		starts[key] = i

	var longs: Array = []
	for i in range(notes.size()):
		var note: Dictionary = notes[i]
		if str(note["type"]) != "long":
			continue
		longs.append({
			"i": i,
			"pos": int(note["position"]),
			"start": float(note["start"]),
			"end": float(note["end"]),
		})

	for a_i in range(longs.size()):
		var a: Dictionary = longs[a_i]
		for b_i in range(a_i + 1, longs.size()):
			var b: Dictionary = longs[b_i]
			if int(a["pos"]) != int(b["pos"]):
				continue
			# overlap if intervals overlap; touching ends OK
			if float(a["start"]) < float(b["end"]) and float(b["start"]) < float(a["end"]):
				return "overlapping long notes on position %d (notes %d and %d)" % [int(a["pos"]), int(a["i"]), int(b["i"])]
	return ""
