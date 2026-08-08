extends Node2D
class_name VolcanicTrees
## Manages the Volcanic map's scattered 3D assets (obsidian rocks/formations, one per .glb in
## assets/map/volcanic/ — see VolcanicAssetScan). Port of rubicon/rubicon_trees.gd's fully generic
## scatter/compositor system (see that file's header for the complete rationale — shared World3D "host"
## viewport, two-pass color+blur-mask render, orthogonal tilted camera), INCLUDING spawn_landmark() (used by
## volcanic_temple_layer.gd — temple.glb is excluded from the regular density-scatter pool, see
## VolcanicAssetScan.SCATTER_EXCLUDED). One omission from the Rubicon original: the real 3D cloud-occluder
## plane (a flat translucent band at a fixed sky altitude, for depth-clipping tall assets against an overhead
## cloud layer) — Volcanic's clouds are ground-anchored ash/smoke plumes (volcanic_clouds.gd), not a
## horizontal sky band, so there's no altitude for a tall rock to poke through/under any more; port a fresh
## version back if a different tall-object-vs-atmosphere need shows up later.
##
## assets/map/volcanic/ currently has no rock/obsidian .glb files (only temple.glb, excluded from this pool),
## so _types stays empty and the regular density-scatter places nothing — the same "drop a .glb, no code
## changes" convention Rubicon documents, just with an empty pool for now.

const VolcanicNoise := preload("res://scripts/gameplay/volcanic/volcanic_noise.gd")
const VolcanicConfig := preload("res://scripts/gameplay/volcanic/volcanic_config.gd")
const VolcanicAssetScan := preload("res://scripts/gameplay/volcanic/volcanic_asset_scan.gd")
const VolcanicTerrainSettings := preload("res://scripts/gameplay/volcanic/volcanic_terrain_settings.gd")
const VolcanicAssetLayerScript := preload("res://scripts/gameplay/volcanic/volcanic_asset_layer.gd")
const BLUR_MASK_SHADER := "res://scripts/gameplay/volcanic/volcanic_blur_mask.gdshader"

const CELL_SIZE_MAX := 110.0
const CELL_SIZE_MIN := 18.0
const DESIRED_HEIGHT_PX := 110.0
const MAX_INSTANCES_PER_TYPE := 2000
const REGEN_MOVE_THRESHOLD := 160.0
const MARGIN := 140.0
const CLOUD_ALTITUDE_PX := VolcanicConfig.CLOUD_MAX_PX   # informational only (Terrain Edit panel's Height
                                                           # readout) — no occluder mesh actually clips against
                                                           # this any more, see header
const TILT_MAX_DEG := 8.0

var _host_vp: SubViewport
var _world3d_root: Node3D
var _asset_layer: VolcanicAssetLayer
var _blur_mask_material: ShaderMaterial
var _types: Array = []
var _placed: Dictionary = {}
var _count_by_type: Array = []
var _settings_by_type: Dictionary = {}
var _last_center: Vector2 = Vector2.ZERO
var _last_regen_center: Vector2 = Vector2.ZERO
var _has_last_center: bool = false
var _view_size: Vector2 = Vector2(1440.0, 780.0)
var _types_ready: bool = false
var _z_comp: float = 1.0
var _river_width: float = 0.0
var _placed_positions: Array = []
var _jitter: float = VolcanicTerrainSettings.DEFAULT_JITTER
var _cell_size: float = CELL_SIZE_MAX

func _ready() -> void:
	add_to_group("volcanic_trees")   # so the Terrain Edit panel can find this instance
	_z_comp = 1.0 / cos(deg_to_rad(VolcanicAssetLayerScript.CAM_ISO_DEG))
	_build_host()
	await get_tree().process_frame
	await _measure_types()

	_asset_layer = VolcanicAssetLayerScript.new()
	add_child(_asset_layer)
	_asset_layer.setup(_host_vp.world_3d)

	var s := VolcanicTerrainSettings.load_settings()
	for t: Dictionary in _types:
		_count_by_type.append(0)
		_settings_by_type[t["name"]] = VolcanicTerrainSettings.asset_entry(s, t["name"])
	_river_width = float(s["river_width"])
	_jitter = float(s["jitter"])

	_types_ready = true

func _build_host() -> void:
	_host_vp = SubViewport.new()
	_host_vp.size = Vector2i(4, 4)
	_host_vp.world_3d = World3D.new()
	add_child(_host_vp)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-100.0, 20.0, 0.0)
	key.light_energy = 1.6
	_host_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-80.0, -160.0, 0.0)
	fill.light_energy = 0.7
	_host_vp.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
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

## Public: keeps scattered assets off the SAME lava band volcanic_ground.gdshader paints (VolcanicNoise.is_river
## uses the same frequency/level) — width 0 disables avoidance entirely.
func apply_river_width(width: float) -> void:
	_river_width = width
	if _types_ready:
		_regenerate(_last_center, true)

## Public: fraction of _cell_size each candidate position is randomly offset by.
func apply_jitter(jitter: float) -> void:
	_jitter = jitter
	if _types_ready:
		_regenerate(_last_center, true)

func _measure_types() -> void:
	for glb_path: String in VolcanicAssetScan.glb_paths():
		var def: Dictionary = await _measure_one(glb_path)
		if not def.is_empty():
			_types.append(def)

func _measure_one(glb_path: String) -> Dictionary:
	var packed := load(glb_path) as PackedScene
	if packed == null:
		return {}
	var probe := packed.instantiate() as Node3D
	_world3d_root.add_child(probe)
	await get_tree().process_frame
	var aabb := VolcanicAssetScan.combined_aabb(probe)
	var footprint_diag: float = Vector2(aabb.size.x, aabb.size.z).length()
	var ref_dim: float = maxf(maxf(aabb.size.y, footprint_diag), 0.001)
	var center_xz := Vector2(aabb.position.x + aabb.size.x * 0.5, aabb.position.z + aabb.size.z * 0.5)
	probe.queue_free()
	return {
		"name": VolcanicAssetScan.type_name(glb_path),
		"packed": packed,
		"scale": DESIRED_HEIGHT_PX / ref_dim,
		"offset": Vector3(-center_xz.x, -aabb.position.y, -center_xz.y),
		"footprint_radius": footprint_diag * 0.5,
		"half_extent": Vector2(aabb.size.x, aabb.size.z) * 0.5,
	}

## Public: places a single instance of `glb_path` at an explicit world position, OUTSIDE the density-scatter
## system entirely — not tracked in _placed/_count_by_type, never touched by _regenerate()'s view-based
## clear/rebuild. For one-off landmark objects (volcanic_temple_layer.gd) whose lifetime is owned by whatever
## spawned them. Caller owns the returned Node3D and must queue_free() it when the landmark should disappear.
## Upright (no random tilt, unlike wild scatter) since a landmark should look deliberately placed. `scale_mult`
## (default 1.0 = the same DESIRED_HEIGHT_PX auto-scale every scattered type gets) lets a landmark be
## deliberately bigger/smaller. Returns {} if `glb_path` fails to load. Verbatim port of
## rubicon_trees.gd's spawn_landmark() — see that file for the full rationale on half_extent/yaw semantics
## (used by volcanic_temple_layer.gd to place local-space marked plume points on the spawned instance).
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
	VolcanicAssetScan.set_visual_layers(outer, VolcanicAssetLayerScript.COLOR_BIT)
	var half_extent: Vector2 = Vector2(def["half_extent"]) * final_scale
	return {
		"node": outer,
		"radius": float(def["footprint_radius"]) * final_scale,
		"half_extent": half_extent,
		"yaw": yaw,
	}

## Public: called by the Terrain Edit panel (live) and effectively by this node's own _ready() (persisted
## settings, via _settings_by_type directly). See rubicon_trees.gd's apply_asset_setting for full semantics.
func apply_asset_setting(type_name: String, density: float, scale_min: float, scale_max: float, scale_bias: float, blur: float, enabled: bool = true) -> void:
	_settings_by_type[type_name] = {"density": density, "scale_min": scale_min, "scale_max": scale_max, "scale_bias": scale_bias, "blur": blur, "enabled": enabled}
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
	if not _types_ready:
		return
	if _has_last_center and center.distance_to(_last_regen_center) < REGEN_MOVE_THRESHOLD:
		return
	_has_last_center = true
	_last_regen_center = center
	_regenerate(center)

func _regenerate(center: Vector2, force_full: bool = false) -> void:
	if _types.is_empty():
		return

	var max_density: float = 0.0
	for t: Dictionary in _types:
		var s: Dictionary = _settings_by_type.get(t["name"], VolcanicTerrainSettings.default_asset_entry())
		if bool(s.get("enabled", true)):
			max_density = maxf(max_density, float(s["density"]))
	var new_cell_size: float = lerpf(CELL_SIZE_MAX, CELL_SIZE_MIN, clampf(max_density / 100.0, 0.0, 1.0))
	if force_full or not is_equal_approx(new_cell_size, _cell_size):
		_clear_all()
	_cell_size = new_cell_size

	var half: Vector2 = _view_size * 0.5 + Vector2(MARGIN, MARGIN)
	var min_p: Vector2 = center - half
	var max_p: Vector2 = center + half

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

func _maybe_place(cell: Vector2) -> void:
	if _types.is_empty():
		return
	var start_i: int = int(VolcanicNoise.hash21(cell + Vector2(17.0, 17.0)) * _types.size())
	for k in _types.size():
		var i: int = (start_i + k) % _types.size()
		var type_def: Dictionary = _types[i]
		var settings: Dictionary = _settings_by_type.get(type_def["name"], VolcanicTerrainSettings.default_asset_entry())
		if not bool(settings.get("enabled", true)):
			continue
		var key := Vector3(cell.x, cell.y, float(i))
		if _placed.has(key):
			continue
		var chance: float = clampf(float(settings["density"]) / 100.0, 0.0, 1.0)
		var roll: float = VolcanicNoise.hash21(cell * 1.271 + Vector2(300.0 + float(i) * 47.0, 900.0 + float(i) * 91.0))
		if roll >= chance:
			continue
		if int(_count_by_type[i]) >= MAX_INSTANCES_PER_TYPE:
			continue
		var jitter := Vector2(
			(VolcanicNoise.hash21(cell + Vector2(23.0 + float(i) * 13.0, 0.0)) - 0.5) * _cell_size * _jitter,
			(VolcanicNoise.hash21(cell + Vector2(0.0, 23.0 + float(i) * 13.0)) - 0.5) * _cell_size * _jitter
		)
		var pos := cell + jitter
		if _river_width > 0.0 and VolcanicNoise.is_river(pos, _river_width):
			continue
		_place_instance(key, cell, pos, i, type_def, settings)

func _place_instance(key: Vector3, cell: Vector2, pos: Vector2, type_idx: int, type_def: Dictionary, settings: Dictionary) -> bool:
	var yaw: float = VolcanicNoise.hash21(cell + Vector2(99.0 + float(type_idx) * 7.0, 3.0)) * TAU
	var raw_roll: float = VolcanicNoise.hash21(cell + Vector2(-7.0, 5.0 + float(type_idx) * 7.0))
	var bias: float = float(settings.get("scale_bias", 0.5))
	var skew_pow: float = pow(4.0, (0.5 - bias) * 2.0)
	var scale_roll: float = pow(raw_roll, skew_pow)
	var total_mult: float = lerpf(float(settings["scale_min"]), float(settings["scale_max"]), scale_roll)

	var radius: float = float(type_def["footprint_radius"]) * float(type_def["scale"]) * total_mult
	for existing: Dictionary in _placed_positions:
		if pos.distance_to(existing["pos"]) < (radius + float(existing["radius"])):
			return false

	var tilt: float = (VolcanicNoise.hash21(cell + Vector2(41.0 + float(type_idx) * 7.0, -19.0)) - 0.5) * 2.0 * deg_to_rad(TILT_MAX_DEG)

	var xform_pos := Vector3(pos.x, 0.0, pos.y * _z_comp)
	var xform_rot := Vector3(0.0, yaw, tilt)
	var xform_scale := Vector3.ONE * (float(type_def["scale"]) * total_mult)

	var outer := Node3D.new()
	outer.position = xform_pos
	outer.rotation = xform_rot
	outer.scale = xform_scale
	var inner := (type_def["packed"] as PackedScene).instantiate() as Node3D
	inner.position = type_def["offset"]
	outer.add_child(inner)
	_world3d_root.add_child(outer)
	VolcanicAssetScan.set_visual_layers(outer, VolcanicAssetLayerScript.COLOR_BIT)

	var proxy := Node3D.new()
	proxy.position = xform_pos
	proxy.rotation = xform_rot
	proxy.scale = xform_scale
	var proxy_inner := (type_def["packed"] as PackedScene).instantiate() as Node3D
	proxy_inner.position = type_def["offset"]
	proxy.add_child(proxy_inner)
	_world3d_root.add_child(proxy)
	VolcanicAssetScan.set_visual_layers(proxy, VolcanicAssetLayerScript.BLUR_BIT)
	VolcanicAssetScan.set_flat_material(proxy, _blur_mask_material)
	VolcanicAssetScan.set_instance_blur_param(proxy, float(settings["blur"]))

	_placed[key] = {"outer": outer, "proxy": proxy, "type_idx": type_idx, "pos": pos, "radius": radius}
	_count_by_type[type_idx] += 1
	_placed_positions.append({"pos": pos, "radius": radius})
	return true
