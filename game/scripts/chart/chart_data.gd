class_name ChartData
extends RefCounted

var path: String = ""
var format_version: int = 1
var title: String = ""
var artist: String = ""
var audio_path: String = ""
var bpm: float = 120.0
var offset_beats: float = 0.0
var difficulty: int = 1
var notes: Array = [] # Array of Dictionaries


func note_count() -> int:
	return notes.size()


func judgment_object_count() -> int:
	var n := 0
	for note in notes:
		if str(note.get("type", "")) == "long":
			n += 2
		else:
			n += 1
	return n
