## Enemy sprite DOWNSCALER.
##
## Run once from the project root (re-run any time after you resize creeps/fleets):
##   godot --headless --script tools/downscale_enemies.gd
##   godot --headless --import --path .      ← then import so the game loads the .ctex
##
## The HD source art in assets/enemiesHD/ is 500–1500 px wide but each creep is only DRAWN at ~25–80 px on the
## arena, so every frame the GPU downsamples a huge texture. This bakes a small copy of each sprite at its real
## display size into  assets/Enemies Downscale/  (same filename). At runtime arena_enemy.gd._resolve_sprite()
## prefers that folder, so spawns use the light texture. If a downscaled file is missing the game falls back to
## the HD sprite automatically — so it is always safe to skip / re-run.
##
## Display width per sprite = max( creep_layout size, every fleet_layout slot size that uses it ) × HEADROOM.
## HEADROOM covers the ±SCALE_VAR (0.15) per-enemy size variance + spawn-pop overshoot so it stays crisp.
## Animated (.gif) and sheet (.sheet.png) sprites are skipped — they are not plain single-frame textures.

extends SceneTree

const WaveDir := preload("res://scripts/gameplay/arena_wave_director.gd")
const OUT_DIR := "res://assets/Enemies Downscale/"
const HEADROOM := 1.25

func _init() -> void:
	print("=== Enemy sprite downscaler ===\n")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# 1) Largest display width any FLEET slot renders each enemy at (fleet ids → ENEMY_DEFS icon filename).
	var fleet_w: Dictionary = {}
	var fcfg := ConfigFile.new()
	if fcfg.load("res://fleet_layout.cfg") == OK:
		var data = fcfg.get_value("fleets", "data", [])
		if data is Array:
			for fl in data:
				for s in (fl as Dictionary).get("slots", []):
					var w := float((s as Dictionary).get("size", 0.0))
					for en in (s as Dictionary).get("enemies", []):
						var d: Dictionary = WaveDir.ENEMY_DEFS.get(String(en), {})
						var ic := String(d.get("icon", ""))
						if ic == "":
							continue
						var fn := ic.get_file()
						fleet_w[fn] = maxf(float(fleet_w.get(fn, 0.0)), w)

	# 2) Walk every creep in creep_layout.cfg (covers bodies AND sub-parts: centipede/squid segments).
	var ccfg := ConfigFile.new()
	if ccfg.load("res://creep_layout.cfg") != OK or not ccfg.has_section("creeps"):
		print("creep_layout.cfg missing or has no [creeps] — nothing to do.")
		quit()
		return

	var n_ok := 0
	var n_copy := 0
	var n_skip := 0
	var n_fail := 0
	for key: String in ccfg.get_section_keys("creeps"):
		var eo: Dictionary = ccfg.get_value("creeps", key, {})
		var path := String(eo.get("path", ""))
		if path == "" or not path.ends_with(".png") or path.ends_with(".sheet.png"):
			n_skip += 1
			continue
		var fn := path.get_file()
		var disp_w := float((eo.get("size", Vector2.ZERO) as Vector2).x)
		disp_w = maxf(disp_w, float(fleet_w.get(fn, 0.0)))
		if disp_w <= 0.0:
			n_skip += 1
			continue
		if not FileAccess.file_exists(path):
			# Stale creep_layout entry — the HD sprite was removed (dropped enemy). Nothing to bake.
			n_skip += 1
			continue
		var img := Image.load_from_file(path)
		if img == null:
			print("  FAIL load  ", path)
			n_fail += 1
			continue
		var iw := img.get_width()
		var ih := img.get_height()
		if iw <= 0 or ih <= 0:
			n_fail += 1
			continue
		var target_w := int(ceil(disp_w * HEADROOM))
		if target_w >= iw:
			# Display size >= source: never upscale — just copy the original through.
			if img.save_png(OUT_DIR + fn) == OK:
				print("  copy  %-26s %d x %d (>= display)" % [fn, iw, ih])
				n_copy += 1
			else:
				n_fail += 1
			continue
		var target_h := maxi(1, int(round(float(target_w) * float(ih) / float(iw))))
		img.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
		if img.save_png(OUT_DIR + fn) == OK:
			print("  bake  %-26s %d x %d  ->  %d x %d" % [fn, iw, ih, target_w, target_h])
			n_ok += 1
		else:
			print("  FAIL save  ", fn)
			n_fail += 1

	print("\nDone. baked=%d  copied=%d  skipped=%d  failed=%d" % [n_ok, n_copy, n_skip, n_fail])
	print("Now run:  godot --headless --import --path .   (so the game imports the new textures)")
	quit()
