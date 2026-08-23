extends SceneTree
var _f := 0
func _initialize() -> void:
	get_root().add_child((load("res://scenes/arena.tscn") as PackedScene).instantiate())
	RenderingServer.frame_post_draw.connect(_p)
func _p() -> void:
	_f += 1
	if _f == 90:
		var w := get_root().get_tree().get_first_node_in_group("arena_weapons")
		for k in ["gatling_gun", "defensive_orbitals", "aliwa", "yari_jaeger", "viper"]:
			w.call("acquire_weapon", k)
		get_root().get_tree().get_first_node_in_group("arena_hud_buttons").call("set_dev_mode", true)
	if _f == 150:
		# every inventory glb the level-up board can render
		var inv := get_root().get_node_or_null("InventoryManager")
		var defs: Dictionary = inv.get("ITEM_DEFS")
		var bad := 0; var n := 0
		for id in defs:
			var g: String = inv.call("get_glb", id)
			if g == "": continue
			n += 1
			if load(g) == null:
				bad += 1; print("  LOAD FAIL ", id, " -> ", g)
		print("inventory glbs: %d resolved, %d failed" % [n, bad])
		get_root().get_tree().get_first_node_in_group("arena_hud_buttons").call("_on_add_level")
	if _f == 300:
		var img := get_root().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8); img.save_png("user://check.png")
		print("ok")
		quit(0)
