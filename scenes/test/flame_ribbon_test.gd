extends Node2D
## Standalone tuning scene for the fire-ring reveal — run with F6. Spawns a FlameRingReveal centered on
## screen and auto-loops the full jet → draw → hold → burnout cycle. Press R to replay immediately.
## Tune the FlameRingReveal @export tunables (top of flame_ring_reveal.gd) and the per-ribbon look knobs
## (top of flame_ribbon.gd), then re-run.

const FlameRingReveal := preload("res://scripts/gameplay/flame_ring_reveal.gd")

var _reveal: Node2D = null

func _ready() -> void:
	_reveal = FlameRingReveal.new()
	add_child(_reveal)
	_reveal.position = Vector2(640.0, 360.0)
	_reveal.ring_radius = 240.0
	_reveal.auto_loop = true
	var lbl := Label.new()
	lbl.text = "Flame ring reveal — press R to replay   (jet → draw → hold → burnout, auto-loops)"
	lbl.position = Vector2(20.0, 16.0)
	add_child(lbl)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_reveal.restart()
