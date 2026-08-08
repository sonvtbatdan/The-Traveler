extends SceneTree
## One-off inspection: prints each landmark icon's opaque content bounding box (Image.get_used_rect()) so
## normalize_landmark_icon_widths.gd's TARGET_CONTENT_WIDTH can be picked sensibly (no blind guessing).
## Run headless: godot --headless --path . --script tools/inspect_landmark_icon_widths.gd

const PATHS := [
	"res://assets/map/rubicon/temple.png",
	"res://assets/map/volcanic/temple.png",
	"res://assets/map/rubicon/constructor.png",
	"res://assets/map/rubicon/mechanic.png",
	"res://assets/map/volcanic/engineer.png",
	"res://assets/map/volcanic/psyker.png",
	"res://assets/ruin/Scholar.png",
]

func _initialize() -> void:
	for path: String in PATHS:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			print(path, " -> FAILED TO LOAD")
			continue
		var used := img.get_used_rect()
		print(path, " canvas=", img.get_width(), "x", img.get_height(), " content=", used.size.x, "x", used.size.y)
	quit(0)
