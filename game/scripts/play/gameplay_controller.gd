extends Node3D

@onready var highway: NoteHighway = $Highway
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var hud: CanvasLayer = $HUD
@onready var pause_overlay: Control = $HUD/PauseOverlay
@onready var score_label: Label = $HUD/ScoreLabel
@onready var combo_label: Label = $HUD/ComboLabel
@onready var judge_label: Label = $HUD/JudgeLabel
@onready var title_label: Label = $HUD/TitleLabel

var _chart: ChartData
var _timing: Timing
var _inputs: InputLanes
var _objects: Array = []
var _perfects: PackedInt32Array
var _pending_by_lane: Array = [[], [], []] # queues of object indices still open
var _object_states: Array = [] # judged or not
var _active_long_release: Dictionary = {} # lane -> object order index waiting release
var _score: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _counts := {"이야!": 0, "히히": 0, "엥...": 0, "Miss": 0}
var _paused: bool = false
var _started: bool = false
var _finished: bool = false
var _audio_length_ms: float = 0.0
var _judge_fade_t: float = 0.0


func _ready() -> void:
	pause_overlay.visible = false
	_inputs = InputLanes.new()
	_inputs.lane_pressed.connect(_on_lane_pressed)
	_inputs.lane_released.connect(_on_lane_released)
	_inputs.configure(AppConfig.lane0_keys, AppConfig.lane1_keys, AppConfig.lane2_keys)

	var path := SceneRouter.pending_chart_path
	if path.is_empty():
		SceneRouter.go_song_select()
		return
	var entry := ChartLoader.load_chart(path)
	if not entry.ok:
		push_error(entry.error)
		SceneRouter.go_song_select()
		return
	_chart = entry.chart
	_timing = Timing.new(_chart.bpm, _chart.offset_beats)
	title_label.text = "%s — %s" % [_chart.title, _chart.artist]

	_objects = ScoreCalculator.build_judgment_objects(_chart.notes, _timing)
	_perfects = ScoreCalculator.perfect_points(_objects.size())
	_object_states.resize(_objects.size())
	for i in range(_objects.size()):
		_object_states[i] = false
		var obj: Dictionary = _objects[i]
		# only "hit" objects enter lane queues; releases tracked via active long
		if str(obj["kind"]) == "hit":
			_pending_by_lane[int(obj["lane"])].append(i)

	highway.scroll_speed = AppConfig.scroll_speed
	highway.setup_notes(_chart.notes, _timing)

	var stream := ChartLoader.load_audio_stream(_chart.audio_path)
	if stream == null:
		push_error("failed to load audio")
		SceneRouter.go_song_select()
		return
	audio_player.stream = stream
	_audio_length_ms = stream.get_length() * 1000.0
	audio_player.play()
	_started = true
	_update_hud()


func _process(delta: float) -> void:
	if not _started or _finished:
		return
	if _paused:
		return

	var now := _now_ms()
	highway.update_visuals(now)
	_auto_miss(now)

	if _judge_fade_t > 0.0:
		_judge_fade_t -= delta
		judge_label.modulate.a = clampf(_judge_fade_t / 0.4, 0.0, 1.0)

	if now >= _audio_length_ms + float(AppConfig.judge_eng_ms) + 200.0:
		_finish_song()


func _unhandled_input(event: InputEvent) -> void:
	if _inputs == null:
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused or _finished:
		return
	_inputs.handle_event(event)


func _toggle_pause() -> void:
	if _finished:
		return
	_paused = not _paused
	pause_overlay.visible = _paused
	if _paused:
		audio_player.stream_paused = true
	else:
		audio_player.stream_paused = false


func _now_ms() -> float:
	return audio_player.get_playback_position() * 1000.0


func _on_lane_pressed(lane: int) -> void:
	highway.flash_lane(lane)
	var now := _now_ms()
	var idx := _find_nearest_pending_hit(lane, now)
	if idx >= 0:
		var obj: Dictionary = _objects[idx]
		var target: float = float(obj["time_ms"])
		var dt := absf(now - target)
		var grade := Judge.grade_from_delta(dt, AppConfig.judge_iya_ms, AppConfig.judge_hihi_ms, AppConfig.judge_eng_ms)
		if grade == Judge.Grade.MISS and now < target:
			# too early outside window: ignore (don't consume)
			if now < target - float(AppConfig.judge_eng_ms):
				return
		_resolve_object(idx, grade)
		if bool(obj["is_long"]) and str(obj["kind"]) == "hit":
			var release_idx := _find_release_for_note(int(obj["note_index"]))
			if release_idx >= 0 and not _object_states[release_idx]:
				_active_long_release[lane] = release_idx
		return

	# After a long start was already judged (including Miss), a later press can arm the release.
	var arm_idx := _find_armable_release(lane, now)
	if arm_idx >= 0:
		_active_long_release[lane] = arm_idx


func _on_lane_released(lane: int) -> void:
	if not _active_long_release.has(lane):
		return
	var idx: int = _active_long_release[lane]
	_active_long_release.erase(lane)
	if _object_states[idx]:
		return
	var obj: Dictionary = _objects[idx]
	var end_ms: float = float(obj["time_ms"])
	var now := _now_ms()
	# Early release before end beat => Miss
	if now < end_ms:
		_resolve_object(idx, Judge.Grade.MISS)
		return
	var dt := absf(now - end_ms)
	var grade := Judge.grade_from_delta(dt, AppConfig.judge_iya_ms, AppConfig.judge_hihi_ms, AppConfig.judge_eng_ms)
	_resolve_object(idx, grade)


func _find_nearest_pending_hit(lane: int, now: float) -> int:
	var queue: Array = _pending_by_lane[lane]
	var best := -1
	var best_dt := INF
	var window := float(AppConfig.judge_eng_ms)
	for i in range(queue.size()):
		var idx: int = queue[i]
		if _object_states[idx]:
			continue
		var t: float = float(_objects[idx]["time_ms"])
		var dt := absf(now - t)
		if dt <= window and dt < best_dt:
			best_dt = dt
			best = idx
	return best


func _find_release_for_note(note_index: int) -> int:
	for i in range(_objects.size()):
		var obj: Dictionary = _objects[i]
		if int(obj["note_index"]) == note_index and str(obj["kind"]) == "release":
			return i
	return -1


func _find_hit_for_note(note_index: int) -> int:
	for i in range(_objects.size()):
		var obj: Dictionary = _objects[i]
		if int(obj["note_index"]) == note_index and str(obj["kind"]) == "hit":
			return i
	return -1


func _find_armable_release(lane: int, now: float) -> int:
	var eng := float(AppConfig.judge_eng_ms)
	var best := -1
	var best_t := INF
	for i in range(_objects.size()):
		if _object_states[i]:
			continue
		var obj: Dictionary = _objects[i]
		if str(obj["kind"]) != "release" or int(obj["lane"]) != lane:
			continue
		var hit_idx := _find_hit_for_note(int(obj["note_index"]))
		if hit_idx < 0 or not _object_states[hit_idx]:
			continue
		var end_ms: float = float(obj["time_ms"])
		if now > end_ms + eng:
			continue
		if end_ms < best_t:
			best_t = end_ms
			best = i
	return best


func _auto_miss(now: float) -> void:
	var eng := float(AppConfig.judge_eng_ms)
	for lane in range(3):
		var queue: Array = _pending_by_lane[lane]
		for idx in queue:
			if _object_states[idx]:
				continue
			var t: float = float(_objects[idx]["time_ms"])
			if now > t + eng:
				_resolve_object(idx, Judge.Grade.MISS)

	# Late release misses (held or never armed after start Miss)
	for i in range(_objects.size()):
		if _object_states[i]:
			continue
		var obj: Dictionary = _objects[i]
		if str(obj["kind"]) != "release":
			continue
		var end_ms: float = float(obj["time_ms"])
		if now > end_ms + eng:
			var lane := int(obj["lane"])
			if _active_long_release.get(lane, -1) == i:
				_active_long_release.erase(lane)
			_resolve_object(i, Judge.Grade.MISS)


func _resolve_object(idx: int, grade: Judge.Grade) -> void:
	if idx < 0 or idx >= _objects.size() or _object_states[idx]:
		return
	_object_states[idx] = true
	var order: int = int(_objects[idx]["order"])
	var perfect := 0
	if order >= 0 and order < _perfects.size():
		perfect = _perfects[order]
	var gained := ScoreCalculator.contribution(perfect, grade)
	_score += gained

	var label := Judge.label(grade)
	_counts[label] = int(_counts.get(label, 0)) + 1
	if grade == Judge.Grade.MISS:
		_combo = 0
	else:
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)

	judge_label.text = label
	_judge_fade_t = 0.6
	judge_label.modulate.a = 1.0
	_update_hud()

	var obj: Dictionary = _objects[idx]
	if str(obj["kind"]) == "hit" and not bool(obj["is_long"]):
		highway.hide_note(int(obj["note_index"]))
	elif str(obj["kind"]) == "release":
		highway.hide_note(int(obj["note_index"]))

	# remove from pending queue
	if str(obj["kind"]) == "hit":
		var lane := int(obj["lane"])
		_pending_by_lane[lane].erase(idx)

	if _all_judged() and _now_ms() >= _audio_length_ms:
		_finish_song()


func _all_judged() -> bool:
	for judged in _object_states:
		if not judged:
			return false
	return true


func _update_hud() -> void:
	score_label.text = "%07d" % _score
	combo_label.text = str(_combo) if _combo > 0 else ""


func _finish_song() -> void:
	if _finished:
		return
	_finished = true
	# miss any remaining
	for i in range(_object_states.size()):
		if not _object_states[i]:
			_resolve_object(i, Judge.Grade.MISS)
	audio_player.stop()
	SceneRouter.go_result({
		"title": _chart.title,
		"artist": _chart.artist,
		"score": _score,
		"max_combo": _max_combo,
		"counts": _counts.duplicate(),
	})


func _on_resume_pressed() -> void:
	if _paused:
		_toggle_pause()


func _on_quit_pressed() -> void:
	audio_player.stop()
	SceneRouter.go_song_select()
