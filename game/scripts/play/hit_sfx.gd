class_name HitSfx
extends RefCounted

## Soft percussive "탓" click synthesized at runtime.


static func make_tat_stream() -> AudioStreamWAV:
	var sample_rate := 44100
	var duration := 0.055
	var n := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 70.0)
		# Soft wood/rim-ish click: low sine + short noise burst
		var tone := sin(TAU * 210.0 * t) * 0.42
		tone += sin(TAU * 420.0 * t) * 0.12
		var noise := (randf() * 2.0 - 1.0) * 0.1 * exp(-t * 140.0)
		var sample := (tone + noise) * env * 0.55
		var s := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
