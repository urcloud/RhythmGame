extends Control

@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var score_label: Label = $Margin/VBox/ScoreLabel
@onready var combo_label: Label = $Margin/VBox/ComboLabel
@onready var counts_label: Label = $Margin/VBox/CountsLabel


func _ready() -> void:
	var r: Dictionary = SceneRouter.last_result
	title_label.text = "%s — %s" % [str(r.get("title", "")), str(r.get("artist", ""))]
	score_label.text = "SCORE  %07d" % int(r.get("score", 0))
	combo_label.text = "MAX COMBO  %d" % int(r.get("max_combo", 0))
	var counts: Dictionary = r.get("counts", {})
	counts_label.text = "이야! %d    히히 %d    엥... %d    Miss %d" % [
		int(counts.get("이야!", 0)),
		int(counts.get("히히", 0)),
		int(counts.get("엥...", 0)),
		int(counts.get("Miss", 0)),
	]


func _on_back_pressed() -> void:
	SceneRouter.go_song_select()
