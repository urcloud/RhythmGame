extends Control

@onready var list: ItemList = $Margin/VBox/ChartList
@onready var detail: Label = $Margin/VBox/DetailLabel
@onready var error_label: Label = $Margin/VBox/ErrorLabel
@onready var play_button: Button = $Margin/VBox/ButtonRow/PlayButton
@onready var path_label: Label = $Margin/VBox/PathLabel

var _entries: Array = []


func _ready() -> void:
	play_button.disabled = true
	error_label.text = ""
	_refresh()


func _refresh() -> void:
	list.clear()
	_entries.clear()
	var dir_path := AppConfig.resolve_chart_dir()
	path_label.text = "차트 폴더: %s" % dir_path
	if not DirAccess.dir_exists_absolute(dir_path):
		error_label.text = "chart_dir not found: %s" % dir_path
		return
	_entries = ChartLoader.scan_directory(dir_path)
	if _entries.is_empty():
		error_label.text = "No .json charts found"
		return
	for entry in _entries:
		if entry.ok:
			var c: ChartData = entry.chart
			list.add_item("%s  /  %s  [Lv.%d]" % [c.title, c.artist, c.difficulty])
		else:
			list.add_item("[오류] %s" % entry.path.get_file())
	error_label.text = ""


func _on_chart_list_item_selected(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry = _entries[index]
	if entry.ok:
		var c: ChartData = entry.chart
		detail.text = "%s\n아티스트: %s\n난이도: %d\nBPM: %.1f\n노트: %d\n오디오: %s" % [
			c.title, c.artist, c.difficulty, c.bpm, c.note_count(), c.audio_path
		]
		error_label.text = ""
		play_button.disabled = false
	else:
		detail.text = entry.path
		error_label.text = entry.error
		play_button.disabled = true


func _on_play_button_pressed() -> void:
	var selected := list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	var entry = _entries[index]
	if entry.ok:
		SceneRouter.go_gameplay(entry.path)


func _on_settings_button_pressed() -> void:
	SceneRouter.go_settings()


func _on_refresh_button_pressed() -> void:
	_refresh()
