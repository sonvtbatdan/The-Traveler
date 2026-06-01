extends Node

const _STATE_FILE := "the_traveler_audio_monitor.tmp"

var _ps_pid:        int     = -1
var _state_file:    String  = ""
var _pre_mute_vol:  float   = -1.0
var _last_state:    String  = ""
var _timer:         Timer   = null

func _ready() -> void:
	_state_file = OS.get_temp_dir().path_join(_STATE_FILE)
	_timer = Timer.new()
	_timer.wait_time  = 0.5
	_timer.one_shot   = false
	_timer.autostart  = false
	_timer.timeout.connect(_on_poll)
	add_child(_timer)

func set_enabled(v: bool) -> void:
	if v:
		_start()
	else:
		_stop()

func _start() -> void:
	_stop()
	var script_path: String = ProjectSettings.globalize_path("res://tools/audio-monitor.ps1")
	# Use -Command with single-quoted paths to handle spaces in project path.
	var ps_cmd: String = "& '%s' -GamePID %d -StateFile '%s'" % [
		script_path.replace("'", "''"),
		OS.get_process_id(),
		_state_file.replace("'", "''"),
	]
	_ps_pid = OS.create_process("powershell.exe", [
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-NonInteractive",
		"-Command", ps_cmd,
	])
	_timer.start()

func _stop() -> void:
	_timer.stop()
	if _ps_pid > 0:
		OS.kill(_ps_pid)
		_ps_pid = -1
	_unmute()
	_last_state = ""
	if FileAccess.file_exists(_state_file):
		DirAccess.remove_absolute(_state_file)

func _on_poll() -> void:
	if not FileAccess.file_exists(_state_file):
		return
	var f := FileAccess.open(_state_file, FileAccess.READ)
	if f == null:
		return
	var state: String = f.get_as_text().strip_edges()
	f = null
	if state == _last_state:
		return
	_last_state = state
	match state:
		"MUTE":   _mute()
		"UNMUTE": _unmute()

func _mute() -> void:
	if _pre_mute_vol >= 0.0:
		return
	_pre_mute_vol = AudioManager.music_volume
	AudioManager.set_music_volume(0.0)

func _unmute() -> void:
	if _pre_mute_vol < 0.0:
		return
	AudioManager.set_music_volume(_pre_mute_vol)
	_pre_mute_vol = -1.0

func _exit_tree() -> void:
	_stop()
