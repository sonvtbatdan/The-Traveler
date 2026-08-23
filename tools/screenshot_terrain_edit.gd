extends SceneTree
## One-shot DEV TOOL: boots scenes/arena.tscn under map_id="electric", turns dev mode on, opens the new
## TERRAIN EDIT panel, and screenshots it — verifies the button placement (above Simplified) and the panel
## layout without needing to click through the real UI by hand.
## Run non-headless:  godot --path . --script tools/screenshot_terrain_edit.gd

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
	if _f == 90:
		var hud := get_root().get_tree().get_first_node_in_group("arena_hud_buttons")
		if hud != null and hud.has_method("set_dev_mode"):
			hud.call("set_dev_mode", true)
	if _f == 100:
		_save("user://terrain_edit_devon.png")
		var hud := get_root().get_tree().get_first_node_in_group("arena_hud_buttons")
		if hud != null:
			hud.call("_on_terrain_edit")
	if _f == 110:
		_save("user://terrain_edit_panel.png")
		var tem := get_root().get_tree().get_first_node_in_group("electric_terrain_edit")
		if tem != null:
			tem.call("_select_asset", "temple")
			tem.call("_on_asset_density_changed", 0.05)
			tem.call("_on_asset_scale_min_changed", 2.0)
			tem.call("_on_asset_scale_max_changed", 2.0)
			tem.call("_on_color_changed", "color_a", Color(1.0, 0.1, 0.1))
	if _f == 120:
		_save("user://terrain_edit_applied.png")
	if _f >= 125:
		quit(0)

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(path)
	if err == OK:
		print("screenshot_terrain_edit: saved ", path, "  ->  ", ProjectSettings.globalize_path(path))
	else:
		push_warning("screenshot_terrain_edit: save failed (%d) for %s" % [err, path])
