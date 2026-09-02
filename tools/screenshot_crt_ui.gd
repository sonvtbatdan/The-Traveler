extends SceneTree
## One-shot DEV TOOL: boots the arena, opens several code-built panels and screenshots them to verify
## the "CRT phosphor console" restyle (square corners, green scanlines, no sea-blue).
## Run non-headless:  godot --path . --script tools/screenshot_crt_ui.gd

var _f := 0

func _initialize() -> void:
	var meta := get_root().get_node_or_null("MetaManager")
	if meta != null:
		meta.set("selected_map_id", "electric")
	var packed := load("res://scenes/arena.tscn") as PackedScene
	get_root().add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	var tree := get_root().get_tree()
	if _f == 80:
		var hud := tree.get_first_node_in_group("arena_hud_buttons")
		if hud != null and hud.has_method("set_dev_mode"):
			hud.call("set_dev_mode", true)
	if _f == 95:
		var inv := tree.get_first_node_in_group("inventory_ui")
		if inv != null and inv.has_method("toggle"):
			inv.call("toggle")
	if _f == 110:
		_save("user://crt_inventory.png")
		var inv := tree.get_first_node_in_group("inventory_ui")
		if inv != null and inv.has_method("toggle"):
			inv.call("toggle")
		var sp := tree.get_first_node_in_group("settings_panel")
		if sp != null and sp.has_method("open"):
			sp.call("open")
		elif sp != null and sp.has_method("toggle"):
			sp.call("toggle")
	if _f == 125:
		_save("user://crt_settings.png")
		var hud := tree.get_first_node_in_group("arena_hud_buttons")
		if hud != null and hud.has_method("_on_terrain_edit"):
			hud.call("_on_terrain_edit")
	if _f == 140:
		_save("user://crt_terrain_edit.png")
	if _f >= 146:
		quit(0)

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	if img.save_png(path) == OK:
		print("screenshot_crt_ui: saved ", ProjectSettings.globalize_path(path))
	else:
		push_warning("screenshot_crt_ui: save failed for %s" % path)
