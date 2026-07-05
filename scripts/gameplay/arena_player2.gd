extends Node2D
## Player 2 — a negative-colour copy of the ship that leash-follows the player (snake-style) and fires a 25%
## copy of the player's highest-level weapon via its OWN ArenaWeapons instance in "companion mode".
##
## This node is a MANAGER that stays at world origin so the companion weapon system draws in world space; only
## the `_ship` child actually moves. Spawned by arena_weapons.force_spawn_player2() — set `copied_kind` +
## `dmg_scale` BEFORE add_child().

const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")
const SHIP_SPRITE  := "res://assets/screen/Spaceship.png"
const SIZE_PX      := 44.0     # drawn size (px on the longest side)
const SHIP_Z       := 60
const LEASH_DIST   := 144.0    # trails this far behind the player before it starts catching up (+50%)
const FOLLOW_SPEED := 360.0    # catch-up speed (px/s)
const AIM_RANGE    := 900.0    # how far P2 looks for a target to face
const TURN_RATE    := 6.0      # max turn speed (rad/s) — fast but not instant

var copied_kinds: Array = []   # the weapons P2 copies (set by the spawner before add_child)
var dmg_scale: float = 0.25
var fam_bonus: Dictionary = {}  # family → bonus frac (Player 2 colour coats)
var procs_enabled: bool = false # Full Sync evolve → the copies can proc status/crit
var ship_index: int = 0         # 0 = P2, 1 = P3 (Ready Player 3) — offsets the follow point

var _ship: Node2D = null
var _weapons: Node = null

func _ready() -> void:
	global_position = Vector2.ZERO        # manager at world origin → companion weapons draw in world space
	_ship = Node2D.new()
	add_child(_ship)
	var pl := get_tree().get_first_node_in_group("player") as Node2D
	_ship.global_position = (pl.global_position + Vector2(0.0, 70.0)) if pl != null else Vector2.ZERO
	_ship.add_to_group("player_2")
	_build_sprite()
	# Companion weapon system, bound to the P2 ship, firing at reduced damage. Fields are read in its _ready().
	_weapons = ArenaWeaponsScript.new()
	_weapons.set("_companion", true)
	_weapons.set("_player_ref", _ship)
	_weapons.set("_dmg_scale", dmg_scale)
	_weapons.set("_p2_fam_bonus", fam_bonus)
	_weapons.set("_procs_enabled", procs_enabled)
	(_weapons as Node2D).position = Vector2.ZERO
	add_child(_weapons)
	for k in copied_kinds:
		_weapons.call_deferred("acquire_weapon", String(k))   # activate each copied weapon on P2

func _build_sprite() -> void:
	var spr := Sprite2D.new()
	var tex := load(SHIP_SPRITE) as Texture2D
	spr.texture = tex
	var longest := maxf(float(tex.get_width()), float(tex.get_height())) if tex != null else 1.0
	spr.scale = Vector2.ONE * (SIZE_PX / maxf(1.0, longest))
	spr.z_index = SHIP_Z
	# Negative (inverted) colours — output = 1 - rgb, alpha kept.
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){\n\tvec4 c = texture(TEXTURE, UV);\n\tCOLOR = vec4(vec3(1.0) - c.rgb, c.a);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	spr.material = mat
	_ship.add_child(spr)

func _physics_process(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	var pl := get_tree().get_first_node_in_group("player") as Node2D
	if pl != null:
		# Leash: catch up toward the player (offset per ship so P2/P3 don't overlap) once past the leash distance.
		var off := Vector2.ZERO if ship_index == 0 else Vector2(cos(float(ship_index) * 2.4), sin(float(ship_index) * 2.4)) * 80.0
		var to := (pl.global_position + off) - _ship.global_position
		var d := to.length()
		if d > LEASH_DIST:
			_ship.global_position += to.normalized() * minf(FOLLOW_SPEED * delta, d - LEASH_DIST)
	# Face the nearest enemy so directional weapons aim; else mirror the player's heading. Turn at a capped rate
	# (fast but not instantaneous) via the shortest angular path.
	var target_rot := _ship.rotation
	var tgt := _nearest_enemy()
	if tgt != null:
		target_rot = (tgt.global_position - _ship.global_position).angle() + PI * 0.5   # sprite up (-Y) = forward
	elif pl != null:
		target_rot = pl.rotation
	_ship.rotation += clampf(angle_difference(_ship.rotation, target_rot), -TURN_RATE * delta, TURN_RATE * delta)

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d := AIM_RANGE * AIM_RANGE
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var dd := _ship.global_position.distance_squared_to((e as Node2D).global_position)
		if dd < best_d:
			best_d = dd
			best = e as Node2D
	return best
