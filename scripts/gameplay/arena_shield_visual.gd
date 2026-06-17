extends Node2D
## Shield visual overlay added as a child of the player when the shield loot drop is collected.
## Breathes (±5% scale at 1.2 Hz) throughout and blinks rapidly in the final 3 seconds, then auto-frees.
## Purely visual — the immunity itself is managed by GameManager._shield_immune / _shield_timer.

const DURATION        := 10.0   # must match GameManager.activate_shield() call in arena_loot.gd
const BREATHE_AMP     := 0.05   # ±5% scale amplitude
const BREATHE_FREQ    := 1.2    # Hz
const BLINK_THRESHOLD := 3.0    # seconds before expiry at which blinking starts
const BLINK_ON        := 0.10   # seconds visible per blink cycle
const BLINK_CYCLE     := 0.20   # total blink cycle duration

var _t: float = 0.0
var _tex: Texture2D = null
var _draw_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	_tex = load("res://assets/defense/shield.png") as Texture2D
	if _tex != null:
		var tw := float(_tex.get_width())
		var th := float(_tex.get_height())
		_draw_size = Vector2(90.0, 90.0 * th / tw)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	# Blink in the final BLINK_THRESHOLD seconds
	if DURATION - _t <= BLINK_THRESHOLD:
		visible = fmod(_t, BLINK_CYCLE) < BLINK_ON
	else:
		visible = true
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	var s := 1.0 + BREATHE_AMP * sin(_t * TAU * BREATHE_FREQ)
	var sz := _draw_size * s
	draw_texture_rect(_tex, Rect2(-sz * 0.5, sz), false, Color(1.0, 1.0, 1.0, 0.7))
