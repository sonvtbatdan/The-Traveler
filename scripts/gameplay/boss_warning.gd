extends Node

## Boss entry warning: flashes warning.png over the SpaceScreen and plays the alert SFX
## whenever GameManager.boss_spawned fires (including phase transitions).

const WARNING_PATH   := "res://assets/screen/warning.png"
const ALERT_SFX_PATH := "res://assets/audio/sfx/bossalert.wav"

const FLASH_DURATION := 5.0   # total duration (seconds)
const FLASH_INTERVAL := 0.75  # one on/off cycle (seconds)
const FADE_TIME      := 0.2   # fade-out duration per flash (seconds)

# SpaceScreen bounds in viewport space, shifted up 300px
const SS_POS  := Vector2(270.0, 8.0 - 150.0)
const SS_SIZE := Vector2(700.0, 764.0)

var _sfx: AudioStream = null
var _tex: Texture2D   = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx = load(ALERT_SFX_PATH) as AudioStream
	_tex = load(WARNING_PATH) as Texture2D
	GameManager.boss_incoming.connect(_on_boss_incoming)

func _on_boss_incoming() -> void:
	if _sfx != null:
		AudioManager.play_sfx(_sfx)
	if _tex != null:
		_run_flash()

func _run_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)

	var tr := TextureRect.new()
	tr.texture = _tex
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = SS_POS
	tr.size = SS_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	layer.add_child(tr)

	var tw := layer.create_tween()
	var n := int(FLASH_DURATION / FLASH_INTERVAL)
	for i: int in n:
		tw.tween_property(tr, "modulate:a", 1.0, 0.0)
		tw.tween_interval(FLASH_INTERVAL - FADE_TIME)
		tw.tween_property(tr, "modulate:a", 0.0, FADE_TIME)
	tw.tween_callback(layer.queue_free)
