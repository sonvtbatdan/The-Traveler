extends RefCounted
class_name VolcanicAssetScan
## Scans assets/map/volcanic/ for rock/obsidian .glb models — mirrors rubicon/rubicon_asset_scan.gd exactly
## (see that file for the full rationale on scanning by .glb stem, not by .png). Dropping a new .glb in this
## folder is the whole "add a rock/obsidian variant" workflow — no code edits.

const FOLDER := "res://assets/map/volcanic/"
const SCATTER_EXCLUDED := ["temple", "engineer", "psyker"]   # landmark/rescue objects spawned via their own
                                        # dedicated system (volcanic_temple_layer.gd / volcanic_ruin_layer.gd),
                                        # NOT the regular density-scatter or the Terrain Edit panel's Assets
                                        # list — filename stem, case-sensitive (mirrors rubicon_asset_scan.gd's
                                        # own SCATTER_EXCLUDED). engineer.glb/psyker.glb moved into this folder
                                        # 2026-08-06 (from assets/ruin/) — MUST stay excluded or they'd get
                                        # randomly ambient-scattered as decoration.
const MAPTILE_FOLDER := FOLDER + "maptile/"     # one subfolder per ground tile SET — see volcanic_ground.gd's
                                                 # apply_maptile_set / Terrain Edit panel's "Tile Set" dropdown.
const WATERTILE_FOLDER := FOLDER + "watertile/" # one subfolder per lava wave-texture SET — see
                                                 # volcanic_ground.gd's apply_water_tile_set / Terrain Edit
                                                 # panel's "Lava Pattern" dropdown.

## Every .glb directly inside FOLDER (not recursive), sorted for stable ordering — excludes
## SCATTER_EXCLUDED (landmark models loaded directly by their own spawner instead).
static func glb_paths() -> Array:
	var out: Array = []
	var da := DirAccess.open(FOLDER)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.get_extension().to_lower() == "glb" and not SCATTER_EXCLUDED.has(fname.get_basename()):
			out.append(FOLDER + fname)
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out

## Every subfolder directly inside `folder`, sorted — shared by maptile_set_names()/watertile_set_names().
static func _list_subdirs(folder: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(folder)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if da.current_is_dir() and not fname.begins_with("."):
			out.append(fname)
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out

## Every image file directly inside `folder`, sorted — shared by maptile_set_image_paths()/
## watertile_wave_path(). `exclude_normal` skips "*_normal.png" companion files (see maptile_normal_path).
static func _list_images(folder: String, exclude_normal: bool) -> Array:
	var out: Array = []
	var da := DirAccess.open(folder)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		var ext := fname.get_extension().to_lower()
		var is_image := ext == "png" or ext == "jpg" or ext == "jpeg"
		var is_companion := exclude_normal and fname.to_lower().contains("_normal")
		if not da.current_is_dir() and is_image and not is_companion:
			out.append(folder + fname)
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out

## Every subfolder directly inside MAPTILE_FOLDER, sorted — one entry per available ground tile set. Drives
## the Terrain Edit panel's "Tile Set" dropdown; adding a new set is just "drop a new subfolder in".
static func maptile_set_names() -> Array:
	return _list_subdirs(MAPTILE_FOLDER)

## Every COLOR image file directly inside MAPTILE_FOLDER/set_name/, sorted — positional (1st/2nd/3rd file),
## NOT filename-pattern-matched. Excludes "*_normal.png" companion files.
static func maptile_set_image_paths(set_name: String) -> Array:
	return _list_images(MAPTILE_FOLDER + set_name + "/", true)

## The generated tangent-space normal map path for a color image returned by maptile_set_image_paths() — see
## tools/generate_canopy_normal.py. Caller is expected to check ResourceLoader.exists() and fall back to a
## flat neutral normal.
static func maptile_normal_path(color_path: String) -> String:
	return color_path.get_basename() + "_normal.png"

## Every subfolder directly inside WATERTILE_FOLDER, sorted — one entry per available lava wave-texture set.
static func watertile_set_names() -> Array:
	return _list_subdirs(WATERTILE_FOLDER)

## The wave-texture image inside WATERTILE_FOLDER/set_name/ — positional (1st file found). Returns "" if the
## set has no image yet.
static func watertile_wave_path(set_name: String) -> String:
	var paths := _list_images(WATERTILE_FOLDER + set_name + "/", false)
	return String(paths[0]) if not paths.is_empty() else ""

## Where a future bake tool would write a baked top-down PNG for a given .glb — same folder, same filename
## stem, .png extension. Mirrors RubiconAssetScan.baked_png_path (no bake tool exists for Volcanic yet).
static func baked_png_path(glb_path: String) -> String:
	return glb_path.get_basename() + ".png"

## Display/lookup name for a .glb — its filename stem. Used as the key for per-asset settings
## (VolcanicTerrainSettings.asset_sizes) and the Terrain Edit panel's per-asset Size sliders.
static func type_name(glb_path: String) -> String:
	return glb_path.get_file().get_basename()

## Recursively sets `.layers` on every VisualInstance3D under `root` — see RubiconAssetScan.set_visual_layers.
static func set_visual_layers(root: Node, mask: int) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = mask
	for c: Node in root.get_children():
		set_visual_layers(c, mask)

## Recursively forces every GeometryInstance3D under `root` to render with `mat` — see
## RubiconAssetScan.set_flat_material.
static func set_flat_material(root: Node, mat: Material) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).material_override = mat
	for c: Node in root.get_children():
		set_flat_material(c, mat)

## Recursively sets the "blur_amount" instance-uniform on every GeometryInstance3D under `root` — see
## RubiconAssetScan.set_instance_blur_param.
static func set_instance_blur_param(root: Node, value: float) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).set_instance_shader_parameter("blur_amount", value)
	for c: Node in root.get_children():
		set_instance_blur_param(c, value)

## Combined AABB of every MeshInstance3D under `root`, in root's own local space — see
## RubiconAssetScan.combined_aabb (same "must already be inside the SceneTree for a frame" caveat applies).
static func combined_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var inv := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in _all_mesh_instances(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

static func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out
