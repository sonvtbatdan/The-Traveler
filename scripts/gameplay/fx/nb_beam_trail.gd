extends Node2D
## Nautilus Move 5 — the faint wake a sweeping beam leaves behind it. Samples the beam's angle every frame
## and fills the wedge between consecutive samples, fading each one out over TRAIL_T, so a spinning beam
## drags a soft comet-tail of where it just was instead of snapping between frames.
##
## World-space (parented to the arena root, absolute origin per sample) like the beam itself, so the boss
## drifting mid-sweep doesn't smear the whole trail with it.
##
## NOTE: no class_name — preload + .new(), matching this folder's convention.

const TRAIL_T   := 0.75     # seconds a sample stays visible — user: "vệt trail để lại cũng mờ"
const MAX_SAMPLES := 128    # ring cap — 0.75 s at 60 fps is ~45, this leaves headroom for a slow frame
const COL_NEAR  := Color(0.70, 0.93, 1.0, 0.85)   # at the origin (ADDITIVE, so this reads as bright light)
const COL_FAR   := Color(0.22, 0.60, 1.0, 0.10)   # at the beam's far end (fades along the length, not to 0)
const STEPS     := 4        # radial subdivisions per wedge — enough for a smooth length gradient

var _samples: Array = []    # [{o: Vector2, a: float, len: float, t: float}] oldest → newest

func begin() -> void:
	z_index = 4               # under the live beam (5), over the terrain
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # energy wake — glows, never darkens what's behind it
	material = mat
	set_process(true)

## One frame of the beam: absolute origin, canvas angle, length.
func push(origin: Vector2, angle: float, length: float) -> void:
	_samples.append({"o": origin, "a": angle, "len": length, "t": 0.0})
	if _samples.size() > MAX_SAMPLES:
		_samples.remove_at(0)

## Stop sampling and let whatever is on screen fade out, then free itself — so ending the move doesn't cut
## the wake off mid-air.
func finish() -> void:
	set_meta("closing", true)

func _process(delta: float) -> void:
	var i := _samples.size() - 1
	while i >= 0:
		var s: Dictionary = _samples[i]
		s["t"] = float(s["t"]) + delta
		if float(s["t"]) >= TRAIL_T:
			_samples.remove_at(i)
		i -= 1
	if _samples.is_empty() and bool(get_meta("closing", false)):
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _samples.size() < 2:
		return
	for i in _samples.size() - 1:
		var a: Dictionary = _samples[i]
		var b: Dictionary = _samples[i + 1]
		# Age of the OLDER edge drives the fade, so the wedge dims uniformly as it falls behind.
		var age := clampf(float(a["t"]) / TRAIL_T, 0.0, 1.0)
		var fade := 1.0 - age * age                 # holds bright longer, then drops away — reads as a real wake
		if fade <= 0.004:
			continue
		var da := float(a["a"])
		var db := float(b["a"])
		# Shortest way round, so crossing the ±PI seam doesn't draw a wedge the long way across the screen.
		db = da + wrapf(db - da, -PI, PI)
		var oa: Vector2 = a["o"]
		var ob: Vector2 = b["o"]
		var la := float(a["len"])
		var lb := float(b["len"])
		# Split along the LENGTH so the near-to-far colour gradient actually reads (draw_polygon interpolates
		# per-vertex, and a single quad from origin to tip would only get the two end colours).
		for k in STEPS:
			var t0 := float(k) / float(STEPS)
			var t1 := float(k + 1) / float(STEPS)
			var c0 := COL_NEAR.lerp(COL_FAR, t0); c0.a *= fade
			var c1 := COL_NEAR.lerp(COL_FAR, t1); c1.a *= fade
			draw_polygon(PackedVector2Array([
				oa + Vector2(cos(da), sin(da)) * (la * t0),
				oa + Vector2(cos(da), sin(da)) * (la * t1),
				ob + Vector2(cos(db), sin(db)) * (lb * t1),
				ob + Vector2(cos(db), sin(db)) * (lb * t0),
			]), PackedColorArray([c0, c1, c1, c0]))
