extends Node

const CONFIG_PATH := "user://config.json"
const DEFAULT_PATH := "res://config/default_config.json"

var chart_dir: String = "../format/examples"
var scroll_speed: float = 1.0
var judge_iya_ms: int = 45
var judge_hihi_ms: int = 90
var judge_eng_ms: int = 150
var lane0_keys: PackedStringArray = PackedStringArray()
var lane1_keys: PackedStringArray = PackedStringArray()
var lane2_keys: PackedStringArray = PackedStringArray()
var window_width: int = 1280
var window_height: int = 720
var fullscreen: bool = false

var _defaults: Dictionary = {}


func _ready() -> void:
	_defaults = _load_json_file(DEFAULT_PATH)
	_apply_dict(_defaults)
	if FileAccess.file_exists(CONFIG_PATH):
		var saved := _load_json_file(CONFIG_PATH)
		if not saved.is_empty():
			_apply_dict(saved)
	apply_window_settings()


func get_as_dict() -> Dictionary:
	return {
		"chart_dir": chart_dir,
		"scroll_speed": scroll_speed,
		"judge_iya_ms": judge_iya_ms,
		"judge_hihi_ms": judge_hihi_ms,
		"judge_eng_ms": judge_eng_ms,
		"lane0_keys": Array(lane0_keys),
		"lane1_keys": Array(lane1_keys),
		"lane2_keys": Array(lane2_keys),
		"window_width": window_width,
		"window_height": window_height,
		"fullscreen": fullscreen,
	}


func validate_candidate(data: Dictionary) -> String:
	var speed := float(data.get("scroll_speed", scroll_speed))
	if speed < 0.5 or speed > 3.0:
		return "scroll_speed must be between 0.5 and 3.0"
	# snap check: multiples of 0.05
	var steps := int(round(speed / 0.05))
	if absf(speed - steps * 0.05) > 0.001:
		return "scroll_speed must be a multiple of 0.05"

	var iya := int(data.get("judge_iya_ms", judge_iya_ms))
	var hihi := int(data.get("judge_hihi_ms", judge_hihi_ms))
	var eng := int(data.get("judge_eng_ms", judge_eng_ms))
	if not (0 < iya and iya < hihi and hihi < eng):
		return "judge windows must satisfy 0 < iya < hihi < eng"

	var l0 := _to_string_array(data.get("lane0_keys", lane0_keys))
	var l1 := _to_string_array(data.get("lane1_keys", lane1_keys))
	var l2 := _to_string_array(data.get("lane2_keys", lane2_keys))
	if l0.is_empty() or l1.is_empty() or l2.is_empty():
		return "each lane must have at least one key"

	var seen: Dictionary = {}
	for lane_idx in range(3):
		var keys: PackedStringArray = [l0, l1, l2][lane_idx]
		for k in keys:
			var uk := str(k).to_upper()
			if seen.has(uk):
				return "key '%s' is assigned to multiple lanes" % str(k)
			seen[uk] = lane_idx

	var w := int(data.get("window_width", window_width))
	var h := int(data.get("window_height", window_height))
	if w < 640 or h < 360:
		return "window size too small"

	return ""


func save_from_dict(data: Dictionary) -> String:
	var err := validate_candidate(data)
	if err != "":
		return err
	_apply_dict(data)
	scroll_speed = snappedf(scroll_speed, 0.05)
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return "failed to write config: %s" % FileAccess.get_open_error()
	file.store_string(JSON.stringify(get_as_dict(), "\t"))
	file.close()
	apply_window_settings()
	return ""


func reset_to_defaults() -> void:
	_apply_dict(_defaults)
	save_from_dict(get_as_dict())


func apply_window_settings() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(window_width, window_height))


func resolve_chart_dir() -> String:
	var project_root := ProjectSettings.globalize_path("res://").rstrip("/")
	if chart_dir.begins_with("/") or (chart_dir.length() > 2 and chart_dir[1] == ":"):
		return chart_dir
	return project_root.path_join(chart_dir).simplify_path()


func lane_keys(lane: int) -> PackedStringArray:
	match lane:
		0:
			return lane0_keys
		1:
			return lane1_keys
		2:
			return lane2_keys
		_:
			return PackedStringArray()


func _apply_dict(data: Dictionary) -> void:
	if data.has("chart_dir"):
		chart_dir = str(data["chart_dir"])
	if data.has("scroll_speed"):
		scroll_speed = float(data["scroll_speed"])
	if data.has("judge_iya_ms"):
		judge_iya_ms = int(data["judge_iya_ms"])
	if data.has("judge_hihi_ms"):
		judge_hihi_ms = int(data["judge_hihi_ms"])
	if data.has("judge_eng_ms"):
		judge_eng_ms = int(data["judge_eng_ms"])
	if data.has("lane0_keys"):
		lane0_keys = _to_string_array(data["lane0_keys"])
	if data.has("lane1_keys"):
		lane1_keys = _to_string_array(data["lane1_keys"])
	if data.has("lane2_keys"):
		lane2_keys = _to_string_array(data["lane2_keys"])
	if data.has("window_width"):
		window_width = int(data["window_width"])
	if data.has("window_height"):
		window_height = int(data["window_height"])
	if data.has("fullscreen"):
		fullscreen = bool(data["fullscreen"])


func _to_string_array(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is PackedStringArray:
		return value
	if value is Array:
		for v in value:
			out.append(str(v))
	return out


func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
