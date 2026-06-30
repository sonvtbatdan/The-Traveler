extends Node2D
## Large-scale gas/dust structure layer. Manual parallax (position = camera*(1-factor)) since structures are
## discrete. Streams ENORMOUS, RARE set-pieces deterministically by world cell (rarer + bigger cells than
## planets), so flying back finds the same structure in the same place. Four types: planetary nebula (ring/
## eye), reflection nebula, dark nebula, emission pillars. z_index keeps them in front of the star field
## (so the dark nebula occludes it) yet behind planets/comets/gameplay.

const StructureScript := preload("res://scripts/gameplay/arena_structure.gd")
const ArenaPopulator := preload("res://scripts/gameplay/arena_populator.gd")

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const STRUCTURE_FACTOR  := 0.25     # parallax: slower than planets (0.40) → farther/bigger-feeling
const STRUCTURE_Z       := -60      # in front of star field (-100), behind planets (-50)/comets (-48)
const STRUCTURE_TYPE_COUNT := 3     # types in rotation (0..2). Pillars (type 3) disabled for now → set 4 to re-enable
const SPAWN_PER_FRAME := 1          # max new structures streamed in per frame (amortized to kill movement hitch)
# Placement (cell size, rarity weight, jitter, min-distance, biome density) is unified in ArenaPopulator
# (type ArenaPopulator.STRUCTURE, setpiece group 0 → no two structures overlap). Only parallax + visuals here.

var _structures: Dictionary = {}    # Vector2i cell → structure node

func _ready() -> void:
	add_to_group("arena_structures")
	z_index = STRUCTURE_Z

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	position = cam.global_position * (1.0 - STRUCTURE_FACTOR)
	var cs := ArenaPopulator.cell_size(ArenaPopulator.STRUCTURE)
	var vc := cam.global_position * STRUCTURE_FACTOR     # layer-space view centre
	var vp := get_viewport().get_visible_rect().size / cam.zoom
	var half := vp * 0.5 + Vector2(cs, cs)
	var cx0 := int(floor((vc.x - half.x) / cs))
	var cx1 := int(ceil((vc.x + half.x) / cs))
	var cy0 := int(floor((vc.y - half.y) / cs))
	var cy1 := int(ceil((vc.y + half.y) / cs))
	var needed := {}
	var budget := SPAWN_PER_FRAME   # amortize: cap new structures/frame so crossing cells doesn't spike (rest fill in next frames)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := Vector2i(cx, cy)
			var place := ArenaPopulator.place_in_cell(ArenaPopulator.STRUCTURE, key)
			if not place.is_empty():
				needed[key] = true   # mark needed even if deferred, so it isn't despawned before it spawns
				if not _structures.has(key) and budget > 0:
					_spawn_cell(key, place["pos"], place["rng"])
					budget -= 1
	for key: Vector2i in _structures.keys():
		if not needed.has(key):
			if is_instance_valid(_structures[key]):
				_structures[key].despawn()
			_structures.erase(key)

func _spawn_cell(key: Vector2i, pos: Vector2, rng: RandomNumberGenerator) -> void:
	var type := rng.randi() % STRUCTURE_TYPE_COUNT   # uniform pick (pillars excluded for now)
	var params := StructureScript.roll_params(type, rng)
	var st := StructureScript.new()
	add_child(st)
	st.apply(params)
	st.position = pos
	_structures[key] = st

## Debug: spawn a structure of `type` at `world_pos` (tagged for Shift+F11 clear). Returns the node.
func spawn_structure_near(world_pos: Vector2, type: int, rng: RandomNumberGenerator) -> Node2D:
	var params := StructureScript.roll_params(type, rng)
	var st := StructureScript.new()
	st.add_to_group("debug_structure")
	add_child(st)
	st.apply(params)
	st.position = to_local(world_pos)
	return st

## Free all debug-spawned structures (Shift+F11).
func clear_debug() -> void:
	for n in get_tree().get_nodes_in_group("debug_structure"):
		if is_instance_valid(n):
			n.queue_free()
