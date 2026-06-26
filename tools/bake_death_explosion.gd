extends SceneTree
# One-shot BAKE: render the composite Explosion (with bloom) to a horizontal sprite-sheet PNG + JSON, so enemy
# deaths can play a cheap flipbook instead of a live particle system. Run non-headless:
#   godot --path . --script tools/bake_death_explosion.gd
# Output: assets/fx/death_explosion/death_explosion.png (+ .json). Smoke is OFF (additive-baked gray looks bad);
# streaks are velocity-limited so the whole burst stays inside the frame. Background is black → play ADDITIVE.
const ExplosionFX := preload("res://scripts/gameplay/fx/explosion.gd")
const FRAME := 256
const COUNT := 18          # frames in the sheet
const STEP := 3            # capture every Nth rendered frame
const DELAY := 0.05        # seconds per sheet frame (≈ STEP/60)

var _sv: SubViewport = null
var _ex: Node2D = null
var _rf := 0               # rendered-frame counter
var _frames: Array = []    # captured Images

func _initialize() -> void:
	Engine.max_fps = 60     # so STEP frames ≈ DELAY seconds
	_sv = SubViewport.new()
	_sv.size = Vector2i(FRAME, FRAME)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.transparent_bg = false
	get_root().add_child(_sv)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)          # pure black → additive playback adds nothing here
	bg.size = Vector2(FRAME, FRAME)
	_sv.add_child(bg)
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 1.0; env.glow_strength = 1.0; env.glow_bloom = 0.1
	env.set_glow_level(1, 1.0); env.set_glow_level(2, 1.0); env.set_glow_level(3, 1.0); env.set_glow_level(4, 0.5)
	var we := WorldEnvironment.new(); we.environment = env
	_sv.add_child(we)
	_ex = ExplosionFX.new()
	_ex.set("shockwave_enabled", false)
	_ex.set("smoke_enabled", false)        # bake the fiery burst only (clean additive)
	_ex.set("time_scale", 1.0)
	_ex.set("streak_vel_min", 260.0); _ex.set("streak_vel_max", 480.0); _ex.set("streak_len", 0.9)  # contained
	_ex.set("fireball_amount", 32); _ex.set("streak_amount", 30)
	_sv.add_child(_ex)
	_ex.call("setup", Vector2(FRAME * 0.5, FRAME * 0.5), 40.0)   # small ref size; playback rescales
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	if _rf % STEP == 0 and _frames.size() < COUNT:
		var img := _sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		_frames.append(img)
	_rf += 1
	if _frames.size() >= COUNT:
		_save()
		quit(0)

func _save() -> void:
	var sheet := Image.create(FRAME * COUNT, FRAME, false, Image.FORMAT_RGBA8)
	for i in _frames.size():
		sheet.blit_rect(_frames[i], Rect2i(0, 0, FRAME, FRAME), Vector2i(i * FRAME, 0))
	DirAccess.make_dir_recursive_absolute("res://assets/fx/death_explosion")
	sheet.save_png("res://assets/fx/death_explosion/death_explosion.png")
	var delays: Array = []
	for _i in COUNT:
		delays.append(DELAY)
	var meta := {"cols": COUNT, "w": FRAME, "h": FRAME, "delays": delays}
	var f := FileAccess.open("res://assets/fx/death_explosion/death_explosion.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	print("BAKED ", COUNT, " frames → assets/fx/death_explosion/death_explosion.png")
