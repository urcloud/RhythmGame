class_name InputLanes
extends RefCounted

signal lane_pressed(lane: int)
signal lane_released(lane: int)

var _key_to_lane: Dictionary = {}
var _lane_down_count: Array[int] = [0, 0, 0]
var _held_keys: Dictionary = {} # keycode -> true


func configure(lane0: PackedStringArray, lane1: PackedStringArray, lane2: PackedStringArray) -> void:
	_key_to_lane.clear()
	_lane_down_count = [0, 0, 0]
	_held_keys.clear()
	_bind_keys(lane0, 0)
	_bind_keys(lane1, 1)
	_bind_keys(lane2, 2)


func handle_event(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	var code := key_event.physical_keycode
	if code == KEY_NONE:
		code = key_event.keycode
	if not _key_to_lane.has(code):
		return
	var lane: int = _key_to_lane[code]
	if key_event.pressed:
		if _held_keys.has(code):
			return
		_held_keys[code] = true
		_lane_down_count[lane] += 1
		if _lane_down_count[lane] == 1:
			lane_pressed.emit(lane)
	else:
		if not _held_keys.has(code):
			return
		_held_keys.erase(code)
		_lane_down_count[lane] = maxi(0, _lane_down_count[lane] - 1)
		if _lane_down_count[lane] == 0:
			lane_released.emit(lane)


func is_lane_held(lane: int) -> bool:
	return lane >= 0 and lane < 3 and _lane_down_count[lane] > 0


func _bind_keys(keys: PackedStringArray, lane: int) -> void:
	for k in keys:
		var code := key_name_to_keycode(str(k))
		if code != KEY_NONE:
			_key_to_lane[code] = lane


static func key_name_to_keycode(name: String) -> Key:
	var n := name.strip_edges()
	if n.length() == 1:
		var ch := n.to_upper()
		match ch:
			"A": return KEY_A
			"B": return KEY_B
			"C": return KEY_C
			"D": return KEY_D
			"E": return KEY_E
			"F": return KEY_F
			"G": return KEY_G
			"H": return KEY_H
			"I": return KEY_I
			"J": return KEY_J
			"K": return KEY_K
			"L": return KEY_L
			"M": return KEY_M
			"N": return KEY_N
			"O": return KEY_O
			"P": return KEY_P
			"Q": return KEY_Q
			"R": return KEY_R
			"S": return KEY_S
			"T": return KEY_T
			"U": return KEY_U
			"V": return KEY_V
			"W": return KEY_W
			"X": return KEY_X
			"Y": return KEY_Y
			"Z": return KEY_Z
			"[": return KEY_BRACKETLEFT
			"]": return KEY_BRACKETRIGHT
			";": return KEY_SEMICOLON
			"'": return KEY_APOSTROPHE
			",": return KEY_COMMA
			".": return KEY_PERIOD
			"/": return KEY_SLASH
	match n.to_upper():
		"BRACKETLEFT", "LEFTBRACKET": return KEY_BRACKETLEFT
		"BRACKETRIGHT", "RIGHTBRACKET": return KEY_BRACKETRIGHT
		"SEMICOLON": return KEY_SEMICOLON
		"APOSTROPHE", "QUOTE": return KEY_APOSTROPHE
		"COMMA": return KEY_COMMA
		"PERIOD": return KEY_PERIOD
		"SLASH": return KEY_SLASH
	return KEY_NONE


static func keycode_to_name(code: Key) -> String:
	match code:
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_SEMICOLON: return ";"
		KEY_APOSTROPHE: return "'"
		KEY_COMMA: return ","
		KEY_PERIOD: return "."
		KEY_SLASH: return "/"
		_:
			if code >= KEY_A and code <= KEY_Z:
				return char(code)
			return OS.get_keycode_string(code)
