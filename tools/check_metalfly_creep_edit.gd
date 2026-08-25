extends SceneTree
## DEV TOOL (2026-08-24) — the Metalfly boss's two 3D bodies in CREEP EDIT: that they appear as a grouped
## pair of layers on the Electric map, get their own preview rigs (not one shared rig), carry a FRONT arrow,
## and — the part that actually matters — that a mount angle dialled on a slider reaches the live boss.
##
## That last step is the whole point of the panel, so it is tested end to end: write a rotation into the
## rig the sliders drive, save through the editor's own _save_layout(), then spawn a boss and read the basis
## its body is actually rendering with. Anything short of that verifies a UI, not a feature.
##
## WRITES PROJECT FILES — one Save in the creep/weapon editors rewrites ALL of these, in full, re-emitting
## every entry with whatever fields the current editor version produces (axis_space, hidden, rot, rot_base,
## z), so they show up as huge diffs even when nothing was really edited:
##     res://creep_layout.cfg
##     res://plume_styles.cfg
##     res://weapon_layout.cfg
##     res://creep_chain_overrides.cfg
## Back up and restore ALL FOUR. Backing up only the obvious one is how three of them were left quietly
## modified for several commits' worth of work here.
##
## Run NON-headless:  godot --path . --script tools/check_metalfly_creep_edit.gd

const TEST_ROT := Vector3(0.0, 0.0, 40.0)   # editor space is Z-up, so Z is the flat "heading" spin

var _f := 0
var _ed: Node = null
var _fails := 0

func _initialize() -> void:
	var packed := load("res://scenes/arena.tscn") as PackedScene
	get_root().add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	match _f:
		60:  _open_editor()
		110: _check_palette()
		140: _dial_and_save()
		170: _check_runtime()
		200:
			print("── ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails, " ──")
			quit(1 if _fails > 0 else 0)

func _fail(msg: String) -> void:
	print("  FAIL: ", msg)
	_fails += 1

func _open_editor() -> void:
	_ed = get_first_node_in_group("creep_edit")
	if _ed == null:
		_fail("creep_edit node not found")
		return
	_ed.call("toggle")
	# Electric's index in MAP_REGISTRY — looked up rather than hardcoded.
	var reg: Array = _ed.get("MAP_REGISTRY")
	var idx := -1
	for i in reg.size():
		if String((reg[i] as Dictionary)["id"]) == String(_ed.get("MF_MAP")):
			idx = i
	if idx < 0:
		_fail("no MAP_REGISTRY entry for MF_MAP")
		return
	_ed.call("_on_map_selected", idx)
	_ed.call("_set_active_creep", _ed.get("MF_ROOT"))
	# LAYERS rows default to collapsed once a group is placed; expand so the screenshot shows both bodies.
	_ed.set("_layers_collapsed", false)
	_ed.call("_refresh_layer_list")

func _check_palette() -> void:
	var names: Array = _ed.get("_all_creep_names")
	var root: String = _ed.get("MF_ROOT")
	var cocoon: String = _ed.get("MF_COCOON")
	print("── palette (Electric) ──")
	for n: String in [root, cocoon]:
		if not names.has(n):
			_fail("'%s' missing from the palette" % n)
	print("  entries present: ", names.has(root), " / ", names.has(cocoon))
	# Exactly two bodies — the root IS the winged one, so a third row would mean a duplicate model stacked
	# on the root's (the bug this arrangement replaced).
	var mf_rows := 0
	for n: String in names:
		if String(n).begins_with(root):
			mf_rows += 1
	print("  metalfly rows: ", mf_rows)
	if mf_rows != 2:
		_fail("expected exactly 2 metalfly rows, got %d" % mf_rows)

	var parents: Dictionary = _ed.get("_creep_parents")
	print("  layer parents: %s -> %s" % [cocoon, parents.get(cocoon, "<none>")])
	if String(parents.get(cocoon, "")) != root:
		_fail("the cocoon layer is not grouped under the root")
	var order: Dictionary = _ed.get("_chain_group_order")
	print("  group order: ", order.get(root, []))

	# Each layer must own its rig. The root and the wings share metalfly.glb, so a path-only cache key would
	# hand them a single rig — and therefore a single rotation between them.
	var cache: Dictionary = _ed.get("_glb_preview_cache")
	var keys: Array = []
	for n: String in [root, cocoon]:
		keys.append(_ed.call("_rig_key", n, _ed.call("_asset_path_for", n)))
	print("  rig keys: ", keys)
	if keys[0] == keys[1]:
		_fail("both bodies share one preview rig")
	print("  rigs built: ", cache.has(keys[0]), " / ", cache.has(keys[1]), "   (cache size ", cache.size(), ")")

	# FRONT arrow
	var markers: Array = _ed.call("_front_markers")
	print("  front markers drawn: ", markers.size())
	for m: Dictionary in markers:
		print("    angle=%.3f rad (%.0f deg)" % [float(m["angle"]), rad_to_deg(float(m["angle"]))])
	if markers.is_empty():
		_fail("no FRONT arrow for the metalfly layers")
	# The Rotate X/Y/Z sliders must be VISIBLE, not merely constructed. `_refresh_glb_view_ui()` gates the
	# whole "3D VIEW / MOUNT ANGLE" section on the WIRED_3D_CREEPS allowlist as well as the file extension,
	# and a body missing from that list previews perfectly while offering no controls at all — which is
	# exactly what shipped in the first pass here, because the original version of this tool checked the
	# rotation DATA PATH and never once asked whether the user could reach it.
	for n: String in [root, cocoon]:
		_ed.call("_set_active_creep", n)
		var section: Array = _ed.get("_glb_view_section_nodes")
		var shown := 0
		for node in section:
			if (node as Control).visible:
				shown += 1
		var sliders := [_ed.get("_glb_rot_x_slider"), _ed.get("_glb_rot_y_slider"), _ed.get("_glb_rot_z_slider")]
		var vis_sliders := 0
		for sl in sliders:
			if sl != null and (sl as Control).is_visible_in_tree():
				vis_sliders += 1
		# `is_visible_in_tree()` only means no ancestor is hidden — it says nothing about whether the control
		# is inside the window. A section that scrolls off the bottom of a tall panel is just as unreachable
		# to the user as a hidden one, so check the rect too.
		var vp_rect := Rect2(Vector2.ZERO, Vector2(get_root().size))
		var on_screen := 0
		var rects: Array[String] = []
		for sl in sliders:
			if sl == null:
				continue
			var r: Rect2 = (sl as Control).get_global_rect()
			rects.append("y=%.0f" % r.position.y)
			if vp_rect.intersects(r):
				on_screen += 1
		print("  '%s': section rows visible %d/%d, sliders visible %d/3, on-screen %d/3  [%s, window h=%d]"
			% [n, shown, section.size(), vis_sliders, on_screen, ", ".join(rects), get_root().size.y])
		if shown != section.size() or vis_sliders != 3:
			_fail("'%s' has no visible Rotate X/Y/Z sliders" % n)
		if on_screen != 3:
			_fail("'%s' Rotate sliders are visible but off-screen" % n)
	_ed.call("_set_active_creep", root)

	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	print("  screenshot err=", img.save_png("user://mf_creep_edit.png"))

func _dial_and_save() -> void:
	print("── dial + save ──")
	var wings: String = _ed.get("MF_ROOT")   # the root IS the winged body
	var cache: Dictionary = _ed.get("_glb_preview_cache")
	var key: String = _ed.call("_rig_key", wings, _ed.call("_asset_path_for", wings))
	if not cache.has(key):
		_fail("no preview rig for the wings layer — nothing to dial")
		return
	# Write straight into the rig the Rotate X/Y/Z sliders drive, which is what _save_layout() reads back.
	(cache[key] as Dictionary)["rot"] = TEST_ROT
	_ed.call("_save_layout", true)
	var cfg := ConfigFile.new()
	cfg.load("res://creep_layout.cfg")
	var entry: Dictionary = cfg.get_value("creeps", wings, {})
	print("  saved '%s': rot=%s  path=%s" % [wings, entry.get("rot", "<none>"), entry.get("path", "<none>")])
	if not (entry.get("rot", Vector3.ZERO) as Vector3).is_equal_approx(TEST_ROT):
		_fail("the dialled rotation did not reach creep_layout.cfg")

func _check_runtime() -> void:
	print("── does it reach the arena? ──")
	var wd: Node = get_first_node_in_group("wave_director")
	var pl := get_first_node_in_group("player") as Node2D
	var boss := wd.call("_spawn", "metalfly", pl.global_position + Vector2(0.0, -300.0), true) as Node2D
	if boss == null:
		_fail("could not spawn a metalfly")
		return
	# Hatch straight to the winged body — that is the layer the rotation was dialled on.
	boss.call("take_damage", 99999.0)
	var rig: Node = boss.get("_mf_rig")
	if rig == null:
		_fail("winged rig missing after hatch")
		return
	var got: Basis = rig.get("_mount_basis")
	var want: Basis = (load("res://scripts/gameplay/fx/glb_topdown_rig.gd").new() as RefCounted).call("view_basis", TEST_ROT)
	print("  rig mount basis  = ", got)
	print("  expected         = ", want)
	var same := got.is_equal_approx(want)
	print("  applied: ", same)
	if not same:
		_fail("the saved mount angle did not reach the live rig")
	if got.is_equal_approx(Basis.IDENTITY):
		_fail("mount basis is identity — the dial had no effect at all")
