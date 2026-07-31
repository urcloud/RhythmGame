class_name Judge
extends RefCounted

enum Grade {
	IYA,
	HIHI,
	ENG,
	MISS,
}

const WEIGHTS := {
	Grade.IYA: 1.0,
	Grade.HIHI: 0.7,
	Grade.ENG: 0.3,
	Grade.MISS: 0.0,
}

const LABELS := {
	Grade.IYA: "이야!",
	Grade.HIHI: "히히",
	Grade.ENG: "엥...",
	Grade.MISS: "Miss",
}


static func grade_from_delta(abs_dt_ms: float, iya_ms: int, hihi_ms: int, eng_ms: int) -> Grade:
	if abs_dt_ms <= float(iya_ms):
		return Grade.IYA
	if abs_dt_ms <= float(hihi_ms):
		return Grade.HIHI
	if abs_dt_ms <= float(eng_ms):
		return Grade.ENG
	return Grade.MISS


static func weight(grade: Grade) -> float:
	return float(WEIGHTS[grade])


static func label(grade: Grade) -> String:
	return str(LABELS[grade])
