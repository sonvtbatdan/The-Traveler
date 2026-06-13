extends "res://scripts/gameplay/enemy_base.gd"

## Bomb — dropped by the Bombing_wanderer (a separate enemy). It slowly falls. It explodes when it
## touches the player OR when its HP reaches 0 (shot down). The explosion damages ALL factions — other
## enemies, the boss, AND the player — via EnemyManager.explode(). Gives no XP and no loot.
##
## HOW THE EXPLOSION HITS EVERY FACTION: it doesn't hit them itself — it asks the manager. See
## enemy_manager.gd explode(): player (ship circle → ship_take_damage), boss (boss hit rect →
## take_boss_damage), and every other enemy (the "normal_enemy" group → on_weapon_hit). The bomb passes
## itself as `source` so the blast never re-hits the bomb that fired it (and bomb→bomb chains safely).

# ── Tunable constants (Bomb) ──────────────────────────────────────────────────
const BOMB_HP: float = 50.0
const BOMB_DMG: int = 20            # explosion damage dealt to everything in range
const BOMB_RADIUS: float = 100.0    # explosion radius
const BOMB_FALL_SPEED: float = 160.0

func _configure() -> void:
	hp_max = BOMB_HP
	xp_reward = 0           # no XP
	contact_damage = 0      # the explosion deals the player damage, not a direct touch
	contact_explodes = true
	body_color = Color(1.0, 0.55, 0.15)   # orange
	shape_kind = "circle"
	icon_path  = "res://assets/enemies/bomb.png"
	size_mult  = 0.5

func _tick(delta: float) -> void:
	position += Vector2(0.0, BOMB_FALL_SPEED * delta)
	if _mgr != null:
		var screen: Vector2 = _mgr.screen_size()
		if center().y > screen.y + 60.0:
			despawn()   # fell off the bottom → fizzles, no explosion

func die() -> void:
	_explode()             # shot down (HP 0) → explode

func _on_contact_death() -> void:
	_explode()             # touched the player → explode

func _explode() -> void:
	if _dead:
		return
	_dead = true
	_unregister()
	if _mgr != null and _mgr.has_method("explode"):
		_mgr.explode(center(), BOMB_RADIUS, BOMB_DMG, self)
	queue_free()
