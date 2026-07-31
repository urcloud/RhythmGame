class_name HitSfx
extends RefCounted

## Soft supportive "탓" tick — quiet enough to sit under any BGM.


static func make_tat_stream() -> AudioStreamWAV:
	var sample_rate := 44100
	var duration := 0.045
	var n := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(sample_rate)
		# Soft rounded envelope — no harsh snap.
		var env := exp(-t * 85.0)
		var env_noise := exp(-t * 160.0)

		# Warm mid tick (gentle wood/fingertip), avoids piercing highs.
		var tone := sin(TAU * 620.0 * t) * 0.34
		tone += sin(TAU * 930.0 * t) * 0.16
		tone += sin(TAU * 310.0 * t) * 0.12

		# Tiny soft noise for texture, heavily filtered by short envelope.
		var noise := (randf() * 2.0 - 1.0) * 0.04 * env_noise

		var sample := (tone * env + noise) * 0.28
		var s := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
