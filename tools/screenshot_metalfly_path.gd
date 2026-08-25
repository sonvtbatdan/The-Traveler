extends SceneTree
## DEV TOOL (2026-08-24) — the Metalfly telegraphs ON THEIR OWN, on a plain dark background: no arena, no
## boss, no 120 creeps drawn over them. The Move 2 charge lane (glow, blink, locked state) and the Move 3
## gathering ring (radial gradient, rim, radiating pulses), each dumped at several points in its cycle.
##
## Exists because the in-arena tool screenshots on STATE CHANGE, which for the lane is the frame it is
## created — i.e. always at alpha 0, mid fade-in, which is exactly when there is nothing to look at.
##
## Run NON-headless:  godot --path . --script tools/screenshot_metalfly_path.gd

const PathScript := preload("res://scripts/gameplay/fx/metalfly_charge_path.gd")
const RingScript := preload("res://scripts/gameplay/fx/metalfly_swarm_ring.gd")
const LANE_LEN   := 1200.0
const RING_R     := 110.0   # arena_enemy.gd's MF_SWARM_RING

var _path: Node2D = null
var _ring: Node2D = null
var _f := 0

func _initialize() -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_path = PathScript.new()
	root.add_child(_path)
	# Down and to the right, from near the top-left corner, so all 1200 px of it is in frame.
	_path.global_position = Vector2(80.0, 250.0)
	_path.call("set_beam", Vector2(0.82, 0.57).normalized(), LANE_LEN)
	_ring = RingScript.new()
	root.add_child(_ring)
	# The lane runs from (180,120) along (0.82,0.57) for 1200 px, i.e. straight through the middle of the
	# frame — the ring goes ABOVE that diagonal so the two never overlap in a screenshot.
	_ring.global_position = Vector2(1180.0, 190.0)
	_ring.call("begin", RING_R)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	# Three frames spread across the blink cycle, all fully faded in.
	if _f in [40, 46, 52]:
		_grab("windup_%d" % _f)
	if _f == 70:
		_path.call("lock")
	if _f == 90:
		_grab("locked")
		print("locked: the breath and flicker stop and the whole lane brightens by LOCKED_BOOST")
	# The ring is released the way Move 3 releases it, and must be gone a moment later.
	if _f == 100:
		_ring.call("release")
	if _f == 130:
		print("ring after release: visible=%s alpha=%.3f  (both must be false/0 — it is dropped the frame"
			% [str(_ring.visible), float(_ring.get("_alpha"))])
		print("                    the brood appears)")
		_grab("ring_released")
	if _f > 140:
		quit(0)

func _grab(tag: String) -> void:
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	print("grab user://mfpath_%s.png err=%d" % [tag, img.save_png("user://mfpath_%s.png" % tag)])
