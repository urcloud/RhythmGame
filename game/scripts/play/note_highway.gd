class_name NoteHighway
extends Node3D

const LANE_X: Array[float] = [-2.4, 0.0, 2.4]
const LANE_WIDTH := 1.7
const NOTE_WIDTH := 1.55
const JUDGE_Z := 0.0
const SPAWN_Z := 28.0
const BASE_APPROACH_MS := 2000.0
const HIGHWAY_WIDTH := 7.6

var scroll_speed: float = 1.0
var _note_nodes: Dictionary = {} # note_index -> MeshInstance3D
var _materials: Array[StandardMaterial3D] = []
var _lane_colors: Array[Color] = [
	Color(0.35, 0.75, 1.0),
	Color(1.0, 0.45, 0.6),
	Color(1.0, 0.85, 0.3),
]
## note_index -> { locked_z, fade, good }
var _resolved: Dictionary = {}
var _effects: Array = [] # { node, age, lifetime, base_scale }


func _ready() -> void:
	_build_highway()
	_materials = [
		_make_mat(_lane_colors[0]),
		_make_mat(_lane_colors[1]),
		_make_mat(_lane_colors[2]),
	]


func setup_notes(notes: Array, timing: Timing) -> void:
	for child in get_children():
		if child.has_meta("note_index") or child.has_meta("hit_fx"):
			child.queue_free()
	_note_nodes.clear()
	_resolved.clear()
	_effects.clear()

	for i in range(notes.size()):
		var note: Dictionary = notes[i]
		var lane := int(note["position"])
		var node := MeshInstance3D.new()
		node.set_meta("note_index", i)
		node.set_meta("lane", lane)
		node.set_meta("type", str(note["type"]))
		node.set_meta("start_ms", timing.beat_to_ms(float(note["start"])))
		if str(note["type"]) == "long":
			node.set_meta("end_ms", timing.beat_to_ms(float(note["end"])))
			var box := BoxMesh.new()
			box.size = Vector3(NOTE_WIDTH, 0.22, 1.0)
			node.mesh = box
		else:
			var box2 := BoxMesh.new()
			box2.size = Vector3(NOTE_WIDTH, 0.28, 0.5)
			node.mesh = box2
		node.material_override = _materials[lane]
		add_child(node)
		_note_nodes[i] = node


func update_visuals(now_ms: float) -> void:
	var approach := BASE_APPROACH_MS / maxf(scroll_speed, 0.05)
	for idx in _note_nodes.keys():
		var node: MeshInstance3D = _note_nodes[idx]
		if not is_instance_valid(node):
			continue
		if not node.visible and _resolved.has(idx):
			continue

		var lane: int = node.get_meta("lane")
		var start_ms: float = node.get_meta("start_ms")
		var ntype: String = node.get_meta("type")
		var x: float = LANE_X[lane]

		if _resolved.has(idx):
			var state: Dictionary = _resolved[idx]
			if bool(state.get("good", false)):
				# Keep successful notes at/above the judge line, then fade out.
				state["fade"] = float(state.get("fade", 1.0)) - 0.045
				var fade: float = float(state["fade"])
				_resolved[idx] = state
				if fade <= 0.0:
					node.visible = false
					continue
				node.visible = true
				node.position = Vector3(x, 0.18, JUDGE_Z)
				var mat := node.material_override as StandardMaterial3D
				if mat:
					var c := mat.albedo_color
					c.a = clampf(fade, 0.0, 1.0)
					mat.albedo_color = c
					mat.emission_energy_multiplier = 1.6 * fade
				continue
			# Miss: allow natural scroll below, then hide.
			pass

		if ntype == "single":
			var z := _time_to_z(start_ms, now_ms, approach)
			node.visible = z > JUDGE_Z - 1.2 and z < SPAWN_Z + 2.0
			node.position = Vector3(x, 0.18, z)
		else:
			var end_ms: float = node.get_meta("end_ms")
			var z_start := _time_to_z(start_ms, now_ms, approach)
			var z_end := _time_to_z(end_ms, now_ms, approach)
			# Successful long head: clamp near side to judge line while still holding.
			if _resolved.has(idx) and bool(_resolved[idx].get("long_head_good", false)):
				z_start = maxf(z_start, JUDGE_Z)
			var z_far := maxf(z_start, z_end)
			var z_near := minf(z_start, z_end)
			var length := maxf(0.25, z_far - z_near)
			var mesh := node.mesh as BoxMesh
			if mesh:
				mesh.size = Vector3(NOTE_WIDTH, 0.22, length)
			node.visible = z_far > JUDGE_Z - 1.2 and z_near < SPAWN_Z + 2.0
			node.position = Vector3(x, 0.15, (z_far + z_near) * 0.5)

	_update_effects()


func resolve_note(note_index: int, lane: int, grade: Judge.Grade, is_long_release: bool = false) -> void:
	var good := grade != Judge.Grade.MISS
	# Only successful hits get judge-line VFX (not auto-miss when notes pass).
	if good:
		play_judge_effect(lane, grade)

	if not _note_nodes.has(note_index):
		return
	var node: MeshInstance3D = _note_nodes[note_index]
	if not is_instance_valid(node):
		return

	var ntype: String = str(node.get_meta("type"))
	if ntype == "long" and not is_long_release:
		# Long start judged: lock head at judge line; body keeps scrolling until end.
		if good:
			_resolved[note_index] = {"good": false, "long_head_good": true, "fade": 1.0}
		return

	if good:
		# Duplicate material so fade doesn't affect other notes on same lane.
		var src := node.material_override as StandardMaterial3D
		if src:
			node.material_override = src.duplicate()
		_resolved[note_index] = {"good": true, "fade": 1.0}
		node.position = Vector3(LANE_X[lane], 0.18, JUDGE_Z)
	else:
		_resolved[note_index] = {"good": false, "fade": 1.0}


func hide_note(note_index: int) -> void:
	if _note_nodes.has(note_index):
		var node: Node3D = _note_nodes[note_index]
		if is_instance_valid(node):
			node.visible = false


func play_press_effect(lane: int) -> void:
	if lane < 0 or lane > 2:
		return
	var color := _lane_colors[lane]
	# Soft pad flash under finger — weaker than judge hit FX.
	var flash := MeshInstance3D.new()
	flash.set_meta("hit_fx", true)
	var box := BoxMesh.new()
	box.size = Vector3(NOTE_WIDTH * 0.95, 0.06, 0.22)
	flash.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.4
	flash.material_override = mat
	flash.position = Vector3(LANE_X[lane], 0.14, JUDGE_Z)
	add_child(flash)
	_effects.append({"node": flash, "age": 0.0, "lifetime": 0.14, "base_scale": 1.0, "kind": "press"})
	flash_lane(lane, 1.6)


func play_judge_effect(lane: int, grade: Judge.Grade) -> void:
	if lane < 0 or lane > 2:
		return
	if grade == Judge.Grade.MISS:
		return
	var color := _effect_color(grade, lane)
	var energy := 3.2
	var lifetime := 0.34
	var scale0 := 1.2
	match grade:
		Judge.Grade.IYA:
			energy = 6.5
			lifetime = 0.48
			scale0 = 1.7
		Judge.Grade.HIHI:
			energy = 4.8
			lifetime = 0.4
			scale0 = 1.45
		Judge.Grade.ENG:
			energy = 3.4
			lifetime = 0.32
			scale0 = 1.2

	# Strong horizontal burst on judge line
	var flash := MeshInstance3D.new()
	flash.set_meta("hit_fx", true)
	var box := BoxMesh.new()
	box.size = Vector3(NOTE_WIDTH * 1.35, 0.2, 0.5)
	flash.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	flash.material_override = mat
	flash.position = Vector3(LANE_X[lane], 0.32, JUDGE_Z)
	add_child(flash)
	_effects.append({"node": flash, "age": 0.0, "lifetime": lifetime, "base_scale": scale0, "kind": "flash"})

	# Expanding ring
	var ring := MeshInstance3D.new()
	ring.set_meta("hit_fx", true)
	var ring_mesh := BoxMesh.new()
	ring_mesh.size = Vector3(0.45, 0.05, 0.45)
	ring.mesh = ring_mesh
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	rmat.emission_enabled = true
	rmat.emission = color
	rmat.emission_energy_multiplier = energy
	ring.material_override = rmat
	ring.position = Vector3(LANE_X[lane], 0.22, JUDGE_Z)
	add_child(ring)
	_effects.append({"node": ring, "age": 0.0, "lifetime": lifetime * 1.2, "base_scale": scale0, "kind": "ring"})

	# Vertical spark column for clearer hit feedback
	var spark := MeshInstance3D.new()
	spark.set_meta("hit_fx", true)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.18, 1.4, 0.18)
	spark.mesh = spark_mesh
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 1.0, 1.0).lerp(color, 0.4)
	smat.emission_energy_multiplier = energy * 1.1
	spark.material_override = smat
	spark.position = Vector3(LANE_X[lane], 0.9, JUDGE_Z)
	add_child(spark)
	_effects.append({"node": spark, "age": 0.0, "lifetime": lifetime * 0.85, "base_scale": scale0, "kind": "spark"})

	flash_lane(lane, energy * 0.55)


func flash_lane(lane: int, boost: float = 2.5) -> void:
	var marker := get_node_or_null("LaneFlash%d" % lane)
	if marker and marker is MeshInstance3D:
		var mat := (marker as MeshInstance3D).material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = boost
			get_tree().create_timer(0.1).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 0.35
			)


func _update_effects() -> void:
	var dt := get_process_delta_time()
	var remain: Array = []
	for fx in _effects:
		var node: MeshInstance3D = fx["node"]
		if not is_instance_valid(node):
			continue
		fx["age"] = float(fx["age"]) + dt
		var life: float = float(fx["lifetime"])
		var t: float = clampf(float(fx["age"]) / life, 0.0, 1.0)
		var fade := 1.0 - t
		var base: float = float(fx["base_scale"])
		match str(fx["kind"]):
			"ring":
				var s := base * (0.7 + t * 3.0)
				node.scale = Vector3(s, 1.0, s * 0.55)
			"spark":
				var sy := base * (1.0 + t * 1.8)
				node.scale = Vector3(1.0 - t * 0.5, sy, 1.0 - t * 0.5)
				node.position.y = 0.9 + t * 0.8
			"press":
				var s3 := base * (1.0 + t * 0.25)
				node.scale = Vector3(s3, 1.0, 1.0)
			_:
				var s2 := base * (1.0 + t * 0.55)
				node.scale = Vector3(s2, 1.0 + t * 1.2, 1.0)
		var mat := node.material_override as StandardMaterial3D
		if mat:
			var c := mat.albedo_color
			c.a = fade
			mat.albedo_color = c
			mat.emission_energy_multiplier = maxf(0.1, mat.emission_energy_multiplier * (0.92))
		if t < 1.0:
			remain.append(fx)
		else:
			node.queue_free()
	_effects = remain


func _effect_color(grade: Judge.Grade, lane: int) -> Color:
	match grade:
		Judge.Grade.IYA:
			return Color(1.0, 0.95, 0.55).lerp(_lane_colors[lane], 0.35)
		Judge.Grade.HIHI:
			return Color(0.7, 0.95, 1.0).lerp(_lane_colors[lane], 0.4)
		Judge.Grade.ENG:
			return Color(0.85, 0.75, 1.0).lerp(_lane_colors[lane], 0.35)
		_:
			return Color(0.55, 0.55, 0.6)


func _time_to_z(target_ms: float, now_ms: float, approach_ms: float) -> float:
	var t := (target_ms - now_ms) / approach_ms
	return JUDGE_Z + t * (SPAWN_Z - JUDGE_Z)


func _build_highway() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(HIGHWAY_WIDTH, 0.05, SPAWN_Z + 4.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_color = Color(0.12, 0.15, 0.22)
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -0.05, SPAWN_Z * 0.5)
	floor_mesh.name = "Floor"
	add_child(floor_mesh)

	for i in range(3):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(LANE_WIDTH, 0.02, SPAWN_Z + 2.0)
		line.mesh = lm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.22, 0.26, 0.34)
		mat.emission_enabled = true
		mat.emission = Color(0.25, 0.3, 0.4)
		mat.emission_energy_multiplier = 0.35
		line.material_override = mat
		line.position = Vector3(LANE_X[i], 0.0, SPAWN_Z * 0.5)
		line.name = "LaneFlash%d" % i
		add_child(line)

	var judge := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(HIGHWAY_WIDTH - 0.4, 0.1, 0.16)
	judge.mesh = jm
	var jmat := StandardMaterial3D.new()
	jmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	jmat.albedo_color = Color(0.95, 0.95, 1.0)
	jmat.emission_enabled = true
	jmat.emission = Color(0.8, 0.9, 1.0)
	jmat.emission_energy_multiplier = 1.4
	judge.material_override = jmat
	judge.position = Vector3(0, 0.06, JUDGE_Z)
	judge.name = "JudgeLine"
	add_child(judge)


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	return mat
