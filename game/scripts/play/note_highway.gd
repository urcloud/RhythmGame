class_name NoteHighway
extends Node3D

const LANE_X: Array[float] = [-1.2, 0.0, 1.2]
const JUDGE_Z := 0.0
const SPAWN_Z := 28.0
const BASE_APPROACH_MS := 2000.0

var scroll_speed: float = 1.0
var _note_nodes: Dictionary = {} # note_index -> Node3D
var _materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	_build_highway()
	_materials = [
		_make_mat(Color(0.35, 0.75, 1.0)),
		_make_mat(Color(1.0, 0.45, 0.6)),
		_make_mat(Color(1.0, 0.85, 0.3)),
	]


func setup_notes(notes: Array, timing: Timing) -> void:
	for child in get_children():
		if child.has_meta("note_index"):
			child.queue_free()
	_note_nodes.clear()

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
			box.size = Vector3(0.9, 0.2, 1.0)
			node.mesh = box
		else:
			var box2 := BoxMesh.new()
			box2.size = Vector3(0.9, 0.25, 0.45)
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
		var lane: int = node.get_meta("lane")
		var start_ms: float = node.get_meta("start_ms")
		var ntype: String = node.get_meta("type")
		var x: float = LANE_X[lane]

		if ntype == "single":
			var z := _time_to_z(start_ms, now_ms, approach)
			node.visible = z > JUDGE_Z - 1.0 and z < SPAWN_Z + 2.0
			node.position = Vector3(x, 0.15, z)
		else:
			var end_ms: float = node.get_meta("end_ms")
			var z_start := _time_to_z(start_ms, now_ms, approach)
			var z_end := _time_to_z(end_ms, now_ms, approach)
			# bar from end (farther) to start (closer / judge)
			var z_far := maxf(z_start, z_end)
			var z_near := minf(z_start, z_end)
			var length := maxf(0.2, z_far - z_near)
			var mesh := node.mesh as BoxMesh
			if mesh:
				mesh.size = Vector3(0.9, 0.2, length)
			node.visible = z_far > JUDGE_Z - 1.0 and z_near < SPAWN_Z + 2.0
			node.position = Vector3(x, 0.12, (z_far + z_near) * 0.5)


func hide_note(note_index: int) -> void:
	if _note_nodes.has(note_index):
		var node: Node3D = _note_nodes[note_index]
		if is_instance_valid(node):
			node.visible = false


func flash_lane(lane: int) -> void:
	# optional pulse via highway lane markers
	var marker := get_node_or_null("LaneFlash%d" % lane)
	if marker and marker is MeshInstance3D:
		var mat := (marker as MeshInstance3D).material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.5
			get_tree().create_timer(0.08).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 0.2
			)


func _time_to_z(target_ms: float, now_ms: float, approach_ms: float) -> float:
	var t := (target_ms - now_ms) / approach_ms
	return JUDGE_Z + t * (SPAWN_Z - JUDGE_Z)


func _build_highway() -> void:
	# floor
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(4.2, 0.05, SPAWN_Z + 4.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.08, 0.1, 0.14)
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -0.05, SPAWN_Z * 0.5)
	floor_mesh.name = "Floor"
	add_child(floor_mesh)

	# lane lines
	for i in range(3):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(1.0, 0.02, SPAWN_Z + 2.0)
		line.mesh = lm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.18, 0.24)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.25, 0.35)
		mat.emission_energy_multiplier = 0.2
		line.material_override = mat
		line.position = Vector3(LANE_X[i], 0.0, SPAWN_Z * 0.5)
		line.name = "LaneFlash%d" % i
		add_child(line)

	# judgment line
	var judge := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(4.0, 0.08, 0.12)
	judge.mesh = jm
	var jmat := StandardMaterial3D.new()
	jmat.albedo_color = Color(0.95, 0.95, 1.0)
	jmat.emission_enabled = true
	jmat.emission = Color(0.8, 0.9, 1.0)
	jmat.emission_energy_multiplier = 1.2
	judge.material_override = jmat
	judge.position = Vector3(0, 0.05, JUDGE_Z)
	judge.name = "JudgeLine"
	add_child(judge)


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	return mat
