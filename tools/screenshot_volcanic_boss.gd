extends SceneTree
## One-shot DEV TOOL: boots arena on Volcanic, opens Creep Edit on the new 3D boss.glb, and separately
## dev-spawns the boss enemy — verifies it renders as a spinning 3D body + its SP smoke points, and the
## editor's Rotate X/Y/Z + Add FP/TP/SP surface. Run non-headless:
##   godot --path . --script tools/screenshot_volcanic_boss.gd

var _f := 0

func _initialize() -> void:
	var meta := get_root().get_node_or_null("MetaManager")
	if meta != null:
		meta.set("selected_map_id", "volcanic")
	get_root().add_child((load("res://scenes/arena.tscn") as PackedScene).instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	var tree := get_root().get_tree()
	if _f == 80:
		var hud := tree.get_first_node_in_group("arena_hud_buttons")
		if hud != null and hud.has_method("set_dev_mode"):
			hud.call("set_dev_mode", true)
		# God mode so the parked player survives the (now large-radius) boss contact and the moves actually run.
		var gm := get_root().get_node_or_null("GameManager")
		if gm != null and gm.has_method("set_god_mode"):
			gm.call("set_god_mode", true)
	if _f == 95:
		var ce := tree.get_first_node_in_group("creep_edit")
		if ce != null and ce.has_method("toggle"):
			ce.call("toggle")
	if _f == 115:
		var ce := tree.get_first_node_in_group("creep_edit")
		if ce != null and ce.has_method("_set_active_creep"):
			ce.call("_set_active_creep", "boss")
	if _f == 130:
		_save("user://vboss_creep_edit.png")
		var ce := tree.get_first_node_in_group("creep_edit")
		if ce != null and ce.has_method("toggle"):
			ce.call("toggle")   # close editor
	if _f == 145:
		var ds := tree.get_first_node_in_group("arena_debug_spawn")
		if ds == null:
			ds = _find_by_method(get_root(), "_spawn_enemy_at")
		if ds != null and ds.has_method("_spawn_enemy_at"):
			ds.call("_spawn_enemy_at", "boss", Vector2(600, 200))
	if _f >= 150:
		# keep the boss parked just above the player so it stays framed for the shots
		var pl := tree.get_first_node_in_group("player")
		for e in tree.get_nodes_in_group("boss"):
			if String(e.get("_boss_move")) == "volcanic" and pl != null:
				e.set("global_position", (pl as Node2D).global_position + Vector2(0, -560))   # clear of the ~264px hit radius
	if _f == 175:
		_save("user://vboss_spawned.png")
		_force_move(tree, 10)   # Move 1 cone
	if _f == 210:
		_save("user://vboss_m1_cone.png")
		_force_move(tree, 11)   # Move 2 charge/beams
	if _f == 245:
		_save("user://vboss_m2_charge.png")
	if _f == 290:
		_save("user://vboss_m2_beams.png")
		_force_move(tree, 12)   # Move 3 ground+ash
	if _f == 330:
		_save("user://vboss_m3_ground.png")
		_force_move(tree, 13)   # Move 4 rotate+rain
	if _f == 370:
		_save("user://vboss_m4_pitch.png")
	if _f == 430:
		_save("user://vboss_m4_rain.png")
	if _f >= 436:
		quit(0)

func _force_move(tree: SceneTree, state: int) -> void:
	for e in tree.get_nodes_in_group("boss"):
		if String(e.get("_boss_move")) == "volcanic":
			e.set("_vb_state", state)
			e.set("_vb_phase", 0)
			e.set("_vb_t", 0.0)
			e.set("_vb_shot_t", 0.0)
			e.set("_vb_fired", 0)

func _find_by_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for c in n.get_children():
		var r := _find_by_method(c, m)
		if r != null:
			return r
	return null

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	if img.save_png(path) == OK:
		print("screenshot_volcanic_boss: saved ", ProjectSettings.globalize_path(path))
	else:
		push_warning("screenshot_volcanic_boss: save failed for " + path)
