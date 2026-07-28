extends Node

const MUSIC_DIR := "res://assets/audio/music/"

var music_volume: float = 1.0
var sfx_volume:   float = 1.0
var weapon_sfx_vols: Dictionary = {
	"gun":       1.0,
	"turret":    1.0,
	"canon":     1.0,
	"lightning": 1.0,
	"railgun":   1.0,
}

func get_weapon_sfx_vol(key: String) -> float:
	return sfx_volume * float(weapon_sfx_vols.get(key, 1.0))

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

var _playlist: Array[String] = []
var _playlist_index: int = 0
var _shuffle_enabled: bool = false
var _loop_current: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep ducking tracked/smoothed even while the game is paused
	_setup_master_duck()
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "SFX"
	add_child(sfx_player)
	music_player.finished.connect(_on_track_finished)
	_build_playlist()
	_play_current_track()

func _process(delta: float) -> void:
	_tick_duck(delta)

# ── Overlap ducking ────────────────────────────────────────────────────────────────────────────────
# Replaces an earlier AudioEffectLimiter (removed 2026-07-28 — it audibly crackled once many short SFX
# (hit/fire/explosion) piled up at once; a hard-limiter's sample-accurate clamping doesn't play nicely with
# game audio's fast transients). This instead SMOOTHLY reduces gain via an AudioEffectAmplify on the Master
# bus, driven every frame from the bus's own real-time peak-volume reading (AudioServer.get_bus_peak_volume_
# *_db) — the more sound currently overlapping, the higher that peak reads, the more this ducks; a lone
## sound (or a quiet moment) stays under DUCK_PEAK_THRESHOLD_DB and is left completely untouched. Fast
# attack (catches a sudden pile-up immediately) + slow release (recovers gradually, no audible pumping/
# crackle) — the actual fix for the artifact, not just a different curve shape.
# Deliberately an AudioEffectAmplify (an effect's own gain), NOT AudioServer.set_bus_volume_db(master, ...)
# — that property is what settings_panel.gd's volume slider controls; ducking it directly would fight the
# slider every frame. This stays fully orthogonal: the slider sets the base level, this only ever pulls
# the mix down temporarily on top of it.
const DUCK_PEAK_THRESHOLD_DB := -14.0   # peak below this = a single/few sound — left alone, untouched
const DUCK_MAX_DB            := -9.0    # heaviest reduction applied once the mix gets very loud/overlapping
const DUCK_RATIO             := 0.6     # fraction of the "over threshold" amount that actually gets ducked
const DUCK_ATTACK_SPEED      := 30.0    # dB/sec ducking IN — fast, catches a sudden pile-up right away
const DUCK_RELEASE_SPEED     := 6.0     # dB/sec recovering OUT — slow, avoids audible pumping

var _duck_amp: AudioEffectAmplify = null
var _duck_db: float = 0.0

func _setup_master_duck() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	var i := AudioServer.get_bus_effect_count(master) - 1
	while i >= 0:
		if AudioServer.get_bus_effect(master, i) is AudioEffectLimiter:
			AudioServer.remove_bus_effect(master, i)   # drop the old limiter if this project still has one
		i -= 1
	for j in AudioServer.get_bus_effect_count(master):
		var fx := AudioServer.get_bus_effect(master, j)
		if fx is AudioEffectAmplify:
			_duck_amp = fx
			return   # already set up (shouldn't happen — autoload _ready() runs once — but stay idempotent)
	_duck_amp = AudioEffectAmplify.new()
	_duck_amp.volume_db = 0.0
	AudioServer.add_bus_effect(master, _duck_amp)

func _tick_duck(delta: float) -> void:
	if _duck_amp == null:
		return
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	var peak := maxf(AudioServer.get_bus_peak_volume_left_db(master, 0), AudioServer.get_bus_peak_volume_right_db(master, 0))
	var over := maxf(0.0, peak - DUCK_PEAK_THRESHOLD_DB)
	var target := clampf(-over * DUCK_RATIO, DUCK_MAX_DB, 0.0)
	var speed := DUCK_ATTACK_SPEED if target < _duck_db else DUCK_RELEASE_SPEED
	_duck_db = move_toward(_duck_db, target, speed * delta)
	_duck_amp.volume_db = _duck_db

func _build_playlist() -> void:
	_playlist.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() in ["wav", "ogg", "mp3"]:
			_playlist.append(MUSIC_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	_playlist.shuffle()
	_playlist_index = 0

func _play_current_track() -> void:
	if _playlist.is_empty():
		return
	var tried := 0
	while tried < _playlist.size():
		var path: String = _playlist[_playlist_index]
		var stream := load(path) as AudioStream
		if stream != null:
			music_player.stream = stream
			music_player.volume_db = linear_to_db(music_volume)
			music_player.play()
			return
		push_warning("AudioManager: cannot load '%s', skipping" % path)
		_playlist_index = (_playlist_index + 1) % _playlist.size()
		tried += 1
	push_warning("AudioManager: no playable tracks in playlist")

func _on_track_finished() -> void:
	if _loop_current:
		_play_current_track()
		return
	_playlist_index = (_playlist_index + 1) % _playlist.size()
	if _playlist_index == 0 and _shuffle_enabled:
		_playlist.shuffle()
	_play_current_track()

func _advance_track() -> void:
	_playlist_index = (_playlist_index + 1) % _playlist.size()
	if _playlist_index == 0 and _shuffle_enabled:
		_playlist.shuffle()
	_play_current_track()

func prev_track() -> void:
	_playlist_index = (_playlist_index - 1 + _playlist.size()) % _playlist.size()
	_play_current_track()

func set_shuffle(enabled: bool) -> void:
	_shuffle_enabled = enabled
	if enabled:
		_playlist.shuffle()
		_playlist_index = 0

func set_loop(enabled: bool) -> void:
	_loop_current = enabled

func play_music(stream: AudioStream) -> void:
	music_player.stream = stream
	music_player.volume_db = linear_to_db(music_volume)
	music_player.play()

func play_sfx(stream: AudioStream) -> void:
	sfx_player.stream = stream
	sfx_player.volume_db = linear_to_db(sfx_volume)
	sfx_player.play()

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)
	sfx_player.volume_db = linear_to_db(sfx_volume)

func next_track() -> void:
	_advance_track()
