extends SceneTree
## One-shot DEV TOOL (2026-08-23): boots the arena, turns dev mode on, opens WEAPON EDIT and screenshots the
## canvas with each 3D weapon selected — verifies the "object clipped in a small square frame" fix and that
## Swarmball/Swarmbot/shooter now get the 3D VIEW / MOUNT ANGLE panel.
## Run non-headless:  godot --path . --script tools/screenshot_weapon_edit_3d.gd

const SHOTS := ["ND-Aliwa-Bmr", "Yari-Jeager", "VIPER head top", "Swarmball", "Swarmbot", "shooter", "BC-SL-Spore"]
var _f := 0
var _we: Node = null

func _initialize() -> void:
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
		_we = get_root().get_tree().get_first_node_in_group("weapon_edit")
		if _we != null:
			_we.call("toggle")
		else:
			print("weapon_edit node NOT FOUND")
	# 15 frames per weapon: select, settle, shoot.
	var idx := int((_f - 110) / 15)
	var phase := (_f - 110) % 15
	if _f >= 110 and idx < SHOTS.size():
		if phase == 0 and _we != null:
			_we.call("_set_active_creep", SHOTS[idx])
		elif phase == 14:
			_save("user://we_%s.png" % String(SHOTS[idx]).replace(" ", "_"))
	if _f >= 110 + SHOTS.size() * 15 + 5:
		quit(0)

func _save(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(path)
	print("screenshot: ", path, " err=", err)
