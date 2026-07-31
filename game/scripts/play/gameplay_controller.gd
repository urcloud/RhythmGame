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
## lane -> last press time_ms (consumed when used for a hit)
var _press_buffer_ms: Array = [NAN, NAN, NAN]
var _score: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _counts := {"이야!": 0, "히히": 0, "엥...": 0, "Miss": 0}
var _paused: bool = false
var _started: bool = false
var _finished: bool = false
var _audio_length_ms: float = 0.0
var _audio_ended: bool = false
var _post_audio_ms: float = 0.0
var _judge_fade_t: float = 0.0
var _tat_player: AudioStreamPlayer


func _ready() -> void:
	pause_overlay.visible = false
	_tat_player = AudioStreamPlayer.new()
	_tat_player.name = "TatSfxPlayer"
	_tat_player.stream = HitSfx.make_tat_stream()
	_tat_player.volume_db = -10.0
	_tat_player.max_polyphony = 8
	_tat_player.bus = "Master"
	add_child(_tat_player)
	# Look down the highway (+Z): notes approach from far (SPAWN_Z) to judge (0).
	var cam := $Camera3D as Camera3D
	if cam:
		cam.global_position = Vector3(0.0, 6.2, -8.2)
		cam.look_at(Vector3(0.0, 0.0, 14.0), Vector3.UP)
		cam.fov = 62.0
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
	if not audio_player.finished.is_connected(_on_audio_finished):
		audio_player.finished.connect(_on_audio_finished)
	_audio_ended = false
	_post_audio_ms = 0.0
	audio_player.play()
	_started = true
	_update_hud()


func _on_audio_finished() -> void:
	_audio_ended = true


func _process(delta: float) -> void:
	if not _started or _finished:
		return
	if _paused:
		return

	# Playback position freezes when the stream ends; keep a virtual clock so
	# late auto-miss / finish thresholds can still be reached.
	if _audio_ended or not audio_player.playing:
		_audio_ended = true
		_post_audio_ms += delta * 1000.0

	var now := _now_ms()
	highway.update_visuals(now)
	_try_buffered_hits(now)
	_auto_miss(now)

	if _judge_fade_t > 0.0:
		_judge_fade_t -= delta
		judge_label.modulate.a = clampf(_judge_fade_t / 0.4, 0.0, 1.0)

	var end_grace := float(AppConfig.judge_eng_ms) + 200.0
	if now >= _audio_length_ms + end_grace or (_audio_ended and _post_audio_ms >= end_grace):
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
	var raw: float
	if _audio_ended:
		raw = _audio_length_ms + _post_audio_ms
	else:
		raw = audio_player.get_playback_position() * 1000.0
	var latency_ms := AudioServer.get_output_latency() * 1000.0
	return raw + float(AppConfig.audio_offset_ms) + latency_ms


func _on_lane_pressed(lane: int) -> void:
	# Always give press feedback — soft "탓" layered on the music.
	highway.play_press_effect(lane)
	_play_tat()
	var now := _now_ms()
	_press_buffer_ms[lane] = now
	if _try_hit_lane(lane, now, true):
		return

	# After a long start was already judged (including Miss), a later press can arm the release.
	var arm_idx := _find_armable_release(lane, now)
	if arm_idx >= 0:
		_active_long_release[lane] = arm_idx
		# Holding for release must not auto-hit a later note via the press buffer.
		_press_buffer_ms[lane] = NAN


func _play_tat() -> void:
	if _tat_player == null or _tat_player.stream == null:
		return
	_tat_player.pitch_scale = randf_range(0.96, 1.06)
	_tat_player.play()


func _on_lane_released(lane: int) -> void:
	_press_buffer_ms[lane] = NAN
	if not _active_long_release.has(lane):
		return
	var idx: int = _active_long_release[lane]
	_active_long_release.erase(lane)
	if _object_states[idx]:
		return
	var obj: Dictionary = _objects[idx]
	var end_ms: float = float(obj["time_ms"])
	var now := _now_ms()
	var eng := float(AppConfig.judge_eng_ms)
	# Too early outside the window: break hold => Miss
	if now < end_ms - eng:
		_resolve_object(idx, Judge.Grade.MISS)
		return
	var dt := absf(now - end_ms)
	var grade := Judge.grade_from_delta(dt, AppConfig.judge_iya_ms, AppConfig.judge_hihi_ms, AppConfig.judge_eng_ms)
	_resolve_object(idx, grade)


func _try_buffered_hits(now: float) -> void:
	for lane in range(3):
		if _active_long_release.has(lane):
			continue
		if is_nan(float(_press_buffer_ms[lane])):
			continue
		if not _inputs.is_lane_held(lane):
			_press_buffer_ms[lane] = NAN
			continue
		_try_hit_lane(lane, now, false)


## Attempt to judge a pending hit using press buffer and/or current time.
## Returns true if a hit object was consumed.
func _try_hit_lane(lane: int, now: float, from_press: bool) -> bool:
	var press_t: float = float(_press_buffer_ms[lane])
	if is_nan(press_t):
		if from_press:
			press_t = now
		else:
			return false

	var idx := _find_best_pending_hit(lane, now, press_t, from_press)
	if idx < 0:
		return false

	var obj: Dictionary = _objects[idx]
	var target: float = float(obj["time_ms"])
	var sample: float
	if from_press:
		sample = now
	elif press_t <= target:
		# Early press held through: wait until note time, then count as on-time.
		if now < target:
			return false
		sample = target
	else:
		# Press was after the note (late buffer); use press time.
		sample = press_t

	var dt := absf(sample - target)
	var grade := Judge.grade_from_delta(dt, AppConfig.judge_iya_ms, AppConfig.judge_hihi_ms, AppConfig.judge_eng_ms)
	if grade == Judge.Grade.MISS:
		return false

	_press_buffer_ms[lane] = NAN
	_resolve_object(idx, grade)
	if bool(obj["is_long"]) and str(obj["kind"]) == "hit":
		var release_idx := _find_release_for_note(int(obj["note_index"]))
		if release_idx >= 0 and not _object_states[release_idx]:
			_active_long_release[lane] = release_idx
	return true


func _find_best_pending_hit(lane: int, now: float, press_t: float, from_press: bool) -> int:
	var queue: Array = _pending_by_lane[lane]
	var best := -1
	var best_dt := INF
	var window := float(AppConfig.judge_eng_ms)
	for i in range(queue.size()):
		var idx: int = queue[i]
		if _object_states[idx]:
			continue
		var t: float = float(_objects[idx]["time_ms"])
		var dt: float
		if from_press:
			dt = absf(now - t)
		elif press_t <= t:
			# Held from before the note: eligible once we reach the note time.
			if now < t:
				continue
			dt = 0.0
		else:
			dt = absf(press_t - t)
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
	var lane := int(obj["lane"])
	var is_release := str(obj["kind"]) == "release"
	highway.resolve_note(int(obj["note_index"]), lane, grade, is_release)

	# remove from pending queue
	if str(obj["kind"]) == "hit":
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
