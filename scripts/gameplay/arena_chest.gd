extends Node2D
## A reward chest spawned far from the player at run start (one per run). Flying into it grants ONE level-up
## choice (the pick-1-of-3 card) WITHOUT increasing the player's level — then it despawns. An off-screen
## pointer (arena_chest_pointer.gd) guides the player to it. Group "arena_chest".

const COLLECT_RANGE := 72.0
const SIZE          := 38.0
const GOLD          := Color(1.0, 0.85, 0.35)

var _player: Node2D = null
var _t: float = 0.0
var _taken: bool = false

func _ready() -> void:
	add_to_group("arena_chest")
	z_index = 50   # above weapon FX (≤6), below the ship (100)

func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and global_position.distance_to(_player.global_position) <= COLLECT_RANGE:
		_collect()
		return
	queue_redraw()

func _collect() -> void:
	_taken = true
	var ui := get_tree().get_first_node_in_group("levelup_ui")
	if ui != null and ui.has_method("grant_reward"):
		ui.call("grant_reward")   # reward WITHOUT a real level-up
	queue_free()

func _draw() -> void:
	# Placeholder chest (no art yet): a glowing golden crate with a lid + lock, pulsing beacon aura.
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(Vector2.ZERO, SIZE * 1.6, Color(GOLD.r, GOLD.g, GOLD.b, 0.10 + 0.10 * pulse))   # beacon aura
	var hw := SIZE * 0.5
	var top := -SIZE * 0.32
	draw_rect(Rect2(-hw, top, SIZE, SIZE * 0.78), Color(0.42, 0.30, 0.14), true)                # body
	draw_rect(Rect2(-hw, top, SIZE, SIZE * 0.30), Color(0.60, 0.44, 0.20), true)                # lid
	draw_rect(Rect2(-hw, top, SIZE, SIZE * 0.78), GOLD, false, 3.0)                             # gold trim
	draw_line(Vector2(-hw, top + SIZE * 0.30), Vector2(hw, top + SIZE * 0.30), GOLD, 2.0)        # lid seam
	draw_circle(Vector2(0.0, top + SIZE * 0.34), 4.5, Color(1.0, 0.95, 0.6))                     # lock
