extends "res://scripts/gameplay/enemy_base.gd"

## Centipede — a tough armored enemy that rotates at 20 rpm and steadily advances toward the player.
## Enters from a random edge.  Explodes on contact (20 damage, armor = 1).

const CE_HP: float = 240.0
const CE_XP: int = 24
const CE_CONTACT_DMG: int = 20
const CE_SPEED: float = 100.0
const CE_ROT_SPEED: float = TAU / 3.0   # 120°/s = 20 rpm

func _configure() -> void:
	_hp_mult = 1.0
	hp_max = CE_HP
	xp_reward = CE_XP
	armor = 1.0
	contact_damage = CE_CONTACT_DMG
	contact_explodes = true
	contact_active = true
	body_color = Color(0.4, 0.75, 0.2)
	shape_kind = "square"
	icon_path = "res://assets/enemies/animalcentipede.png"

func spawn(mgr: Node) -> void:
	_mgr = mgr
	var screen: Vector2 = mgr.screen_size()
	var edge := randi() % 4
	match edge:
		0: position = Vector2(randf_range(0.0, screen.x - size.x), -size.y)
		1: position = Vector2(randf_range(0.0, screen.x - size.x), screen.y)
		2: position = Vector2(-size.x, randf_range(0.0, screen.y - size.y))
		3: position = Vector2(screen.x, randf_range(0.0, screen.y - size.y))

func _tick(delta: float) -> void:
	if _mgr == null:
		return
	rotation += CE_ROT_SPEED * delta
	var to: Vector2 = _mgr.ship_center() - center()
	if to.length() > 1.0:
		position += to.normalized() * CE_SPEED * delta
