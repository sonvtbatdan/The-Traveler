extends Node2D
class_name RubiconTrees
## Manages the Rubicon map's scattered 3D assets (trees/temples/etc, one per .glb in assets/map/rubicon/ —
## see RubiconAssetScan). Real, LIVE 3D models, not baked sprites — a static 2D bake captures one fixed
## camera angle forever, and the only way to fake "variety" was rotating that flat image in-plane, which
## broke the illusion (a tilted-perspective bake, rotated 90° in 2D, reads as the tree tipping over, not
## standing). Random variety here is applied ONLY around the vertical (Y) axis — every instance stands
## upright, just facing a different direction, like a real forest.
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

const CELL_SIZE := 110.0            # grid spacing for candidate positions (world px)
const TREE_CHANCE_BLUE := 0.55      # base chance a candidate cell gets AN asset, on the grass zone (before per-asset density)
const TREE_CHANCE_SAND := 0.12      # ...on the sand zone (a few stragglers, not a hard biome gate)
const DESIRED_HEIGHT_PX := 110.0    # each type's scale_min=scale_max=1.0 renders about this tall
const MAX_INSTANCES_PER_TYPE := 200 # real Node3D instances (not MultiMesh slots) — plenty for one screen+margin
const REGEN_MOVE_THRESHOLD := 160.0 # rebuild the instance set once the focus drifts this far
const MARGIN := 140.0               # extra world-space margin beyond the camera view rect
const CLOUD_ALTITUDE_PX := RubiconConfig.CLOUD_MAX_PX   # informational only now — see header comment
const CLOUD_BOX_HALF_EXTENT := 2200.0   # generous XZ half-size so its edges never scroll on-screen
const MIN_ASSET_SPACING := 100.0    # no two scattered instances (any type) may land closer than this, world px

var _host_vp: SubViewport      # tiny, never displayed directly — just holds the shared World3D
var _world3d_root: Node3D
var _cloud_occluder: MeshInstance3D
var _asset_layer: RubiconAssetLayer
var _blur_mask_material: ShaderMaterial
var _types: Array = []             # [{name, packed, scale(ref dim factor), offset}]
var _instances_by_type: Array = [] # Array[Array[{outer, proxy}]] — placements currently alive, per type
var _settings_by_type: Dictionary = {}   # type_name -> {density, scale_min, scale_max, blur}
var _last_center: Vector2 = Vector2.ZERO        # current frame's focus (apply_asset_setting's live-regen anchor)
var _last_regen_center: Vector2 = Vector2.ZERO  # focus at the time of the last _regenerate() — drift is measured from THIS
var _has_last_center: bool = false
var _view_size: Vector2 = Vector2(1440.0, 780.0)
var _types_ready: bool = false
var _z_comp: float = 1.0
var _river_width: float = 0.0
var _placed_positions: Array = []   # every instance's world XZ this regen pass, ACROSS all types — MIN_ASSET_SPACING check

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
		_instances_by_type.append([])
		_settings_by_type[t["name"]] = RubiconTerrainSettings.asset_entry(s, t["name"])
	_river_width = float(s["river_width"])

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
	apply_cloud_settings(s["cloud_opacity"], s["cloud_brightness"])

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

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). `opacity_mult` scales the cloud occluder's own base alpha; `brightness_mult` scales
## its color toward white (>1) or grey/black (<1).
func apply_cloud_settings(opacity_mult: float, brightness_mult: float) -> void:
	if _cloud_occluder == null:
		return
	var mat: ShaderMaterial = _cloud_occluder.material_override
	mat.set_shader_parameter("max_alpha", 0.3 * opacity_mult)
	mat.set_shader_parameter("cloud_color", Color(1.0, 1.0, 1.0) * brightness_mult)

## Public: called by the Terrain Edit panel (live, on slider change) and by this node's own _ready()
## (persisted settings). Keeps scattered assets off the SAME river band rubicon_ground.gdshader paints
## (RubiconNoise.is_river uses the same frequency/level) — width 0 disables river avoidance entirely.
func apply_river_width(width: float) -> void:
	_river_width = width
	if _types_ready:
		_regenerate(_last_center)

## Measures each discovered .glb's own AABB ONCE (probe instance, freed right after) so every scattered copy
## can be scaled to DESIRED_HEIGHT_PX and recentered (base on the ground, centered XZ) regardless of however
## the source model happens to be authored/scaled/offset.
func _measure_types() -> void:
	for glb_path: String in RubiconAssetScan.glb_paths():
		var packed := load(glb_path) as PackedScene
		if packed == null:
			continue
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
		_types.append({
			"name": RubiconAssetScan.type_name(glb_path),
			"packed": packed,
			"scale": DESIRED_HEIGHT_PX / ref_dim,
			"offset": Vector3(-center_xz.x, -aabb.position.y, -center_xz.y),
		})

## Public: called by the Terrain Edit panel (live, on slider change) and effectively by this node's own
## _ready() (persisted settings, via _settings_by_type directly). Updates ONE asset type's Density/
## Scale-range/Bias/Blur independently of every other type — every future scattered instance of this type
## rolls its own random scale in [scale_min, scale_max], skewed toward one end by scale_bias, and gets its
## own blur-mask proxy value.
func apply_asset_setting(type_name: String, density: float, scale_min: float, scale_max: float, scale_bias: float, blur: float) -> void:
	_settings_by_type[type_name] = {"density": density, "scale_min": scale_min, "scale_max": scale_max, "scale_bias": scale_bias, "blur": blur}
	# Density/scale/blur changed what the NEXT regen would place — force one now instead of waiting for the
	# player to drift REGEN_MOVE_THRESHOLD px so the panel's sliders feel live.
	if _types_ready:
		_regenerate(_last_center)

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

func _regenerate(center: Vector2) -> void:
	if _types.is_empty():
		return
	for arr: Array in _instances_by_type:
		for entry: Dictionary in arr:
			if is_instance_valid(entry["outer"]):
				entry["outer"].queue_free()
			if is_instance_valid(entry["proxy"]):
				entry["proxy"].queue_free()
		arr.clear()
	_placed_positions.clear()

	var half: Vector2 = _view_size * 0.5 + Vector2(MARGIN, MARGIN)
	var min_p: Vector2 = center - half
	var max_p: Vector2 = center + half
	var start_x: float = floor(min_p.x / CELL_SIZE) * CELL_SIZE
	var start_y: float = floor(min_p.y / CELL_SIZE) * CELL_SIZE

	var x := start_x
	while x < max_p.x:
		var y := start_y
		while y < max_p.y:
			_maybe_place(Vector2(x, y))
			y += CELL_SIZE
		x += CELL_SIZE

## Each type rolls its OWN density-adjusted chance independently; the first type to hit (in a per-cell-
## shuffled order, so no single type gets permanent "first dibs") wins the cell — keeps placements from
## overlapping while still letting every type's density behave like an honest per-type probability.
## Two extra gates apply BEFORE any type is even considered: the candidate position must be off the river
## (RubiconNoise.is_river, same band rubicon_ground.gdshader paints) and at least MIN_ASSET_SPACING away from
## every instance already placed this regen pass (any type — a temple and a tree can't overlap either).
func _maybe_place(cell: Vector2) -> void:
	if _types.is_empty():
		return
	var jitter := Vector2(
		(RubiconNoise.hash21(cell + Vector2(23.0, 0.0)) - 0.5) * CELL_SIZE * 0.8,
		(RubiconNoise.hash21(cell + Vector2(0.0, 23.0)) - 0.5) * CELL_SIZE * 0.8
	)
	var pos := cell + jitter
	if _river_width > 0.0 and RubiconNoise.is_river(pos, _river_width):
		return
	for existing: Vector2 in _placed_positions:
		if pos.distance_to(existing) < MIN_ASSET_SPACING:
			return
	var biome: float = RubiconNoise.biome_value(cell)
	var is_blue: bool = biome > RubiconConfig.BLUE_THRESHOLD
	var base_chance: float = TREE_CHANCE_BLUE if is_blue else TREE_CHANCE_SAND
	var start_i: int = int(RubiconNoise.hash21(cell + Vector2(17.0, 17.0)) * _types.size())
	for k in _types.size():
		var i: int = (start_i + k) % _types.size()
		var type_def: Dictionary = _types[i]
		var settings: Dictionary = _settings_by_type.get(type_def["name"], RubiconTerrainSettings.default_asset_entry())
		var chance: float = clampf(base_chance * float(settings["density"]), 0.0, 1.0)
		var roll: float = RubiconNoise.hash21(cell * 1.271 + Vector2(300.0 + float(i) * 47.0, 900.0 + float(i) * 91.0))
		if roll >= chance:
			continue
		var arr: Array = _instances_by_type[i]
		if arr.size() >= MAX_INSTANCES_PER_TYPE:
			continue
		_place_instance(cell, pos, i, type_def, settings, arr)
		_placed_positions.append(pos)
		return

func _place_instance(cell: Vector2, pos: Vector2, type_idx: int, type_def: Dictionary, settings: Dictionary, arr: Array) -> void:
	var yaw: float = RubiconNoise.hash21(cell + Vector2(99.0, 3.0)) * TAU   # spin around the trunk only — stays upright
	var raw_roll: float = RubiconNoise.hash21(cell + Vector2(-7.0, 5.0))   # 0..1, this cell's fixed point in the range
	# scale_bias skews which end of [scale_min, scale_max] comes up more often — 0.5 is uniform (no skew),
	# 0.0 raises raw_roll to a HIGH power (pushes most rolls toward 0 → mostly small), 1.0 lowers it to a
	# power < 1 (pushes most rolls toward 1 → mostly large). See RubiconTerrainSettings.DEFAULT_ASSET_SCALE_BIAS.
	var bias: float = float(settings.get("scale_bias", 0.5))
	var skew_pow: float = pow(4.0, (0.5 - bias) * 2.0)
	var scale_roll: float = pow(raw_roll, skew_pow)
	var total_mult: float = lerpf(float(settings["scale_min"]), float(settings["scale_max"]), scale_roll)

	var xform_pos := Vector3(pos.x, 0.0, pos.y * _z_comp)   # ground level; _z_comp cancels the tilt's cos() foreshortening on Z
	var xform_rot := Vector3(0.0, yaw, 0.0)                  # Y-axis only — never tips over
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

	arr.append({"outer": outer, "proxy": proxy})
