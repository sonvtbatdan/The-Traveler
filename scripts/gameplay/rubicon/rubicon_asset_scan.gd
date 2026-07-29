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

## Every .glb directly inside FOLDER (not recursive), sorted for stable ordering.
static func glb_paths() -> Array:
	var out: Array = []
	var da := DirAccess.open(FOLDER)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.get_extension().to_lower() == "glb":
			out.append(FOLDER + fname)
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out

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
