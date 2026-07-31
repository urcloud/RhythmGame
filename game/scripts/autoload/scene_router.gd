extends Node

signal chart_selected(chart_path: String)

var pending_chart_path: String = ""
var last_result: Dictionary = {}


func go_song_select() -> void:
	_change("res://scenes/song_select.tscn")


func go_settings() -> void:
	_change("res://scenes/settings.tscn")


func go_gameplay(chart_path: String) -> void:
	pending_chart_path = chart_path
	chart_selected.emit(chart_path)
	_change("res://scenes/gameplay.tscn")


func go_result(result: Dictionary) -> void:
	last_result = result
	_change("res://scenes/result.tscn")


func _change(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)
