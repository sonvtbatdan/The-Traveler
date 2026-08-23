extends SceneTree
## One-shot post-process (2026-08-06, on request: "Scale lại các icon temple, landmark cho bằng width nếu
## chưa bằng") — crops each landmark/temple icon to its own opaque content bounding box (Image.get_used_
## rect()), rescales that content (aspect preserved) so every icon's CONTENT — not raw canvas — shares the
## same pixel WIDTH, then recomposes onto a common CANVASxCANVAS transparent square, overwriting the file in
## place. Confirmed via tools/inspect_landmark_icon_widths.gd that these were genuinely inconsistent before
## this pass: some (constructor/mechanic/engineer, hand-supplied) were already tightly cropped at their own
## native size (210-280px wide); others (the freshly-baked psyker/Scholar/volcanic-temple) sat on a full
## 512x512 canvas with lots of transparent padding, so their SUBJECT read much smaller once arena_ruin_
## pointer.gd scales the whole image to its fixed ICON_WIDTH — this pass makes that scale-down start from a
## consistent subject size across every one of them.
##
## Run headless (pure Image ops, no 3D/GPU needed):
##   godot --headless --path . --script tools/normalize_landmark_icon_widths.gd
## Then re-import (pixel dimensions changed on disk): godot --headless --path . --import --quit

const TARGET_PATHS := [
	"res://assets/map/electric/landmark/temple.png",
	"res://assets/map/volcanic/landmark/temple.png",
	"res://assets/map/electric/landmark/constructor.png",
	"res://assets/map/electric/landmark/mechanic.png",
	"res://assets/map/volcanic/landmark/engineer.png",
	"res://assets/map/volcanic/landmark/psyker.png",
	"res://assets/ruin/Scholar.png",
]
const TARGET_CONTENT_WIDTH := 280.0   # matches constructor.png's own native width (the largest of the
                                        # already-tightly-cropped set) — keeps most icons downscaled (safe,
                                        # no quality loss) and only mildly upscales the smallest ones.
const CANVAS := 400   # comfortably fits the tallest scaled content (~330px, volcanic temple) with padding

func _initialize() -> void:
	for path: String in TARGET_PATHS:
		_normalize(path)
	quit(0)

func _normalize(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		push_warning("normalize_landmark_icon_widths: failed to load " + path)
		return
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_warning("normalize_landmark_icon_widths: empty/blank image " + path)
		return
	var cropped := img.get_region(used)
	var scale := TARGET_CONTENT_WIDTH / float(cropped.get_width())
	var new_w := int(round(cropped.get_width() * scale))
	var new_h := int(round(cropped.get_height() * scale))
	if new_h > CANVAS:   # defensive: an unusually tall subject clamped by height instead, so it still fits
		var scale2 := float(CANVAS) / float(cropped.get_height())
		new_w = int(round(cropped.get_width() * scale2))
		new_h = int(round(cropped.get_height() * scale2))
	cropped.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var dst := Vector2i((CANVAS - new_w) / 2, (CANVAS - new_h) / 2)
	canvas.blit_rect(cropped, Rect2i(Vector2i.ZERO, Vector2i(new_w, new_h)), dst)
	var err := canvas.save_png(path)
	if err == OK:
		print("normalize_landmark_icon_widths: saved ", path, " content=", new_w, "x", new_h)
	else:
		push_warning("normalize_landmark_icon_widths: save failed (%d) for %s" % [err, path])
