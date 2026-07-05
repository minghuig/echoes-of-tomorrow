class_name Sfx
extends RefCounted
## Procedural sound effects: tiny square-wave PCM16 blips synthesized once at
## startup. No audio assets in the repo, nothing for the web export to fetch.
## Pure view-layer flavor — the sim never knows sound exists.

const MIX_RATE: int = 22050


static func fire_blip() -> AudioStreamWAV:
	return _tone([880.0], 0.05)


static func block_hit() -> AudioStreamWAV:
	return _tone([440.0], 0.05)


static func block_break() -> AudioStreamWAV:
	return _tone([150.0], 0.2)


static func clear_chime() -> AudioStreamWAV:
	return _tone([660.0, 880.0, 1320.0], 0.45)


## Square wave with exponential decay; multiple frequencies play as equal
## sequential segments (a tiny arpeggio).
static func _tone(freqs: Array, duration: float) -> AudioStreamWAV:
	var frames := int(duration * MIX_RATE)
	var segment := maxi(1, frames / freqs.size())
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var freq: float = freqs[mini(i / segment, freqs.size() - 1)]
		var phase := fmod(float(i) * freq / MIX_RATE, 1.0)
		var sample := 1.0 if phase < 0.5 else -1.0
		var envelope := exp(-6.0 * float(i % segment) / float(segment))
		data.encode_s16(i * 2, int(sample * envelope * 0.4 * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav
