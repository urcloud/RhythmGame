extends SceneTree

## Run: godot --path game --headless -s res://scripts/tools/headless_smoke.gd


func _initialize() -> void:
	# Autoloads are available after MainLoop initialization.
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures := 0
	failures += _test_sample_chart()
	failures += _test_scan_dir()
	failures += _test_score_math()
	failures += _test_validator_rejects()
	failures += _test_config_key_collision()
	if failures == 0:
		print("SMOKE OK")
		quit(0)
	else:
		printerr("SMOKE FAILED: %d" % failures)
		quit(1)


func _test_sample_chart() -> int:
	var project_root := ProjectSettings.globalize_path("res://").rstrip("/")
	var chart_path := project_root.path_join("../format/examples/sample.chart.json").simplify_path()
	var entry := ChartLoader.load_chart(chart_path)
	if not entry.ok:
		printerr("sample chart load failed: ", entry.error)
		return 1
	var c: ChartData = entry.chart
	if c.judgment_object_count() != 9:
		printerr("expected 9 judgment objects, got ", c.judgment_object_count())
		return 1
	if not FileAccess.file_exists(c.audio_path):
		printerr("audio missing: ", c.audio_path)
		return 1
	print("sample chart OK: ", c.title, " N=", c.judgment_object_count())
	return 0


func _test_scan_dir() -> int:
	var cfg := get_root().get_node_or_null("AppConfig")
	if cfg == null:
		printerr("AppConfig autoload missing")
		return 1
	var dir_path: String = cfg.resolve_chart_dir()
	var entries := ChartLoader.scan_directory(dir_path)
	if entries.is_empty():
		printerr("scan found no charts in ", dir_path)
		return 1
	var ok_count := 0
	for e in entries:
		if e.ok:
			ok_count += 1
	if ok_count < 1:
		printerr("no valid charts in scan")
		return 1
	print("scan OK: ", ok_count, " valid in ", dir_path)
	return 0


func _test_config_key_collision() -> int:
	var cfg := get_root().get_node_or_null("AppConfig")
	if cfg == null:
		printerr("AppConfig autoload missing")
		return 1
	var data: Dictionary = cfg.get_as_dict()
	data["lane1_keys"] = ["Q", "H"] # Q belongs to lane0
	var err: String = cfg.validate_candidate(data)
	if err == "":
		printerr("expected key collision rejection")
		return 1
	print("config collision OK: ", err)
	return 0


func _test_score_math() -> int:
	var pts := ScoreCalculator.perfect_points(9)
	var total := 0
	for p in pts:
		total += p
	if total != 1_000_000:
		printerr("perfect points sum != 1000000: ", total)
		return 1
	var all_iya := 0
	for p in pts:
		all_iya += ScoreCalculator.contribution(p, Judge.Grade.IYA)
	if all_iya != 1_000_000:
		printerr("all iya score != 1000000: ", all_iya)
		return 1
	print("score math OK")
	return 0


func _test_validator_rejects() -> int:
	var bad := {
		"formatVersion": 1,
		"meta": {
			"title": "t",
			"artist": "a",
			"audio": "x.wav",
			"bpm": 120,
			"offsetBeats": 0,
			"difficulty": 3,
		},
		"notes": [],
	}
	var err := ChartValidator.validate(bad)
	if err == "":
		printerr("expected non-mp3 rejection")
		return 1
	var dup := {
		"formatVersion": 1,
		"meta": {
			"title": "t",
			"artist": "a",
			"audio": "x.mp3",
			"bpm": 120,
			"offsetBeats": 0,
			"difficulty": 3,
		},
		"notes": [
			{"type": "single", "start": 1.0, "position": 0},
			{"type": "single", "start": 1.0, "position": 0},
		],
	}
	err = ChartValidator.validate(dup)
	if err == "":
		printerr("expected duplicate rejection")
		return 1
	var nested := {
		"formatVersion": 1,
		"meta": {
			"title": "t",
			"artist": "a",
			"audio": "x.mp3",
			"bpm": 120,
			"offsetBeats": 0,
			"difficulty": 3,
		},
		"notes": [
			{"type": "long", "start": 1.0, "end": 4.0, "position": 0},
			{"type": "single", "start": 2.0, "position": 0},
		],
	}
	err = ChartValidator.validate(nested)
	if err == "":
		printerr("expected nested-single rejection")
		return 1
	print("validator OK")
	return 0
