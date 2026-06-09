extends Node

## Boss-fight battle music. A bundled track that loops while a boss is alive.
## On boss start the normal AudioManager music STOPS and this track fades in; on boss end
## (victory or player death) this track fades out and AudioManager starts a FRESH track.
## Reads only AudioManager's public surface (music_player / music_volume / next_track) — it does
## NOT modify the locked audio_manager.gd. Created as a child of the main scene by main.gd.

const TRACK_PATH := "res://assets/audio/boss/boss_music_2.mp3"
const FADE_SEC := 0.5
const SILENT_DB := -60.0   # effectively inaudible (fade target when off)

var _player: AudioStreamPlayer
var _active: bool = false
var _fade: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	add_child(_player)
	var stream := load(TRACK_PATH) as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true   # seamless repeat for the whole fight
	_player.stream = stream
	_player.volume_db = SILENT_DB
	GameManager.boss_spawned.connect(_on_boss_start)
	GameManager.boss_killed.connect(_on_boss_end)
	GameManager.ship_destroyed.connect(_on_boss_end)

func _on_boss_start() -> void:
	if _active:
		return   # already in a fight (e.g. Chromeleon re-emits boss_spawned at phase 2)
	_active = true
	# Stop the normal background music: fade the shared player down, then stop it.
	if AudioManager != null and AudioManager.music_player != null:
		var amp: AudioStreamPlayer = AudioManager.music_player
		var tw := create_tween()
		tw.tween_property(amp, "volume_db", SILENT_DB, FADE_SEC)
		tw.tween_callback(amp.stop)
	# Fade the boss track in from silence.
	_player.volume_db = SILENT_DB
	if not _player.playing:
		_player.play()
	_fade_player_to(_target_db())

func _on_boss_end() -> void:
	if not _active:
		return   # ship_destroyed/boss_killed can fire outside a boss fight — ignore
	# A 2-phase boss fires boss_killed when its first phase dies — keep the boss track playing
	# through the transition into phase 2 instead of switching back to normal music.
	var bf := get_tree().get_first_node_in_group("boss_fight")
	if bf != null and bf.has_method("is_phase_transition") and bf.is_phase_transition():
		return
	_active = false
	# Fade the boss track out, then stop it.
	_fade_player_to(SILENT_DB)
	_fade.tween_callback(_player.stop)
	# Restart the normal music with a fresh track, faded in.
	if AudioManager != null:
		AudioManager.next_track()
		if AudioManager.music_player != null:
			var amp: AudioStreamPlayer = AudioManager.music_player
			amp.volume_db = SILENT_DB
			var tw := create_tween()
			tw.tween_property(amp, "volume_db", _music_db(), FADE_SEC)

func _process(_delta: float) -> void:
	# While the boss track is the active music, keep it in sync with the volume slider.
	if _active and _player.playing and (_fade == null or not _fade.is_valid()):
		_player.volume_db = _target_db()

# ── helpers ───────────────────────────────────────────────────────────────────

## The boss track's target loudness, following the in-game music-volume setting.
func _target_db() -> float:
	return _music_db()

func _music_db() -> float:
	var v := 1.0
	if AudioManager != null:
		v = clampf(AudioManager.music_volume, 0.0001, 1.0)
	return linear_to_db(v)

func _fade_player_to(db: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", db, FADE_SEC)
