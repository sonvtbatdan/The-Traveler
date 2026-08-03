extends Node2D
class_name RubiconTrees
## Manages the Rubicon map's scattered 3D assets (trees/temples/etc, one per .glb in assets/map/rubicon/ —
## see RubiconAssetScan). Real, LIVE 3D models, not baked sprites — a static 2D bake captures one fixed
## camera angle forever, and the only way to fake "variety" was rotating that flat image in-plane, which
## broke the illusion (a tilted-perspective bake, rotated 90° in 2D, reads as the tree tipping over, not
## standing). Random variety here comes from the vertical (Y) axis — every instance faces a different
## direction, like a real forest — plus a small random lean around Z (TILT_MAX_DEG) so they don't all stand
## perfectly ramrod-straight either.
##
## This node owns the SHARED 3D world (one small "host" SubViewport holding the World3D + 2 lights + a
## transparent environment + the Node3D root all scattered instances are parented under), a real 3D cloud
## OCCLUDER mesh (a translucent box at RubiconConfig.CLOUD_MIN_PX..CLOUD_MAX_PX, tracking the camera every
## frame), and runs the scatter/placement logic.
##
## Asset instances and the cloud occluder all render in ONE combined pass (RubiconAssetLayer) — this is
## deliberate: putting them in the SAME World3D/camera means the engine's own per-pixel depth test clips a
## tall asset against the cloud box for free (the part above the box occludes it — pokes through; the part
## below gets occluded BY it — stays "under the clouds"), instead of the old whole-object above/below-cloud
## routing (an entire tall temple used to render entirely in front of the clouds, base included, which was
## wrong — see the git history around "camera đang là góc top down" for the discussion that led here).
##
## Per-asset independent Blur (Terrain Edit panel) can't be "this type's own separate composite" anymore
## (there's only one color composite now) — instead every placed instance gets a lightweight PROXY twin
## (same mesh, flat rubicon_blur_mask.gdshader material, tagged with that instance's own blur amount via a
## per-instance shader uniform) rendered into a second pass. RubiconAssetLayer reads both passes and applies
## a per-pixel variable blur radius, so two asset types standing side by side can still have independently
## different blur amounts. See rubicon_asset_layer.gd's header for the full two-pass composite picture.
##
## Camera projection is ORTHOGONAL, tilted CAM_ISO_DEG (RubiconAssetLayer) — matches arena.gd's SHIP_ISO_DEG
## for visual consistency, and critically must NOT be perspective: the ground/grass layers scroll LINEARLY
## (world_offset is a flat translation, no depth falloff), while a perspective camera's translation-over-a-
## plane has depth-dependent apparent motion, so the two would drift apart as the player moves. Orthogonal
## removes that drift entirely — BUT the tilt alone still under-scrolls the tilt axis by cos(CAM_ISO_DEG)
## (the camera's actual on-screen "up" is a Y/Z mix, not pure Z) — measured empirically: a 50px world move
## only produced ~44px of on-screen movement vs the ground's true 50px. `_z_comp` (1/cos(CAM_ISO_DEG),
## applied in RubiconAssetLayer.update_view and this script's _place_instance) cancels that out exactly.
##
## Altitude model: see RubiconConfig's TERRAIN_HEIGHT_PX/CLOUD_MIN_PX/CLOUD_MAX_PX/SHIP_HEIGHT_PX (single
## source of truth). CLOUD_ALTITUDE_PX below mirrors RubiconConfig.CLOUD_MAX_PX (the top of the cloud band) —
## it's now purely an informational threshold (Terrain Edit panel's Height readout); actual clipping is real
## per-pixel depth testing against the cloud occluder mesh, not a height comparison in this script.

const RubiconNoise := preload("res://scripts/gameplay/rubicon/rubicon_noise.gd")
const RubiconConfig := preload("res://scripts/gameplay/rubicon/rubicon_config.gd")
const RubiconAssetScan := preload("res://scripts/gameplay/rubicon/rubicon_asset_scan.gd")
const RubiconTerrainSettings := preload("res://scripts/gameplay/rubicon/rubicon_terrain_settings.gd")
const RubiconAssetLayerScript := preload("res://scripts/gameplay/rubicon/rubicon_asset_layer.gd")
const CLOUD_OCCLUDER_SHADER := "res://scripts/gameplay/rubicon/rubicon_cloud_occluder.gdshader"
const BLUR_MASK_SHADER := "res://scripts/gameplay/rubicon/rubicon_blur_mask.gdshader"

const CELL_SIZE_MAX := 110.0        # grid spacing for candidate positions at low/default density (world px)
const CELL_SIZE_MIN := 18.0         # ...shrinks toward this as the densest enabled type approaches 100, so
                                     # small-footprint assets actually get enough CANDIDATE positions to pack
                                     # edge-to-edge instead of being capped by a coarse grid regardless of
                                     # how tight their own footprint-radius overlap check would allow.
const DESIRED_HEIGHT_PX := 110.0    # each type's scale_min=scale_max=1.0 renders about this tall
const MAX_INSTANCES_PER_TYPE := 2000 # real Node3D instances (not MultiMesh slots) — raised well past the old
                                      # 200 so a fine grid at max density doesn't fill just one screen corner
                                      # before hitting the cap (dev-only feature; pushing many types to 100
                                      # density at once will cost real frame time — that's an accepted tradeoff)
const REGEN_MOVE_THRESHOLD := 160.0 # rebuild the instance set once the focus drifts this far
const MARGIN := 140.0               # extra world-space margin beyond the camera view rect
const CLOUD_ALTITUDE_PX := RubiconConfig.CLOUD_MAX_PX   # informational only now — see header comment
const CLOUD_BOX_HALF_EXTENT := 2200.0   # generous XZ half-size so its edges never scroll on-screen
const TILT_MAX_DEG := 8.0    # random lean around Z, on top of the Y-axis facing yaw — natural, not tipped over

var _host_vp: SubViewport      # tiny, never displayed directly — just holds the shared World3D
var _world3d_root: Node3D
var _cloud_occluder: MeshInstance3D
var _asset_layer: RubiconAssetLayer
var _blur_mask_material: ShaderMaterial
var _types: Array = []             # [{name, packed, scale(ref dim factor), offset}]
var _placed: Dictionary = {}       # Vector3(cell.x, cell.y, type_idx) -> {outer, proxy, type_idx, pos, radius}
                                    # — one candidate cell can hold up to ONE instance PER TYPE (each type
                                    # rolls its own independent chance + its own jittered offset within the
                                    # cell — see _maybe_place); persists ACROSS _regenerate() calls, see that
                                    # func's header for why.
var _count_by_type: Array = []     # per-type live instance count (MAX_INSTANCES_PER_TYPE cap)
var _settings_by_type: Dictionary = {}   # type_name -> {density, scale_min, scale_max, blur}
var _last_center: Vector2 = Vector2.ZERO        # current frame's focus (apply_asset_setting's live-regen anchor)
var _last_regen_center: Vector2 = Vector2.ZERO  # focus at the time of the last _regenerate() — drift is measured from THIS
var _has_last_center: bool = false
var _view_size: Vector2 = Vector2(1440.0, 780.0)
var _types_ready: bool = false
var _z_comp: float = 1.0
var _river_width: float = 0.0
var _placed_positions: Array = []   # {pos, radius} per instance this regen pass, ACROSS all types — no-overlap check
var _jitter: float = RubiconTerrainSettings.DEFAULT_JITTER   # fraction of _cell_size — Terrain Edit panel's Jitter slider
var _cell_size: float = CELL_SIZE_MAX   # recomputed each _regenerate() from the densest enabled type's density

func _ready() -> void:
	add_to_group("rubicon_trees")   # so the Terrain Edit panel can find this instance
	_z_comp = 1.0 / cos(deg_to_rad(RubiconAssetLayerScript.CAM_ISO_DEG))
	_build_host()
	_build_cloud_occluder()
	await get_tree().process_frame
	await _measure_types()

	_asset_layer = RubiconAssetLayerScript.new()
	add_child(_asset_layer)
	_asset_layer.setup(_host_vp.world_3d)

	var s := RubiconTerrainSettings.load_settings()
	for t: Dictionary in _types:
		_count_by_type.append(0)
		_settings_by_type[t["name"]] = RubiconTerrainSettings.asset_entry(s, t["name"])
	_river_width = float(s["river_width"])
	_jitter = float(s["jitter"])

	_types_ready = true

func _build_host() -> void:
	_host_vp = SubViewport.new()
	_host_vp.size = Vector2i(4, 4)   # never displayed — only exists to host the shared World3D + lights
	_host_vp.world_3d = World3D.new()
	add_child(_host_vp)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-100.0, 20.0, 0.0)   # mostly overhead, slight angle for shading form
	key.light_energy = 1.6
	_host_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-80.0, -160.0, 0.0)
	fill.light_energy = 0.7
	_host_vp.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)   # transparent — every layer composites over the ground below
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 0.98)
	env.ambient_light_energy = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	_host_vp.add_child(we)

	_world3d_root = Node3D.new()
	_host_vp.add_child(_world3d_root)
	_blur_mask_material = ShaderMaterial.new()
	_blur_mask_material.shader = load(BLUR_MASK_SHADER)

## Real 3D geometry, not a 2D trick — a single flat quad at the midpoint of RubiconConfig.CLOUD_MIN_PX..
## CLOUD_MAX_PX in the SAME World3D as the scattered instances, so ordinary depth testing clips them against
## each other per-pixel. A single face, not a box: a box's near+far faces would BOTH blend along the same
## view ray (transparent geometry doesn't self-occlude), roughly doubling the apparent alpha — a thin flat
## plane reads as the intended "10px-thick band" without that. Repositioned (not resized) every frame in
## update_view() to track the camera; CLOUD_BOX_HALF_EXTENT is generous enough that its edges never scroll
## into view.
func _build_cloud_occluder() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(CLOUD_BOX_HALF_EXTENT * 2.0, CLOUD_BOX_HALF_EXTENT * 2.0)

	var mat := ShaderMaterial.new()
	mat.shader = load(CLOUD_OCCLUDER_SHADER)
	mat.set_shader_parameter("tex_cloud", _make_noise_tex())

	_cloud_occluder = MeshInstance3D.new()
	_cloud_occluder.mesh = plane
	_cloud_occluder.material_override = mat
	_cloud_occluder.layers = RubiconAssetLayerScript.COLOR_BIT
	_world3d_root.add_child(_cloud_occluder)

	var s := RubiconTerrainSettings.load_settings()
	apply_cloud_settings(s["cloud_opacity"], s["cloud_brightness"], s["cloud_color"], s["cloud_clumpiness"])

func _make_noise_tex() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = 16.0 / 1024.0
	n.fractal_octaves = 4
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = 77
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 1024
	tex.seamless = true
	tex.normalize = true
	tex.noise = n
	return tex

## Public: called by the Terrain Edit panel (live, on slider/ColorPickerButton change) and by this node's own
## _ready() (persisted settings). `opacity_mult` scales the cloud occluder's own base alpha; `color` is the
## base tint and `brightness_mult` scales its intensity toward white-out (>1) or grey/black (<1). `clumpiness`
## (0..1) matches rubicon_clouds.gdshader's mass/detail treatment so the occluder's real depth-clipping shape
## visually agrees with the decorative 2D cloud layer above it.
func apply_cloud_settings(opacity_mult: float, brightness_mult: float, color: Color, clumpiness: float) -> void:
	if _cloud_occluder == null:
		return
	var mat: ShaderMaterial = _cloud_occluder.material_override
	mat.set_shader_parameter("max_alpha", 0.3 * opacity_mult)
	mat.set_shader_parameter("cloud_color", color * brightness_mult)
	mat.set_shader_parameter("clumpiness", clumpiness)

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). Keeps scattered assets off the SAME river band rubicon_ground.gdshader paints
## (RubiconNoise.is_river uses the same frequency/level) — width 0 disables river avoidance entirely.
func apply_river_width(width: float) -> void:
	_river_width = width
	if _types_ready:
		_regenerate(_last_center, true)

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). Fraction of _cell_size each candidate position is randomly offset by — 0 = a rigid
## grid, higher = more organic scatter. Lower values reduce how often two adjacent cells' own footprints
## overlap (see _place_instance's radius-sum check), so a high-density asset can pack in closer to actually
## filling the available cells instead of visibly gapping between canopies.
func apply_jitter(jitter: float) -> void:
	_jitter = jitter
	if _types_ready:
		_regenerate(_last_center, true)

## Measures each discovered .glb's own AABB ONCE (probe instance, freed right after) so every scattered copy
## can be scaled to DESIRED_HEIGHT_PX and recentered (base on the ground, centered XZ) regardless of however
## the source model happens to be authored/scaled/offset.
func _measure_types() -> void:
	for glb_path: String in RubiconAssetScan.glb_paths():
		var def: Dictionary = await _measure_one(glb_path)
		if not def.is_empty():
			_types.append(def)

## Shared by _measure_types() (regular scatter pool) and spawn_landmark() (one-off boss/landmark objects,
## e.g. rubicon_temple_layer.gd, whose .glb is excluded from the regular pool — see
## RubiconAssetScan.SCATTER_EXCLUDED) — same AABB-probe measurement either way.
func _measure_one(glb_path: String) -> Dictionary:
	var packed := load(glb_path) as PackedScene
	if packed == null:
		return {}
	var probe := packed.instantiate() as Node3D
	_world3d_root.add_child(probe)
	await get_tree().process_frame   # global_transform isn't valid until this fresh node has rendered once
	var aabb := RubiconAssetScan.combined_aabb(probe)
	# Scale by whichever dimension is LARGER — height for a tall/thin tree, footprint diagonal for a
	# wide/flat structure like the temple.
	var footprint_diag: float = Vector2(aabb.size.x, aabb.size.z).length()
	var ref_dim: float = maxf(maxf(aabb.size.y, footprint_diag), 0.001)
	var center_xz := Vector2(aabb.position.x + aabb.size.x * 0.5, aabb.position.z + aabb.size.z * 0.5)
	probe.queue_free()
	return {
		"name": RubiconAssetScan.type_name(glb_path),
		"packed": packed,
		"scale": DESIRED_HEIGHT_PX / ref_dim,
		"offset": Vector3(-center_xz.x, -aabb.position.y, -center_xz.y),
		"footprint_radius": footprint_diag * 0.5,   # raw (pre-scale) — _place_instance multiplies by scale*total_mult
		"half_extent": Vector2(aabb.size.x, aabb.size.z) * 0.5,   # raw (pre-scale) box half-extents (x, z) of the
		                                                            # model's own base footprint — used by
		                                                            # spawn_landmark() for a footprint-shaped (not
		                                                            # circular) ground ring, see its own comment
	}

## Public: places a single instance of `glb_path` at an explicit world position, OUTSIDE the density-scatter
## system entirely — not tracked in _placed/_count_by_type, never touched by _regenerate()'s view-based
## clear/rebuild. For one-off landmark/boss objects (e.g. the temple boss, rubicon_temple_layer.gd) whose
## lifetime is owned by whatever spawned them (a game-logic event — the boss dying — not camera distance).
## Caller owns the returned Node3D and must queue_free() it when the landmark should disappear. Upright (no
## random tilt, unlike wild-tree scatter) since a landmark should look deliberately placed, not windswept.
## `scale_mult` (default 1.0 = the same DESIRED_HEIGHT_PX auto-scale every scattered type gets) lets a landmark
## be deliberately bigger/smaller than that baseline — the returned "radius" scales with it too, so a caller's
## 2D hit-circle stays sized to match what's actually on screen. The returned "half_extent"/"yaw" describe the
## model's actual BASE footprint (an oriented box, not a circle) for the ground ring (rubicon_ground.gd's
## apply_landmarks / rubicon_ground.gdshader) to hug the real base contact instead of floating a circle around
## it — half_extent is the model's RAW local (pre-rotation) half-extent, deliberately NOT pre-divided by
## _z_comp here: the ground shader does the full inverse rotate+shear itself (see its landmark ring comment)
## so the box edge lands exactly on the model's true on-screen silhouette at ANY yaw, not just yaw=0/90/180/270
## (an earlier version pre-divided here, which is only exact at those four angles and visibly skewed the ring
## off the model's real edges at other angles). Returns {} if `glb_path` fails to load.
func spawn_landmark(glb_path: String, world_pos: Vector2, scale_mult: float = 1.0) -> Dictionary:
	var def: Dictionary = await _measure_one(glb_path)
	if def.is_empty():
		return {}
	var yaw := randf() * TAU
	var final_scale: float = float(def["scale"]) * scale_mult
	var outer := Node3D.new()
	outer.position = Vector3(world_pos.x, 0.0, world_pos.y * _z_comp)
	outer.rotation = Vector3(0.0, yaw, 0.0)
	outer.scale = Vector3.ONE * final_scale
	var inner := (def["packed"] as PackedScene).instantiate() as Node3D
	inner.position = def["offset"]
	outer.add_child(inner)
	_world3d_root.add_child(outer)
	RubiconAssetScan.set_visual_layers(outer, RubiconAssetLayerScript.COLOR_BIT)
	var half_extent: Vector2 = Vector2(def["half_extent"]) * final_scale
	return {
		"node": outer,
		"radius": float(def["footprint_radius"]) * final_scale,
		"half_extent": half_extent,
		"yaw": yaw,
	}

## Public: called by the Terrain Edit panel (live, on slider change) and effectively by this node's own
## _ready() (persisted settings, via _settings_by_type directly). Updates ONE asset type's Density/
## Scale-range/Bias/Blur/Enabled independently of every other type — every future scattered instance of this
## type rolls its own random scale in [scale_min, scale_max], skewed toward one end by scale_bias, and gets
## its own blur-mask proxy value. `enabled=false` stops this type from spawning at all, regardless of density
## (a separate on/off from density so re-enabling restores the exact density you had tuned before).
func apply_asset_setting(type_name: String, density: float, scale_min: float, scale_max: float, scale_bias: float, blur: float, enabled: bool = true) -> void:
	_settings_by_type[type_name] = {"density": density, "scale_min": scale_min, "scale_max": scale_max, "scale_bias": scale_bias, "blur": blur, "enabled": enabled}
	# Density/scale/blur/enabled changed what the NEXT regen would place — force one now instead of waiting
	# for the player to drift REGEN_MOVE_THRESHOLD px so the panel's controls feel live. `true` forces a full
	# clear+rebuild (not just the new-area diff _regenerate normally does on movement) since already-placed
	# cells may need a different outcome under the new settings.
	if _types_ready:
		_regenerate(_last_center, true)

func _type_index(type_name: String) -> int:
	for i in _types.size():
		if _types[i]["name"] == type_name:
			return i
	return -1

## Call every frame with the camera's world-space focus and the viewport size.
func update_view(center: Vector2, view_size: Vector2) -> void:
	_view_size = view_size
	_last_center = center
	if _asset_layer != null:
		_asset_layer.update_view(center, view_size)
	_cloud_occluder.position = Vector3(center.x, (RubiconConfig.CLOUD_MIN_PX + RubiconConfig.CLOUD_MAX_PX) * 0.5, center.y * _z_comp)
	if not _types_ready:
		return
	if _has_last_center and center.distance_to(_last_regen_center) < REGEN_MOVE_THRESHOLD:
		return
	_has_last_center = true
	_last_regen_center = center
	_regenerate(center)

## `force_full=false` (the movement-triggered path, via update_view): DIFFS against whatever's already
## placed instead of rebuilding from scratch. Grid cells are globally aligned (floor(pos/_cell_size)*
## _cell_size, not relative to `center`), so a cell's placement outcome never depends on which regen call
## computed it — it's always safe to just keep an already-placed instance if it's still within the new view
## bounds, freeing only the ones that drifted out and adding only the newly-exposed cells. This turns the
## PER-MOVEMENT cost from "the whole view+margin rect, every ~160px" into "just the new sliver of cells that
## movement exposed" — the former was fine at the old fixed 200-cap/110px grid, but became a real per-frame
## hitch once density-driven settings pushed the grid down toward CELL_SIZE_MIN and the cap up to 2000 (a
## single regen could synchronously instantiate thousands of Node3D scenes in one frame otherwise).
##
## `force_full=true` (settings changed: density/scale/blur/enabled/jitter/river/cell-size) clears everything
## first — an already-placed cell's OWN outcome can change under new settings even though its position never
## left the view, so the diff above can't be trusted; only genuine camera movement can skip straight to it.
func _regenerate(center: Vector2, force_full: bool = false) -> void:
	if _types.is_empty():
		return

	# Grid resolution ITSELF shrinks toward the densest enabled type's density (same idea as _jitter): at
	# low/default density the old coarse 110px grid is plenty, but a small-footprint asset pushed to 100
	# density needs far MORE candidate positions than a 110px grid offers to actually pack edge-to-edge —
	# its own footprint-radius overlap check (_place_instance) is already fine with much closer neighbors,
	# the grid was the thing capping it. A large asset isn't hurt by the finer grid either: it just keeps
	# getting rejected by its own (larger) radius check on the extra in-between candidates.
	var max_density: float = 0.0
	for t: Dictionary in _types:
		var s: Dictionary = _settings_by_type.get(t["name"], RubiconTerrainSettings.default_asset_entry())
		if bool(s.get("enabled", true)):
			max_density = maxf(max_density, float(s["density"]))
	var new_cell_size: float = lerpf(CELL_SIZE_MAX, CELL_SIZE_MIN, clampf(max_density / 100.0, 0.0, 1.0))
	if force_full or not is_equal_approx(new_cell_size, _cell_size):
		_clear_all()
	_cell_size = new_cell_size

	var half: Vector2 = _view_size * 0.5 + Vector2(MARGIN, MARGIN)
	var min_p: Vector2 = center - half
	var max_p: Vector2 = center + half

	# Free whatever fell outside the new bounds.
	for key: Vector3 in _placed.keys().duplicate():
		var entry: Dictionary = _placed[key]
		var p: Vector2 = entry["pos"]
		if p.x < min_p.x or p.x > max_p.x or p.y < min_p.y or p.y > max_p.y:
			if is_instance_valid(entry["outer"]):
				entry["outer"].queue_free()
			if is_instance_valid(entry["proxy"]):
				entry["proxy"].queue_free()
			_count_by_type[entry["type_idx"]] -= 1
			_placed.erase(key)

	# Seed the overlap-check accumulator with everything kept, then fill in only the newly-exposed cells.
	# (_maybe_place itself skips any (cell, type) pair already present in _placed, so re-scanning cells that
	# are still fully covered from the last pass costs only cheap hash checks, no wasted instantiation.)
	_placed_positions = []
	for key: Vector3 in _placed:
		var entry: Dictionary = _placed[key]
		_placed_positions.append({"pos": entry["pos"], "radius": entry["radius"]})

	var start_x: float = floor(min_p.x / _cell_size) * _cell_size
	var start_y: float = floor(min_p.y / _cell_size) * _cell_size

	var x := start_x
	while x < max_p.x:
		var y := start_y
		while y < max_p.y:
			_maybe_place(Vector2(x, y))
			y += _cell_size
		x += _cell_size

## Frees every currently-placed instance (used when a settings change means cached placements can no longer
## be trusted — see _regenerate's header).
func _clear_all() -> void:
	for key: Vector3 in _placed:
		var entry: Dictionary = _placed[key]
		if is_instance_valid(entry["outer"]):
			entry["outer"].queue_free()
		if is_instance_valid(entry["proxy"]):
			entry["proxy"].queue_free()
	_placed.clear()
	for i in _count_by_type.size():
		_count_by_type[i] = 0

## Every ENABLED type gets its OWN independent roll for this cell (chance = density/100, no biome or other
## type's outcome involved) and, if it hits, its OWN jittered position (offset also depends on the type
## index, not just the cell — so different types don't all contend for the exact same point). This is what
## makes each type's realized on-screen fill % depend ONLY on its own Density slider: previously all types
## shared one identical jittered position per cell and the first type to roll a hit in a shuffled per-cell
## order silently claimed it, so a type's real spawn rate dropped the more OTHER types were enabled — not
## because of anything the user set. The only interaction between types now is genuine physical overlap
## (_place_instance's footprint-radius check against everything already placed this pass, across all types)
## — "no room left" skips that one placement, exactly like density=0 would, instead of forcing it in anyway.
## Water/river avoidance (RubiconNoise.is_river) is the one remaining exclusion zone, checked per type against
## its OWN jittered position since that position differs per type.
##
## Iteration order is shuffled PER CELL (start_i) so that under genuine physical contention (more types
## wanting space than the cell area can hold — an inherent capacity limit, not a bug), no single type
## systematically loses every tie just for sitting later in the discovery order; averaged over many cells,
## every type gets a fair, roughly-equal share of the "goes first" slot.
func _maybe_place(cell: Vector2) -> void:
	if _types.is_empty():
		return
	var start_i: int = int(RubiconNoise.hash21(cell + Vector2(17.0, 17.0)) * _types.size())
	for k in _types.size():
		var i: int = (start_i + k) % _types.size()
		var type_def: Dictionary = _types[i]
		var settings: Dictionary = _settings_by_type.get(type_def["name"], RubiconTerrainSettings.default_asset_entry())
		if not bool(settings.get("enabled", true)):
			continue
		var key := Vector3(cell.x, cell.y, float(i))
		if _placed.has(key):
			continue
		var chance: float = clampf(float(settings["density"]) / 100.0, 0.0, 1.0)
		var roll: float = RubiconNoise.hash21(cell * 1.271 + Vector2(300.0 + float(i) * 47.0, 900.0 + float(i) * 91.0))
		if roll >= chance:
			continue
		if int(_count_by_type[i]) >= MAX_INSTANCES_PER_TYPE:
			continue
		var jitter := Vector2(
			(RubiconNoise.hash21(cell + Vector2(23.0 + float(i) * 13.0, 0.0)) - 0.5) * _cell_size * _jitter,
			(RubiconNoise.hash21(cell + Vector2(0.0, 23.0 + float(i) * 13.0)) - 0.5) * _cell_size * _jitter
		)
		var pos := cell + jitter
		if _river_width > 0.0 and RubiconNoise.is_river(pos, _river_width):
			continue
		_place_instance(key, cell, pos, i, type_def, settings)

## Returns true if placed. Rejects (returns false, places nothing) only on a genuine footprint OVERLAP with
## an already-placed instance this regen pass — no arbitrary flat minimum distance, just real per-instance
## radii (footprint_radius * type scale * this roll's own total_mult) summed and compared to actual distance.
func _place_instance(key: Vector3, cell: Vector2, pos: Vector2, type_idx: int, type_def: Dictionary, settings: Dictionary) -> bool:
	var yaw: float = RubiconNoise.hash21(cell + Vector2(99.0 + float(type_idx) * 7.0, 3.0)) * TAU   # spin around the trunk only — stays upright
	var raw_roll: float = RubiconNoise.hash21(cell + Vector2(-7.0, 5.0 + float(type_idx) * 7.0))   # 0..1, this cell+type's fixed point in the range
	# scale_bias skews which end of [scale_min, scale_max] comes up more often — 0.5 is uniform (no skew),
	# 0.0 raises raw_roll to a HIGH power (pushes most rolls toward 0 → mostly small), 1.0 lowers it to a
	# power < 1 (pushes most rolls toward 1 → mostly large). See RubiconTerrainSettings.DEFAULT_ASSET_SCALE_BIAS.
	var bias: float = float(settings.get("scale_bias", 0.5))
	var skew_pow: float = pow(4.0, (0.5 - bias) * 2.0)
	var scale_roll: float = pow(raw_roll, skew_pow)
	var total_mult: float = lerpf(float(settings["scale_min"]), float(settings["scale_max"]), scale_roll)

	var radius: float = float(type_def["footprint_radius"]) * float(type_def["scale"]) * total_mult
	for existing: Dictionary in _placed_positions:
		if pos.distance_to(existing["pos"]) < (radius + float(existing["radius"])):
			return false

	var tilt: float = (RubiconNoise.hash21(cell + Vector2(41.0 + float(type_idx) * 7.0, -19.0)) - 0.5) * 2.0 * deg_to_rad(TILT_MAX_DEG)

	var xform_pos := Vector3(pos.x, 0.0, pos.y * _z_comp)   # ground level; _z_comp cancels the tilt's cos() foreshortening on Z
	var xform_rot := Vector3(0.0, yaw, tilt)                 # Y = facing direction, Z = a slight random lean
	var xform_scale := Vector3.ONE * (float(type_def["scale"]) * total_mult)

	var outer := Node3D.new()
	outer.position = xform_pos
	outer.rotation = xform_rot
	outer.scale = xform_scale
	var inner := (type_def["packed"] as PackedScene).instantiate() as Node3D
	inner.position = type_def["offset"]   # recenters XZ and rests the model's own AABB base on outer's y=0
	outer.add_child(inner)
	_world3d_root.add_child(outer)
	RubiconAssetScan.set_visual_layers(outer, RubiconAssetLayerScript.COLOR_BIT)

	# Lightweight blur-mask twin: same silhouette, flat material encoding this TYPE's own blur amount, seen
	# only by the blur-mask pass's camera (RubiconAssetLayer.BLUR_BIT) — see this file's header comment.
	var proxy := Node3D.new()
	proxy.position = xform_pos
	proxy.rotation = xform_rot
	proxy.scale = xform_scale
	var proxy_inner := (type_def["packed"] as PackedScene).instantiate() as Node3D
	proxy_inner.position = type_def["offset"]
	proxy.add_child(proxy_inner)
	_world3d_root.add_child(proxy)
	RubiconAssetScan.set_visual_layers(proxy, RubiconAssetLayerScript.BLUR_BIT)
	RubiconAssetScan.set_flat_material(proxy, _blur_mask_material)
	RubiconAssetScan.set_instance_blur_param(proxy, float(settings["blur"]))

	_placed[key] = {"outer": outer, "proxy": proxy, "type_idx": type_idx, "pos": pos, "radius": radius}
	_count_by_type[type_idx] += 1
	_placed_positions.append({"pos": pos, "radius": radius})
	return true
