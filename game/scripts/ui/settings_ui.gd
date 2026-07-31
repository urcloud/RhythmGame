extends Control

@onready var chart_dir_edit: LineEdit = $Margin/VBox/Grid/ChartDirEdit
@onready var scroll_spin: SpinBox = $Margin/VBox/Grid/ScrollSpin
@onready var iya_spin: SpinBox = $Margin/VBox/Grid/IyaSpin
@onready var hihi_spin: SpinBox = $Margin/VBox/Grid/HihiSpin
@onready var eng_spin: SpinBox = $Margin/VBox/Grid/EngSpin
@onready var audio_offset_spin: SpinBox = $Margin/VBox/Grid/AudioOffsetSpin
@onready var lane0_edit: LineEdit = $Margin/VBox/Grid/Lane0Edit
@onready var lane1_edit: LineEdit = $Margin/VBox/Grid/Lane1Edit
@onready var lane2_edit: LineEdit = $Margin/VBox/Grid/Lane2Edit
@onready var width_spin: SpinBox = $Margin/VBox/Grid/WidthSpin
@onready var height_spin: SpinBox = $Margin/VBox/Grid/HeightSpin
@onready var fullscreen_check: CheckBox = $Margin/VBox/Grid/FullscreenCheck
@onready var status_label: Label = $Margin/VBox/StatusLabel


func _ready() -> void:
	_load_into_ui(AppConfig.get_as_dict())
	status_label.text = ""


func _load_into_ui(data: Dictionary) -> void:
	chart_dir_edit.text = str(data.get("chart_dir", ""))
	scroll_spin.value = float(data.get("scroll_speed", 1.0))
	iya_spin.value = int(data.get("judge_iya_ms", 45))
	hihi_spin.value = int(data.get("judge_hihi_ms", 90))
	eng_spin.value = int(data.get("judge_eng_ms", 150))
	audio_offset_spin.value = int(data.get("audio_offset_ms", 0))
	lane0_edit.text = _keys_to_text(data.get("lane0_keys", []))
	lane1_edit.text = _keys_to_text(data.get("lane1_keys", []))
	lane2_edit.text = _keys_to_text(data.get("lane2_keys", []))
	width_spin.value = int(data.get("window_width", 1280))
	height_spin.value = int(data.get("window_height", 720))
	fullscreen_check.button_pressed = bool(data.get("fullscreen", false))


func _collect() -> Dictionary:
	return {
		"chart_dir": chart_dir_edit.text.strip_edges(),
		"scroll_speed": float(scroll_spin.value),
		"audio_offset_ms": int(audio_offset_spin.value),
		"judge_iya_ms": int(iya_spin.value),
		"judge_hihi_ms": int(hihi_spin.value),
		"judge_eng_ms": int(eng_spin.value),
		"lane0_keys": _text_to_keys(lane0_edit.text),
		"lane1_keys": _text_to_keys(lane1_edit.text),
		"lane2_keys": _text_to_keys(lane2_edit.text),
		"window_width": int(width_spin.value),
		"window_height": int(height_spin.value),
		"fullscreen": fullscreen_check.button_pressed,
	}


func _on_save_pressed() -> void:
	var err := AppConfig.save_from_dict(_collect())
	if err == "":
		status_label.text = "저장됨"
		status_label.modulate = Color(0.5, 1.0, 0.6)
	else:
		status_label.text = err
		status_label.modulate = Color(1.0, 0.45, 0.45)


func _on_reset_pressed() -> void:
	AppConfig.reset_to_defaults()
	_load_into_ui(AppConfig.get_as_dict())
	status_label.text = "기본값으로 복원됨"
	status_label.modulate = Color(0.7, 0.85, 1.0)


func _on_back_pressed() -> void:
	SceneRouter.go_song_select()


func _keys_to_text(keys: Variant) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if keys is Array or keys is PackedStringArray:
		for k in keys:
			parts.append(str(k))
	return " ".join(parts)


func _text_to_keys(text: String) -> Array:
	var out: Array = []
	for part in text.split(" ", false):
		var t := part.strip_edges()
		if not t.is_empty():
			out.append(t)
	return out
