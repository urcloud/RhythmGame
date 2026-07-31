class_name ChartLoader
extends RefCounted


class ScanEntry:
	extends RefCounted
	var path: String = ""
	var ok: bool = false
	var error: String = ""
	var chart: ChartData = null


static func scan_directory(dir_path: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			var full := dir_path.path_join(file_name)
			results.append(load_chart(full))
		file_name = dir.get_next()
	dir.list_dir_end()
	results.sort_custom(func(a: ScanEntry, b: ScanEntry) -> bool:
		var at := a.chart.title if a.ok and a.chart else a.path.get_file()
		var bt := b.chart.title if b.ok and b.chart else b.path.get_file()
		return at.nocasecmp_to(bt) < 0
	)
	return results


static func load_chart(path: String) -> ScanEntry:
	var entry := ScanEntry.new()
	entry.path = path
	if not FileAccess.file_exists(path):
		entry.error = "file not found"
		return entry
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		entry.error = "cannot open file"
		return entry
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	var verr := ChartValidator.validate(parsed)
	if verr != "":
		entry.error = verr
		return entry

	var root: Dictionary = parsed
	var meta: Dictionary = root["meta"]
	var chart := ChartData.new()
	chart.path = path
	chart.format_version = int(root["formatVersion"])
	chart.title = str(meta["title"])
	chart.artist = str(meta["artist"])
	chart.bpm = float(meta["bpm"])
	chart.offset_beats = float(meta["offsetBeats"])
	chart.difficulty = int(meta["difficulty"])

	var audio_rel := str(meta["audio"])
	var chart_dir := path.get_base_dir()
	chart.audio_path = chart_dir.path_join(audio_rel).simplify_path()
	if not chart.audio_path.to_lower().ends_with(".mp3"):
		entry.error = "audio must be mp3"
		return entry
	if not FileAccess.file_exists(chart.audio_path):
		entry.error = "audio file missing: %s" % chart.audio_path
		return entry

	var notes: Array = root["notes"]
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var as_ := float(a["start"])
		var bs := float(b["start"])
		if as_ == bs:
			return int(a["position"]) < int(b["position"])
		return as_ < bs
	)
	chart.notes = notes
	entry.ok = true
	entry.chart = chart
	return entry


static func load_audio_stream(audio_path: String) -> AudioStreamMP3:
	var file := FileAccess.open(audio_path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	return stream
