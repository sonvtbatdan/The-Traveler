extends "res://scripts/gameplay/enemy_base.gd"

## Phase 1 trivial enemy — stands still, takes damage, dies, grants XP. Exists only to verify the
## shared foundation (weapon hits + acid armor-shred + death + XP) before the real enemies are built.

# ── Tunable constants (Dummy) ─────────────────────────────────────────────────
const DUMMY_HP: float = 30.0
const DUMMY_XP: int = 5

func _configure() -> void:
	hp_max = DUMMY_HP
	xp_reward = DUMMY_XP
	armor = 0.0
	contact_damage = 0        # never touches the player
	contact_explodes = false
	body_color = Color(0.70, 0.75, 0.85)
	shape_kind = "circle"
