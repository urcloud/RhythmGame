class_name NoteHighway
extends Node3D

# Screen-left → screen-right for position 0/1/2.
# Camera looks toward +Z, so its local +X is world -X; world +X appears on the left.
const LANE_X: Array[float] = [2.4, 0.0, -2.4]
const LANE_WIDTH := 1.7
const NOTE_WIDTH := 1.55
const LONG_BODY_WIDTH := 1.05
const SINGLE_DEPTH := 0.48
const HEAD_DEPTH := 0.58
const TAIL_DEPTH := 0.4
const JUDGE_Z := 0.0
const SPAWN_Z := 28.0
const BASE_APPROACH_MS := 2000.0
const HIGHWAY_WIDTH := 7.6

var scroll_speed: float = 1.0
var _note_nodes: Dictionary = {} # note_index -> Node3D
# Saturated note hues against a neutral dark stage.
var _lane_colors: Array[Color] = [
	Color(0.2, 0.82, 1.0),
	Color(1.0, 0.42, 0.68),
	Color(1.0, 0.82, 0.28),
]
## note_index -> { locked_z, fade, good }
var _resolved: Dictionary = {}
var _effects: Array = []
var _floor_mat: ShaderMaterial
var _backdrop_mat: ShaderMaterial
var _rail_mats: Array[ShaderMaterial] = []
var _ambient_t: float = 0.0
var _lane_boost: Array[float] = [0.2, 0.2, 0.2]
var _judge_pulse: float = 0.0


func _ready() -> void:
	_build_highway()


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
		var color := _lane_colors[lane]
		var root := Node3D.new()
		root.set_meta("note_index", i)
		root.set_meta("lane", lane)
		root.set_meta("type", str(note["type"]))
		root.set_meta("start_ms", timing.beat_to_ms(float(note["start"])))
		if str(note["type"]) == "long":
			root.set_meta("end_ms", timing.beat_to_ms(float(note["end"])))
			_build_long_note(root, color)
		else:
			_build_single_note(root, color)
		add_child(root)
		_note_nodes[i] = root


func _build_single_note(root: Node3D, color: Color) -> void:
	# Dark chassis gives volume; colored plate + chrome rim read as a physical key.
	var chassis := MeshInstance3D.new()
	chassis.name = "Chassis"
	var cbox := BoxMesh.new()
	cbox.size = Vector3(NOTE_WIDTH * 1.02, 0.2, SINGLE_DEPTH * 1.02)
	chassis.mesh = cbox
	chassis.material_override = _make_mat(Color(0.08, 0.09, 0.12), 0.35)
	chassis.position = Vector3(0.0, 0.14, 0.0)
	root.add_child(chassis)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(NOTE_WIDTH * 0.92, 0.22, SINGLE_DEPTH * 0.86)
	body.mesh = box
	body.material_override = _make_mat(color, 1.55)
	body.position = Vector3(0.0, 0.3, 0.0)
	root.add_child(body)

	# Top specular strip — cheap plastic → molded keycap feel.
	var top := MeshInstance3D.new()
	top.name = "Top"
	var tbox := BoxMesh.new()
	tbox.size = Vector3(NOTE_WIDTH * 0.78, 0.04, SINGLE_DEPTH * 0.55)
	top.mesh = tbox
	top.material_override = _make_mat(Color(1.0, 1.0, 1.0).lerp(color, 0.35), 2.1)
	top.position = Vector3(0.0, 0.42, 0.02)
	root.add_child(top)

	for side in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		var rbox := BoxMesh.new()
		rbox.size = Vector3(0.07, 0.34, SINGLE_DEPTH * 0.95)
		rim.mesh = rbox
		rim.material_override = _make_mat(Color(0.92, 0.95, 1.0), 1.8)
		rim.position = Vector3(side * NOTE_WIDTH * 0.48, 0.28, 0.0)
		root.add_child(rim)

	var lip := MeshInstance3D.new()
	lip.name = "Lip"
	var lip_box := BoxMesh.new()
	lip_box.size = Vector3(NOTE_WIDTH * 1.05, 0.1, 0.1)
	lip.mesh = lip_box
	lip.material_override = _make_mat(Color(1.0, 1.0, 1.0), 2.4)
	lip.position = Vector3(0.0, 0.38, -SINGLE_DEPTH * 0.5 + 0.05)
	root.add_child(lip)


func _build_long_note(root: Node3D, color: Color) -> void:
	# Patterned hold ribbon — high contrast vs dark deck.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_box := BoxMesh.new()
	body_box.size = Vector3(LONG_BODY_WIDTH, 0.18, 1.0)
	body.mesh = body_box
	var hold_shader := load("res://shaders/hold_trail.gdshader") as Shader
	var hold_mat := ShaderMaterial.new()
	hold_mat.shader = hold_shader
	hold_mat.set_shader_parameter("base_color", color)
	hold_mat.set_shader_parameter("stripe_color", Color(0.97, 0.99, 1.0))
	hold_mat.set_shader_parameter("energy", 1.45)
	hold_mat.set_shader_parameter("stripe_freq", 2.4)
	body.material_override = hold_mat
	root.add_child(body)

	# Bright center spine.
	var core := MeshInstance3D.new()
	core.name = "Core"
	var core_box := BoxMesh.new()
	core_box.size = Vector3(LONG_BODY_WIDTH * 0.22, 0.26, 1.0)
	core.mesh = core_box
	core.material_override = _make_mat(Color(1.0, 1.0, 1.0).lerp(color, 0.25), 2.0)
	root.add_child(core)

	# Chrome side rails so the hold silhouette never melts into the lane.
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.name = "Rail%s" % ("L" if side < 0.0 else "R")
		var rbox := BoxMesh.new()
		rbox.size = Vector3(0.08, 0.28, 1.0)
		rail.mesh = rbox
		rail.material_override = _make_mat(Color(0.9, 0.94, 1.0), 1.6)
		root.add_child(rail)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_box := BoxMesh.new()
	head_box.size = Vector3(NOTE_WIDTH, 0.36, HEAD_DEPTH)
	head.mesh = head_box
	head.material_override = _make_mat(color, 1.7)
	root.add_child(head)

	var head_rim_l := MeshInstance3D.new()
	head_rim_l.name = "HeadRimL"
	var hrl := BoxMesh.new()
	hrl.size = Vector3(0.07, 0.4, HEAD_DEPTH * 0.95)
	head_rim_l.mesh = hrl
	head_rim_l.material_override = _make_mat(Color(0.95, 0.97, 1.0), 1.9)
	root.add_child(head_rim_l)

	var head_rim_r := MeshInstance3D.new()
	head_rim_r.name = "HeadRimR"
	var hrr := BoxMesh.new()
	hrr.size = Vector3(0.07, 0.4, HEAD_DEPTH * 0.95)
	head_rim_r.mesh = hrr
	head_rim_r.material_override = _make_mat(Color(0.95, 0.97, 1.0), 1.9)
	root.add_child(head_rim_r)

	var head_lip := MeshInstance3D.new()
	head_lip.name = "HeadLip"
	var hl := BoxMesh.new()
	hl.size = Vector3(NOTE_WIDTH * 1.05, 0.1, 0.1)
	head_lip.mesh = hl
	head_lip.material_override = _make_mat(Color(1.0, 1.0, 1.0), 2.4)
	root.add_child(head_lip)

	var tail := MeshInstance3D.new()
	tail.name = "Tail"
	var tail_box := BoxMesh.new()
	tail_box.size = Vector3(NOTE_WIDTH * 0.92, 0.3, TAIL_DEPTH)
	tail.mesh = tail_box
	tail.material_override = _make_mat(color.lightened(0.15), 1.5)
	root.add_child(tail)

	var tail_cap := MeshInstance3D.new()
	tail_cap.name = "TailCap"
	var tcap := BoxMesh.new()
	tcap.size = Vector3(NOTE_WIDTH * 0.98, 0.08, 0.08)
	tail_cap.mesh = tcap
	tail_cap.material_override = _make_mat(Color(1.0, 1.0, 1.0), 2.0)
	root.add_child(tail_cap)


func update_visuals(now_ms: float) -> void:
	var approach := BASE_APPROACH_MS / maxf(scroll_speed, 0.05)
	_ambient_t += get_process_delta_time()
	_update_ambient()

	for idx in _note_nodes.keys():
		var node: Node3D = _note_nodes[idx]
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
				state["fade"] = float(state.get("fade", 1.0)) - 0.045
				var fade: float = float(state["fade"])
				_resolved[idx] = state
				if fade <= 0.0:
					node.visible = false
					continue
				node.visible = true
				node.position = Vector3(x, 0.0, JUDGE_Z)
				_fade_note_materials(node, fade)
				continue

		if ntype == "single":
			var z := _time_to_z(start_ms, now_ms, approach) + SINGLE_DEPTH * 0.5
			node.visible = z > JUDGE_Z - 1.2 and z < SPAWN_Z + 2.0
			node.position = Vector3(x, 0.0, z)
		else:
			var end_ms: float = node.get_meta("end_ms")
			var z_start := _time_to_z(start_ms, now_ms, approach)
			var z_end := _time_to_z(end_ms, now_ms, approach)
			var holding := _resolved.has(idx) and bool(_resolved[idx].get("long_head_good", false))
			if holding:
				z_start = maxf(z_start, JUDGE_Z)
			var z_far := maxf(z_start, z_end)
			var z_near := minf(z_start, z_end)
			var length := maxf(HEAD_DEPTH + TAIL_DEPTH, z_far - z_near)
			node.visible = z_far > JUDGE_Z - 1.2 and z_near < SPAWN_Z + 2.0
			node.position = Vector3(x, 0.0, 0.0)
			_layout_long_parts(node, z_near, z_far, length)
			if holding:
				_pulse_hold_materials(node, lane)

	_update_effects()
	_decay_lane_boost()


func _layout_long_parts(root: Node3D, z_near: float, z_far: float, length: float) -> void:
	var body := root.get_node_or_null("Body") as MeshInstance3D
	var core := root.get_node_or_null("Core") as MeshInstance3D
	var rail_l := root.get_node_or_null("RailL") as MeshInstance3D
	var rail_r := root.get_node_or_null("RailR") as MeshInstance3D
	var head := root.get_node_or_null("Head") as MeshInstance3D
	var head_lip := root.get_node_or_null("HeadLip") as MeshInstance3D
	var head_rim_l := root.get_node_or_null("HeadRimL") as MeshInstance3D
	var head_rim_r := root.get_node_or_null("HeadRimR") as MeshInstance3D
	var tail := root.get_node_or_null("Tail") as MeshInstance3D
	var tail_cap := root.get_node_or_null("TailCap") as MeshInstance3D
	var body_len := maxf(0.25, length - HEAD_DEPTH * 0.3 - TAIL_DEPTH * 0.3)
	var body_z := (z_near + z_far) * 0.5

	if body:
		var mesh := body.mesh as BoxMesh
		if mesh:
			mesh.size = Vector3(LONG_BODY_WIDTH, 0.18, body_len)
		body.position = Vector3(0.0, 0.16, body_z)
	if core:
		var cmesh := core.mesh as BoxMesh
		if cmesh:
			cmesh.size = Vector3(LONG_BODY_WIDTH * 0.22, 0.26, body_len)
		core.position = Vector3(0.0, 0.22, body_z)
	for rail_side in [[rail_l, -1.0], [rail_r, 1.0]]:
		var rail: MeshInstance3D = rail_side[0]
		var side: float = rail_side[1]
		if rail:
			var rmesh := rail.mesh as BoxMesh
			if rmesh:
				rmesh.size = Vector3(0.08, 0.28, body_len)
			rail.position = Vector3(side * LONG_BODY_WIDTH * 0.52, 0.2, body_z)
	if head:
		head.position = Vector3(0.0, 0.28, z_near + HEAD_DEPTH * 0.5)
	if head_lip:
		head_lip.position = Vector3(0.0, 0.42, z_near + 0.05)
	if head_rim_l:
		head_rim_l.position = Vector3(-NOTE_WIDTH * 0.48, 0.3, z_near + HEAD_DEPTH * 0.5)
	if head_rim_r:
		head_rim_r.position = Vector3(NOTE_WIDTH * 0.48, 0.3, z_near + HEAD_DEPTH * 0.5)
	if tail:
		tail.position = Vector3(0.0, 0.24, z_far - TAIL_DEPTH * 0.5)
	if tail_cap:
		tail_cap.position = Vector3(0.0, 0.4, z_far - 0.04)


func _pulse_hold_materials(root: Node3D, lane: int) -> void:
	var pulse := 1.15 + sin(_ambient_t * 10.0) * 0.2
	var body := root.get_node_or_null("Body") as MeshInstance3D
	if body and body.material_override is ShaderMaterial:
		(body.material_override as ShaderMaterial).set_shader_parameter("pulse", pulse)
		(body.material_override as ShaderMaterial).set_shader_parameter("energy", 1.35 + pulse * 0.25)
	var core := root.get_node_or_null("Core") as MeshInstance3D
	if core:
		var mat := core.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 1.6 + pulse * 0.4
	flash_lane(lane, 0.55 + pulse * 0.15)


func _fade_note_materials(root: Node3D, fade: float) -> void:
	for child in root.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var mat := mi.material_override as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var c := mat.albedo_color
			c.a = clampf(fade, 0.0, 1.0)
			mat.albedo_color = c
			mat.emission_energy_multiplier = maxf(0.1, mat.emission_energy_multiplier * 0.96)
		elif mi.material_override is ShaderMaterial:
			var sm := mi.material_override as ShaderMaterial
			sm.set_shader_parameter("energy", 1.45 * fade)
			sm.set_shader_parameter("pulse", fade)


func resolve_note(note_index: int, lane: int, grade: Judge.Grade, is_long_release: bool = false) -> void:
	var good := grade != Judge.Grade.MISS
	if good:
		play_judge_effect(lane, grade)

	if not _note_nodes.has(note_index):
		return
	var node: Node3D = _note_nodes[note_index]
	if not is_instance_valid(node):
		return

	var ntype: String = str(node.get_meta("type"))
	if ntype == "long" and not is_long_release:
		if good:
			_resolved[note_index] = {"good": false, "long_head_good": true, "fade": 1.0}
		return

	if good:
		for child in node.get_children():
			if child is MeshInstance3D:
				var mi := child as MeshInstance3D
				if mi.material_override:
					mi.material_override = mi.material_override.duplicate()
		_resolved[note_index] = {"good": true, "fade": 1.0}
		node.position = Vector3(LANE_X[lane], 0.0, JUDGE_Z)
		if ntype == "long":
			_layout_long_parts(node, JUDGE_Z, JUDGE_Z + 0.7, 0.7)
			for name in ["Body", "Core", "RailL", "RailR"]:
				var part := node.get_node_or_null(name) as Node3D
				if part:
					part.visible = false
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
	var flash := MeshInstance3D.new()
	flash.set_meta("hit_fx", true)
	var box := BoxMesh.new()
	box.size = Vector3(NOTE_WIDTH * 0.95, 0.05, 0.28)
	flash.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1).lerp(color, 0.5)
	mat.emission_energy_multiplier = 1.4
	flash.material_override = mat
	flash.position = Vector3(LANE_X[lane], 0.12, JUDGE_Z)
	add_child(flash)
	_effects.append({"node": flash, "age": 0.0, "lifetime": 0.14, "base_scale": 1.0, "kind": "press"})
	flash_lane(lane, 1.1)


func play_judge_effect(lane: int, grade: Judge.Grade) -> void:
	if lane < 0 or lane > 2:
		return
	if grade == Judge.Grade.MISS:
		return
	var color := _effect_color(grade, lane)
	var energy := 1.6
	var lifetime := 0.3
	var scale0 := 1.15
	var spark_n := 4
	match grade:
		Judge.Grade.IYA:
			energy = 2.6
			lifetime = 0.42
			scale0 = 1.4
			spark_n = 7
		Judge.Grade.HIHI:
			energy = 2.0
			lifetime = 0.34
			scale0 = 1.25
			spark_n = 5
		Judge.Grade.ENG:
			energy = 1.5
			lifetime = 0.26
			scale0 = 1.1
			spark_n = 3

	_judge_pulse = maxf(_judge_pulse, energy * 0.04)

	var flash := MeshInstance3D.new()
	flash.set_meta("hit_fx", true)
	var box := BoxMesh.new()
	box.size = Vector3(NOTE_WIDTH * 1.2, 0.16, 0.36)
	flash.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	flash.material_override = mat
	flash.position = Vector3(LANE_X[lane], 0.3, JUDGE_Z)
	add_child(flash)
	_effects.append({"node": flash, "age": 0.0, "lifetime": lifetime, "base_scale": scale0, "kind": "flash"})

	var ring := MeshInstance3D.new()
	ring.set_meta("hit_fx", true)
	var ring_mesh := BoxMesh.new()
	ring_mesh.size = Vector3(0.4, 0.04, 0.4)
	ring.mesh = ring_mesh
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	rmat.emission_enabled = true
	rmat.emission = color
	rmat.emission_energy_multiplier = energy * 0.9
	ring.material_override = rmat
	ring.position = Vector3(LANE_X[lane], 0.2, JUDGE_Z)
	add_child(ring)
	_effects.append({"node": ring, "age": 0.0, "lifetime": lifetime * 1.15, "base_scale": scale0, "kind": "ring"})

	var spark := MeshInstance3D.new()
	spark.set_meta("hit_fx", true)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.12, 1.6, 0.12)
	spark.mesh = spark_mesh
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 1.0, 1.0).lerp(color, 0.4)
	smat.emission_energy_multiplier = energy
	spark.material_override = smat
	spark.position = Vector3(LANE_X[lane], 1.0, JUDGE_Z)
	add_child(spark)
	_effects.append({"node": spark, "age": 0.0, "lifetime": lifetime * 0.85, "base_scale": scale0, "kind": "spark"})

	for i in range(spark_n):
		var shard := MeshInstance3D.new()
		shard.set_meta("hit_fx", true)
		var sh := BoxMesh.new()
		sh.size = Vector3(0.05, 0.05, 0.14)
		shard.mesh = sh
		var shmat := StandardMaterial3D.new()
		shmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shmat.albedo_color = Color(1, 1, 1, 0.9)
		shmat.emission_enabled = true
		shmat.emission = color
		shmat.emission_energy_multiplier = energy * 0.8
		shard.material_override = shmat
		shard.position = Vector3(LANE_X[lane], 0.35, JUDGE_Z)
		add_child(shard)
		var ang := randf() * TAU
		var speed := randf_range(1.8, 4.5)
		_effects.append({
			"node": shard,
			"age": 0.0,
			"lifetime": lifetime * randf_range(0.5, 0.85),
			"base_scale": 1.0,
			"kind": "shard",
			"vel": Vector3(cos(ang) * speed * 0.45, randf_range(2.2, 5.5), sin(ang) * speed * 0.2),
		})

	flash_lane(lane, energy * 0.35)


func flash_lane(lane: int, boost: float = 1.2, _auto_decay: bool = true) -> void:
	if lane < 0 or lane > 2:
		return
	_lane_boost[lane] = maxf(_lane_boost[lane], boost)
	_apply_lane_flash_visual(lane)


func _apply_lane_flash_visual(lane: int) -> void:
	var marker := get_node_or_null("LaneFlash%d" % lane) as MeshInstance3D
	if marker == null:
		return
	var mat := marker.material_override as StandardMaterial3D
	if mat == null:
		return
	var boost := _lane_boost[lane]
	var t := clampf((boost - 0.2) / 1.4, 0.0, 1.0)
	# Neutral dark bed; only a soft tint on hit.
	var idle := Color(0.07, 0.085, 0.11)
	var hit := Color(0.12, 0.14, 0.18).lerp(_lane_colors[lane] * 0.35, 0.5)
	mat.albedo_color = idle.lerp(hit, t)
	mat.emission = _lane_colors[lane]
	mat.emission_energy_multiplier = 0.15 + t * 0.7


func _decay_lane_boost() -> void:
	var dt := get_process_delta_time()
	for i in range(3):
		_lane_boost[i] = lerpf(_lane_boost[i], 0.2, clampf(dt * 9.0, 0.0, 1.0))
		_apply_lane_flash_visual(i)


func _update_ambient() -> void:
	var pulse := 0.92 + 0.08 * sin(_ambient_t * 1.6)
	if _floor_mat:
		_floor_mat.set_shader_parameter("scroll", _ambient_t * 1.2 * maxf(scroll_speed, 0.5))
		_floor_mat.set_shader_parameter("pulse", pulse + _judge_pulse * 0.5)
	if _backdrop_mat:
		_backdrop_mat.set_shader_parameter("pulse", pulse + _judge_pulse * 0.3)
	for mat in _rail_mats:
		if mat:
			mat.set_shader_parameter("scroll", _ambient_t * 0.9)
			mat.set_shader_parameter("pulse", pulse)
	_judge_pulse = maxf(0.0, _judge_pulse - get_process_delta_time() * 2.2)

	var judge := get_node_or_null("JudgeLine") as MeshInstance3D
	if judge:
		var jmat := judge.material_override as StandardMaterial3D
		if jmat:
			jmat.emission_energy_multiplier = 1.3 + _judge_pulse * 0.8 + sin(_ambient_t * 5.0) * 0.08
	var judge_glow := get_node_or_null("JudgeGlow") as MeshInstance3D
	if judge_glow:
		var gmat := judge_glow.material_override as StandardMaterial3D
		if gmat:
			gmat.emission_energy_multiplier = 0.55 + _judge_pulse * 0.5
			gmat.albedo_color.a = 0.16 + _judge_pulse * 0.1


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
				var s := base * (0.75 + t * 2.8)
				node.scale = Vector3(s, 1.0, s * 0.55)
			"spark":
				var sy := base * (1.0 + t * 1.6)
				node.scale = Vector3(1.0 - t * 0.55, sy, 1.0 - t * 0.55)
				node.position.y = 1.0 + t * 0.9
			"press":
				node.scale = Vector3(base * (1.0 + t * 0.35), 1.0, 1.0)
			"shard":
				var vel: Vector3 = fx.get("vel", Vector3.ZERO)
				node.position += vel * dt
				fx["vel"] = vel + Vector3(0.0, -11.0, 0.0) * dt
				node.scale = Vector3.ONE * (1.0 - t * 0.65)
			_:
				var s2 := base * (1.0 + t * 0.45)
				node.scale = Vector3(s2, 1.0 + t * 0.8, 1.0)
		var mat := node.material_override as StandardMaterial3D
		if mat:
			var c := mat.albedo_color
			c.a = fade
			mat.albedo_color = c
			mat.emission_energy_multiplier = maxf(0.1, mat.emission_energy_multiplier * 0.9)
		if t < 1.0:
			remain.append(fx)
		else:
			node.queue_free()
	_effects = remain


func _effect_color(grade: Judge.Grade, lane: int) -> Color:
	match grade:
		Judge.Grade.IYA:
			return Color(1.0, 0.94, 0.55).lerp(_lane_colors[lane], 0.25)
		Judge.Grade.HIHI:
			return Color(0.7, 0.92, 1.0).lerp(_lane_colors[lane], 0.3)
		Judge.Grade.ENG:
			return Color(0.85, 0.78, 1.0).lerp(_lane_colors[lane], 0.25)
		_:
			return Color(0.55, 0.55, 0.6)


func _time_to_z(target_ms: float, now_ms: float, approach_ms: float) -> float:
	var t := (target_ms - now_ms) / approach_ms
	return JUDGE_Z + t * (SPAWN_Z - JUDGE_Z)


func _build_highway() -> void:
	_build_atmosphere()
	_build_floor()
	_build_side_rails()
	_build_lanes()
	_build_judge_line()
	_build_far_portal()


func _build_atmosphere() -> void:
	var back := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48.0, 30.0)
	back.mesh = plane
	var shader := load("res://shaders/backdrop.gdshader") as Shader
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = shader
	back.material_override = _backdrop_mat
	back.rotation_degrees = Vector3(-90, 0, 0)
	back.position = Vector3(0.0, 7.0, SPAWN_Z + 8.0)
	back.name = "Backdrop"
	add_child(back)

	# Ceiling canopy for cabinet depth.
	var ceiling := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(HIGHWAY_WIDTH + 6.0, 0.08, SPAWN_Z + 6.0)
	ceiling.mesh = cmesh
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(0.04, 0.05, 0.08)
	ceiling.material_override = cmat
	ceiling.position = Vector3(0.0, 5.8, SPAWN_Z * 0.45)
	add_child(ceiling)

	# Soft ceiling accent strip.
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.2, 0.06, SPAWN_Z + 2.0)
	strip.mesh = sm
	strip.material_override = _make_mat(Color(0.35, 0.65, 0.95), 0.7)
	strip.position = Vector3(0.0, 5.7, SPAWN_Z * 0.45)
	add_child(strip)


func _build_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(HIGHWAY_WIDTH, SPAWN_Z + 4.0)
	floor_mesh.mesh = plane
	var shader := load("res://shaders/highway_floor.gdshader") as Shader
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = shader
	_floor_mat.set_shader_parameter("base_color", Color(0.045, 0.05, 0.065))
	_floor_mat.set_shader_parameter("panel_color", Color(0.09, 0.11, 0.15))
	_floor_mat.set_shader_parameter("line_color", Color(0.4, 0.5, 0.6))
	floor_mesh.material_override = _floor_mat
	floor_mesh.position = Vector3(0, -0.02, SPAWN_Z * 0.5)
	floor_mesh.name = "Floor"
	add_child(floor_mesh)

	var deck := MeshInstance3D.new()
	var dbox := BoxMesh.new()
	dbox.size = Vector3(HIGHWAY_WIDTH + 1.0, 0.12, SPAWN_Z + 4.5)
	deck.mesh = dbox
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.03, 0.035, 0.05)
	deck.material_override = dmat
	deck.position = Vector3(0, -0.12, SPAWN_Z * 0.5)
	deck.name = "Deck"
	add_child(deck)

	# Outer steel lips of the stage.
	for side in [-1.0, 1.0]:
		var lip := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(0.12, 0.1, SPAWN_Z + 4.0)
		lip.mesh = lbox
		lip.material_override = _make_mat(Color(0.55, 0.62, 0.72), 0.7)
		lip.position = Vector3(side * (HIGHWAY_WIDTH * 0.5 + 0.2), 0.02, SPAWN_Z * 0.5)
		add_child(lip)


func _build_side_rails() -> void:
	var shader := load("res://shaders/cabin_wall.gdshader") as Shader
	for side_i in range(2):
		var side := -1.0 if side_i == 0 else 1.0
		var accent := Color(0.35, 0.75, 1.0) if side < 0.0 else Color(0.95, 0.55, 0.75)
		var wall := MeshInstance3D.new()
		var wmesh := BoxMesh.new()
		wmesh.size = Vector3(0.35, 3.6, SPAWN_Z + 3.0)
		wall.mesh = wmesh
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("base_color", Color(0.055, 0.07, 0.1))
		mat.set_shader_parameter("accent_color", accent)
		mat.set_shader_parameter("energy", 0.75)
		wall.material_override = mat
		wall.position = Vector3(side * (HIGHWAY_WIDTH * 0.5 + 1.1), 1.7, SPAWN_Z * 0.5)
		wall.name = "CabinWall%d" % side_i
		add_child(wall)
		_rail_mats.append(mat)

		# Lower bumper rail.
		var bumper := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(0.2, 0.35, SPAWN_Z + 2.5)
		bumper.mesh = bmesh
		bumper.material_override = _make_mat(Color(0.18, 0.22, 0.28), 0.4)
		bumper.position = Vector3(side * (HIGHWAY_WIDTH * 0.5 + 0.55), 0.2, SPAWN_Z * 0.5)
		add_child(bumper)

		var accent_line := MeshInstance3D.new()
		var amesh := BoxMesh.new()
		amesh.size = Vector3(0.05, 0.06, SPAWN_Z + 2.0)
		accent_line.mesh = amesh
		accent_line.material_override = _make_mat(accent, 0.9)
		accent_line.position = Vector3(side * (HIGHWAY_WIDTH * 0.5 + 0.48), 0.42, SPAWN_Z * 0.5)
		add_child(accent_line)


func _build_lanes() -> void:
	for i in range(3):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(LANE_WIDTH * 0.96, 0.015, SPAWN_Z + 2.0)
		line.mesh = lm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.07, 0.085, 0.11)
		mat.emission_enabled = true
		mat.emission = _lane_colors[i]
		mat.emission_energy_multiplier = 0.15
		line.material_override = mat
		line.position = Vector3(LANE_X[i], 0.0, SPAWN_Z * 0.5)
		line.name = "LaneFlash%d" % i
		add_child(line)

		# Thin steel dividers — identity without painting the whole bed.
		for edge_side in [-1.0, 1.0]:
			var div := MeshInstance3D.new()
			var dm := BoxMesh.new()
			dm.size = Vector3(0.03, 0.04, SPAWN_Z + 2.0)
			div.mesh = dm
			div.material_override = _make_mat(Color(0.45, 0.52, 0.6), 0.55)
			div.position = Vector3(LANE_X[i] + edge_side * LANE_WIDTH * 0.5, 0.02, SPAWN_Z * 0.5)
			add_child(div)


func _build_judge_line() -> void:
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(HIGHWAY_WIDTH - 0.15, 0.05, 0.55)
	plate.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.1, 0.12, 0.16)
	plate.material_override = pmat
	plate.position = Vector3(0, 0.01, JUDGE_Z)
	add_child(plate)

	var judge := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(HIGHWAY_WIDTH - 0.3, 0.08, 0.1)
	judge.mesh = jm
	var jmat := StandardMaterial3D.new()
	jmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	jmat.albedo_color = Color(0.92, 0.96, 1.0)
	jmat.emission_enabled = true
	jmat.emission = Color(0.75, 0.9, 1.0)
	jmat.emission_energy_multiplier = 1.35
	judge.material_override = jmat
	judge.position = Vector3(0, 0.07, JUDGE_Z)
	judge.name = "JudgeLine"
	add_child(judge)

	var glow := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(HIGHWAY_WIDTH + 0.2, 0.03, 0.55)
	glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.55, 0.8, 1.0, 0.16)
	gmat.emission_enabled = true
	gmat.emission = Color(0.55, 0.85, 1.0)
	gmat.emission_energy_multiplier = 0.55
	glow.material_override = gmat
	glow.position = Vector3(0, 0.02, JUDGE_Z)
	glow.name = "JudgeGlow"
	add_child(glow)

	for i in range(3):
		var tick := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(NOTE_WIDTH * 0.85, 0.04, 0.06)
		tick.mesh = tm
		tick.material_override = _make_mat(
			Color(0.85, 0.9, 0.95).lerp(_lane_colors[i], 0.45), 1.2
		)
		tick.position = Vector3(LANE_X[i], 0.12, JUDGE_Z)
		add_child(tick)


func _build_far_portal() -> void:
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(HIGHWAY_WIDTH + 1.4, 0.14, 0.16)
	frame.mesh = fm
	frame.material_override = _make_mat(Color(0.5, 0.6, 0.75), 0.9)
	frame.position = Vector3(0.0, 0.1, SPAWN_Z + 0.7)
	frame.name = "FarPortal"
	add_child(frame)

	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.22, 2.6, 0.22)
		pillar.mesh = box
		pillar.material_override = _make_mat(Color(0.2, 0.24, 0.3), 0.5)
		pillar.position = Vector3(side * (HIGHWAY_WIDTH * 0.5 + 0.35), 1.3, SPAWN_Z + 0.7)
		add_child(pillar)

		var cap := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.1, 1.8, 0.08)
		cap.mesh = cbox
		var accent := _lane_colors[0] if side < 0.0 else _lane_colors[2]
		cap.material_override = _make_mat(accent, 0.85)
		cap.position = Vector3(side * (HIGHWAY_WIDTH * 0.5 + 0.35), 1.3, SPAWN_Z + 0.55)
		add_child(cap)


func _make_mat(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, color.a)
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = energy
	return mat
