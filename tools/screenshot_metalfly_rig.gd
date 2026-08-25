extends SceneTree
## DEV TOOL (2026-08-24) — the Metalfly body rig ON ITS OWN: no arena, no fight, no camera motion, heading
## pinned. Dumps one PNG per sampled frame of scripts/gameplay/fx/metalfly_rig.gd so the wing stroke, the
## fast beat and the mouth gape can be compared side by side.
##
## The in-arena tool (tools/screenshot_metalfly.gd) verifies the FIGHT; this one verifies the ANIMATION.
## It exists because the arena portraits were taken while the boss was turning hard onto a nearby player,
## so every frame had a different heading and the flap could not be read out of them.
##
## Run NON-headless (it renders):  godot --path . --script tools/screenshot_metalfly_rig.gd

const RigScript := preload("res://scripts/gameplay/fx/metalfly_rig.gd")
const HEADING   := PI * 0.5   # pinned: head toward screen-down, the same pose for every sample

var _rig: Node2D = null
var _f := 0
var _shot := 0

func _initialize() -> void:
	var host := Node2D.new()
	get_root().add_child(host)
	_rig = RigScript.new()
	host.add_child(_rig)
	if not _rig.call("setup"):
		print("rig setup FAILED")
		quit(1)
		return
	_rig.call("set_heading", HEADING)
	_rig.call("set_flap", "slow")
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	_rig.call("set_heading", HEADING)
	# 8 samples across one full slow beat (FLAP_HZ_SLOW 2.2 -> ~0.45s), then the fast beat, then the gape.
	if _f >= 30 and _f < 30 + 8 * 9 and (_f - 30) % 9 == 0:
		_grab("slow_%d" % _shot)
	if _f == 30 + 8 * 9:
		_rig.call("set_flap", "fast")
		_shot = 0
	if _f > 130 and _f < 130 + 4 * 3 and (_f - 130) % 3 == 0:
		_grab("fast_%d" % _shot)
	if _f == 150:
		_rig.call("set_mouth_open", true)
		_shot = 0
	if _f == 200:
		_grab("gape_open")
	if _f == 205:
		_rig.call("set_mouth_open", false)
		_rig.call("set_flap", "none")
	if _f == 260:
		_grab("gape_shut_wings_stopped")
		print("wings stopped -> flap_blend=", _rig.get("_flap_blend"), " mouth=", _rig.get("_mouth"))
	if _f == 265:
		_centroid_check()
	if _f > 270:
		quit(0)

## Is the rendered body actually CENTRED on the node? The Sprite2D is centred on this node's origin, so the
## alpha-weighted centroid of the viewport should land near the viewport centre; a large offset would mean
## the hitbox (and the HP bar, drawn at -_radius-8 by arena_enemy.gd) sits off the visible body.
func _centroid_check() -> void:
	var vp: SubViewport = _rig.get("_vp")
	var img := vp.get_texture().get_image()
	var sx := 0.0
	var sy := 0.0
	var sw := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.05:
				sx += float(x) * a
				sy += float(y) * a
				sw += a
	var cx := sx / maxf(sw, 0.001)
	var cy := sy / maxf(sw, 0.001)
	print("centroid=(%.1f, %.1f)  viewport centre=(%.1f, %.1f)  offset=(%.1f, %.1f) px"
		% [cx, cy, img.get_width() * 0.5, img.get_height() * 0.5,
		   cx - img.get_width() * 0.5, cy - img.get_height() * 0.5])

func _grab(tag: String) -> void:
	var vp: SubViewport = _rig.get("_vp")
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := "user://mfrig_%s.png" % tag
	print("grab ", path, " err=", img.save_png(path),
		"  flap_phase=%.2f  span=%.1f" % [_rig.get("_flap_phase"), _span()])
	_shot += 1

## Distance between the two wing-tip muzzles — the flap's on-screen amplitude, in px.
func _span() -> float:
	var m: Array = _rig.call("wing_muzzles")
	return (m[0] as Vector2).distance_to(m[1] as Vector2) if m.size() == 2 else -1.0
