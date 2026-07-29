extends CharacterBody2D
class_name RubiconPlayer
## Placeholder free-flight controller for Rubicon — 8-directional, unbounded (no world edge; matches the
## "đi mọi hướng, vô tận" requirement). Reuses the project's existing move_up/down/left/right input actions
## (see project.godot [input]) rather than ui_*, to match arena.gd's convention. Visual is a plain triangle
## until a real plane sprite/model is supplied — swap _build_visual() then.

const MOVE_SPEED := 260.0
const TURN_SPEED := 10.0

func _ready() -> void:
	_build_visual()
	var shape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 14.0
	shape.shape = circ
	add_child(shape)

func _build_visual() -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -18), Vector2(14, 14), Vector2(0, 6), Vector2(-14, 14)])
	poly.color = Color(0.90, 0.92, 0.96)
	add_child(poly)

func _physics_process(delta: float) -> void:
	var dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if dir.length() > 1.0:
		dir = dir.normalized()
	velocity = dir * MOVE_SPEED
	move_and_slide()
	if dir.length() > 0.05:
		var target_rot := dir.angle() + PI * 0.5   # placeholder nose points "up" at rotation 0
		rotation = lerp_angle(rotation, target_rot, TURN_SPEED * delta)
