extends SceneTree
## One-shot DEV TOOL (2026-08-23): boots the arena, grants the 3D weapons (Swarm Host, Shooter, Yari Jaeger,
## Boomerang, VIPER) and screenshots gameplay — verifies the live .glb rigs render at the right size instead
## of a giant crop (Yari-Jeager) and that Swarmball/Swarmbot/shooter draw as 3D models at all.
## Run non-headless:  godot --path . --script tools/screenshot_arena_3d_weapons.gd

var _f := 0

func _initialize() -> void:
	var packed := load("res://scenes/arena.tscn") as PackedScene
	get_root().add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	if _f == 90:
		var w := get_root().get_tree().get_first_node_in_group("arena_weapons")
		if w == null:
			print("arena_weapons NOT FOUND"); quit(1); return
		for k in ["swarm", "shooter", "yari_jaeger", "aliwa", "viper"]:
			print("acquire ", k, " -> ", w.call("acquire_weapon", k))   # MAX_WEAPONS caps this at 5
	if _f == 220:
		_save("user://arena_3d_a.png")
	if _f == 400:
		_save("user://arena_3d_b.png")
	if _f == 700:
		_save("user://arena_3d_c.png")
		var w2 := get_root().get_tree().get_first_node_in_group("arena_weapons")
		if w2 != null:
			print("3D rigs up: ", (w2.get("_glb3d") as Dictionary).keys(),
				"  swarm_units=", (w2.get("_swarm_units") as Array).size(),
				"  shooter_orbs=", (w2.get("_shooter_orbs") as Array).size(),
				"  jaeger_ready=", w2.get("_jaeger3d_ready"))
	if _f >= 710:
		quit(0)

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	print("screenshot: ", path, " err=", img.save_png(path))
