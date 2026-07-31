class_name Timing
extends RefCounted

var bpm: float = 120.0
var offset_beats: float = 0.0


func _init(p_bpm: float = 120.0, p_offset: float = 0.0) -> void:
	bpm = p_bpm
	offset_beats = p_offset


func beat_to_ms(beat: float) -> float:
	return (beat + offset_beats) * (60000.0 / bpm)


func ms_to_beat(time_ms: float) -> float:
	return time_ms * (bpm / 60000.0) - offset_beats
