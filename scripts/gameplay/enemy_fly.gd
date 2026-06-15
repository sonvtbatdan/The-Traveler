extends "res://scripts/gameplay/enemy_base.gd"

## Fly — one member of a FliesFlock (20 total, 2 concentric rings).
## Starts at its ring position, then continuously picks random scatter targets within the play area
## and flies toward them.  No dive — just contact explosion.

const FL_HP: float = 10.0
const FL_XP: int = 2
const FL_CONTACT_DMG: int = 5
const FL_SPEED: float = 120.0
const FL_SCATTER_INTERVAL: float = 1.0
const FL_SCATTER_MARGIN: float = 60.0
const FL_ARRIVE_DIST: float = 8.0

var _scatter_target: Vector2 = Vector2.ZERO
var _scatter_acc: float = 0.0

func _configure() -> void:
	_hp_mult = 1.0
	hp_max = FL_HP
	xp_reward = FL_XP
	contact_damage = FL_CONTACT_DMG
	contact_explodes = true
	contact_active = true
	body_color = Color(0.7, 0.5, 0.9)
	shape_kind = "circle"
	icon_path = "res://assets/enemies/animalflies.png"

## Flock calls this after add_child to set the starting ring position.
func set_initial_pos(pos: Vector2) -> void:
	position = pos - size * 0.5
	_scatter_acc = randf() * FL_SCATTER_INTERVAL   # stagger initial scatter so they don't all move at once

func _tick(delta: float) -> void:
	if _mgr == null:
		return
	_scatter_acc += delta
	if _scatter_acc >= FL_SCATTER_INTERVAL or center().distance_to(_scatter_target) <= FL_ARRIVE_DIST:
		_scatter_acc = 0.0
		_pick_scatter_target()
	var to := _scatter_target - center()
	if to.length() > 1.0:
		position += to.normalized() * FL_SPEED * delta

func _pick_scatter_target() -> void:
	var screen: Vector2 = _mgr.screen_size()
	_scatter_target = Vector2(
		randf_range(FL_SCATTER_MARGIN, screen.x - FL_SCATTER_MARGIN),
		randf_range(FL_SCATTER_MARGIN, screen.y * 0.85 - FL_SCATTER_MARGIN)
	)
