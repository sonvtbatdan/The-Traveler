extends RefCounted
class_name RubiconAssetScan
## Scans assets/map/rubicon/ for tree .glb models — the single source of truth both the offline bake tool
## (tools/bake_rubicon_trees.gd) and the runtime scatter (rubicon_trees.gd) read. Dropping a new .glb in
## that folder + re-running the bake tool is the whole "add a tree variant" workflow — no code edits.
##
## Filtering by .glb (not by scanning for .png directly) matters: Godot's glTF importer extracts embedded
## material textures into the SAME folder (e.g. "tree 1_Baked_BaseColor.png", "..._MetallicRoughness.png"
## sit right next to "tree 1.glb" after import) — scanning for "any .png in the folder" would scatter those
## material maps as if they were tree sprites. Driving off .glb stems sidesteps that entirely.

const FOLDER := "res://assets/map/rubicon/"
const SCATTER_EXCLUDED := ["temple"]   # landmark/boss objects spawned via a dedicated system
                                        # (rubicon_temple_layer.gd), NOT the regular density-scatter or the
                                        # Terrain Edit panel's Assets list — filename stem, case-sensitive.
const MAPTILE_FOLDER := FOLDER + "maptile/"     # one subfolder per ground tile SET (e.g. "green", "grey") —
                                                 # each holds the 3 canopy photos that set's ground uses; see
                                                 # rubicon_ground.gd's apply_maptile_set / Terrain Edit panel's
                                                 # "Tile Set" dropdown.
const WATERTILE_FOLDER := FOLDER + "watertile/" # one subfolder per water wave-texture SET (e.g. "B"/"C"/"D",
                                                 # named after the SeaWaterMaterial variant it's copied from —
                                                 # see rubicon_ground.gd's apply_water_tile_set / Terrain Edit
                                                 # panel's "Water Pattern" dropdown).

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
## the Terrain Edit panel's "Tile Set" dropdown; adding a new set is just "drop a new subfolder in", no code
## changes (mirrors glb_paths()' "add a tree = drop a .glb in" convention).
static func maptile_set_names() -> Array:
	return _list_subdirs(MAPTILE_FOLDER)

## Every COLOR image file directly inside MAPTILE_FOLDER/set_name/, sorted — positional (1st/2nd/3rd file),
## NOT filename-pattern-matched, since sets aren't guaranteed to share a naming convention (e.g. "green" ships
## canopy1/2/3.png, "grey" ships canopy1a/2a/3a.png). Excludes "*_normal.png" companion files (see
## maptile_normal_path/tools/generate_canopy_normal.py) — those live in the SAME folder but aren't a 4th/5th/6th
## color tile, they're a per-pixel normal map for one of the first 3.
static func maptile_set_image_paths(set_name: String) -> Array:
	return _list_images(MAPTILE_FOLDER + set_name + "/", true)

## The generated tangent-space normal map path for a color image returned by maptile_set_image_paths() — see
## tools/generate_canopy_normal.py. May not exist (older/future sets not yet processed by that tool); caller is
## expected to check ResourceLoader.exists() and fall back to a flat neutral normal.
static func maptile_normal_path(color_path: String) -> String:
	return color_path.get_basename() + "_normal.png"

## Every subfolder directly inside WATERTILE_FOLDER, sorted — one entry per available water wave-texture set.
## Drives the Terrain Edit panel's "Water Pattern" dropdown.
static func watertile_set_names() -> Array:
	return _list_subdirs(WATERTILE_FOLDER)

## The wave-texture image inside WATERTILE_FOLDER/set_name/ — positional (1st file found), same convention as
## maptile. Returns "" if the set has no image yet.
static func watertile_wave_path(set_name: String) -> String:
	var paths := _list_images(WATERTILE_FOLDER + set_name + "/", false)
	return String(paths[0]) if not paths.is_empty() else ""

## Where tools/bake_rubicon_trees.gd writes (icon/reference use) the baked top-down PNG for a given
## .glb — same folder, same filename stem, .png extension. NOT used for in-game scattering any more
## (rubicon_trees.gd renders the live .glb directly so moving the camera actually reveals new angles,
## which a static bake fundamentally can't do) — kept for quick visual reference/thumbnails.
static func baked_png_path(glb_path: String) -> String:
	return glb_path.get_basename() + ".png"

## Display/lookup name for a .glb — its filename stem (e.g. "res://assets/map/rubicon/tree 1.glb" -> "tree
## 1"). Used as the key for per-asset settings (RubiconTerrainSettings.asset_sizes) and the Terrain Edit
## panel's per-asset Size sliders.
static func type_name(glb_path: String) -> String:
	return glb_path.get_file().get_basename()

## Recursively sets `.layers` on every VisualInstance3D under `root` — used to tag a scattered tree/temple
## instance as "short" or "tall" (rubicon_trees.gd's cloud-altitude split: a Camera3D's cull_mask only
## renders the layer bits it's set to see, so two cameras with different cull_mask + this per-instance
## layers tag is how one instance renders in the below-cloud composite and another in the above-cloud one).
static func set_visual_layers(root: Node, mask: int) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = mask
	for c: Node in root.get_children():
		set_visual_layers(c, mask)

## Recursively forces every GeometryInstance3D under `root` to render with `mat` instead of its own imported
## material — used for the blur-mask proxy pass (rubicon_trees.gd/rubicon_asset_layer.gd), which needs the
## real mesh silhouette but none of the original textures/lighting.
static func set_flat_material(root: Node, mat: Material) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).material_override = mat
	for c: Node in root.get_children():
		set_flat_material(c, mat)

## Recursively sets the "blur_amount" instance-uniform (declared in the blur-mask shader) on every
## GeometryInstance3D under `root` — lets many proxies share ONE ShaderMaterial resource while each still
## encodes its own type's blur setting (Godot's per-instance shader uniform feature).
static func set_instance_blur_param(root: Node, value: float) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).set_instance_shader_parameter("blur_amount", value)
	for c: Node in root.get_children():
		set_instance_blur_param(c, value)

## Combined AABB of every MeshInstance3D under `root`, in root's own local space. `root` MUST already be
## inside the SceneTree for at least one frame (global_transform reads as identity/garbage otherwise —
## the classic "!is_inside_tree()" trap right after add_child(); callers must await a frame first).
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
