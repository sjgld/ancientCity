extends Node
## 聲音：以撥弦合成（Karplus-Strong）即時生成古琴般的五聲音階配樂與音效，不需任何音檔。

const SR := 22050
# 五聲音階（宮商角徵羽），由低至高
const SCALE := [146.83, 164.81, 196.0, 220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33]

var notes: Array = []
var sfx := {}
var players: Array = []
var sfx_players: Array = []
var music_on := true
var sound_on := true
var ready_notes := false
var gen_i := 0
var next_t := 2.0
var pos := 4
var phrase_left := 0
var last_bad := 0.0


func _ready() -> void:
	var mb := AudioServer.bus_count
	AudioServer.add_bus(mb)
	AudioServer.set_bus_name(mb, "Music")
	AudioServer.set_bus_send(mb, "Master")
	AudioServer.set_bus_volume_db(mb, -9.0)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.85
	rv.damping = 0.4
	rv.wet = 0.4
	rv.dry = 0.75
	AudioServer.add_bus_effect(mb, rv)
	var sb := AudioServer.bus_count
	AudioServer.add_bus(sb)
	AudioServer.set_bus_name(sb, "Sfx")
	AudioServer.set_bus_send(sb, "Master")
	AudioServer.set_bus_volume_db(sb, -6.0)
	for k in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		players.append(p)
	for k in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		sfx_players.append(p)
	notes.resize(SCALE.size())


func _process(delta: float) -> void:
	# 每幀生成一個音，避免啟動時卡頓
	if gen_i < SCALE.size():
		notes[gen_i] = _pluck(SCALE[gen_i], 3.2, 0.996, 0.9)
		gen_i += 1
		return
	if sfx.is_empty():
		sfx["click"] = _pluck(1318.5, 0.18, 0.95, 0.5)
		sfx["coin"] = _pluck(1760.0, 0.6, 0.99, 0.6)
		sfx["build"] = _thump()
		sfx["gong"] = _gong()
		sfx["bad"] = _drum()
		ready_notes = true
		return
	if not music_on or DisplayServer.get_name() == "headless":
		return
	next_t -= delta
	if next_t > 0:
		return
	if phrase_left <= 0:
		phrase_left = randi_range(4, 8)
		next_t = randf_range(2.5, 6.0)
		pos = clampi(pos + randi_range(-2, 2), 2, SCALE.size() - 3)
		return
	phrase_left -= 1
	pos = clampi(pos + [-2, -1, -1, 1, 1, 2, 0][randi() % 7], 0, SCALE.size() - 1)
	_play_note(pos, randf_range(0.55, 0.85))
	if randf() < 0.15 and pos + 4 < SCALE.size():
		_play_note(pos + 4, 0.35)
	next_t = [0.5, 0.75, 0.75, 1.0, 1.5][randi() % 5]


func _play_note(i: int, vol: float) -> void:
	for p in players:
		if not p.playing:
			p.stream = notes[i]
			p.volume_db = linear_to_db(vol)
			p.play()
			return


func play(name: String) -> void:
	if not sound_on or not sfx.has(name):
		return
	if name == "bad":
		var now := Time.get_ticks_msec() / 1000.0
		if now - last_bad < 3.0:
			return
		last_bad = now
	for p in sfx_players:
		if not p.playing:
			p.stream = sfx[name]
			p.play()
			return


func set_music(on: bool) -> void:
	music_on = on
	if not on:
		for p in players:
			p.stop()


func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	return w


## 撥弦：雜訊填入延遲線，反覆平均即成弦音；decay 越近 1 餘音越長。
func _pluck(freq: float, dur: float, decay: float, gain: float) -> AudioStreamWAV:
	var n := int(SR * dur)
	var period := maxi(2, int(SR / freq))
	var buf := PackedFloat32Array()
	buf.resize(period)
	for i in period:
		buf[i] = randf_range(-1.0, 1.0)
	# 先平滑一次，音色較溫潤
	for i in period:
		buf[i] = (buf[i] + buf[(i + 1) % period]) * 0.5
	var out := PackedFloat32Array()
	out.resize(n)
	var idx := 0
	for i in n:
		var cur := buf[idx]
		var nxt := buf[(idx + 1) % period]
		buf[idx] = (cur + nxt) * 0.5 * decay
		idx = (idx + 1) % period
		var env := minf(1.0, i / 60.0)
		out[i] = cur * gain * env
	return _wav(out)


func _thump() -> AudioStreamWAV:
	var n := int(SR * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (randf_range(-1, 1) - lp) * 0.08
		out[i] = (sin(TAU * 85.0 * t) * 0.8 + lp * 1.5) * exp(-t * 14.0)
	return _wav(out)


func _drum() -> AudioStreamWAV:
	var n := int(SR * 0.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (randf_range(-1, 1) - lp) * 0.05
		var f := 70.0 - t * 30.0
		out[i] = (sin(TAU * f * t) * 0.9 + lp * 1.2) * exp(-t * 7.0)
	return _wav(out)


func _gong() -> AudioStreamWAV:
	var n := int(SR * 3.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var parts := [[1.0, 1.0, 1.2], [1.48, 0.6, 1.6], [2.03, 0.45, 2.2], [2.76, 0.3, 3.0], [3.9, 0.2, 4.0]]
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		for p in parts:
			v += sin(TAU * 98.0 * p[0] * t + sin(t * 3.0) * 0.4) * p[1] * exp(-t * p[2])
		out[i] = v * 0.4 * minf(1.0, t * 200.0)
	return _wav(out)
