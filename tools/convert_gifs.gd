## GIF → PNG sprite sheet converter.
##
## Run once from the project root:
##   godot --headless --script tools/convert_gifs.gd
##
## For each .gif found under res://assets/ it writes two files next to it:
##   <name>.sheet.png  — horizontal sprite sheet (all frames side-by-side)
##   <name>.sheet.json — {"cols":N, "w":W, "h":H, "delays":[...]}
##
## Already-converted files are skipped (safe to re-run).
## After running, open the Godot editor once so it imports the new .sheet.png
## files. Future game sessions load PNG natively — no GDScript LZW decode.
##
## Export note: add  *.sheet.json  to Project → Export → Resources →
## "Filters to export non-resource files" so delays survive the PCK.

extends SceneTree

const SEARCH_ROOT := "res://assets/"

func _init() -> void:
	print("=== GIF → PNG sprite sheet converter ===\n")
	var n_ok   := 0
	var n_skip := 0
	var n_fail := 0

	for gif_path: String in _find_gifs(SEARCH_ROOT):
		var base      := gif_path.get_basename()
		var png_path  := base + ".sheet.png"
		var json_path := base + ".sheet.json"
		var abs_png   := ProjectSettings.globalize_path(png_path)

		if FileAccess.file_exists(abs_png):
			print("  skip  " + gif_path.get_file())
			n_skip += 1
			continue

		print("  conv  " + gif_path.get_file() + " ...", false)
		if _convert(gif_path, abs_png, ProjectSettings.globalize_path(json_path)):
			print(" OK")
			n_ok += 1
		else:
			print(" FAIL")
			n_fail += 1

	print("\n%d converted, %d skipped, %d failed." % [n_ok, n_skip, n_fail])
	if n_ok > 0:
		print("Open the Godot editor once to import the new .sheet.png files.")
	quit()

# ── File discovery ─────────────────────────────────────────────────────────────

func _find_gifs(folder: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				result.append_array(_find_gifs(folder + entry + "/"))
		elif entry.get_extension().to_lower() == "gif":
			result.append(folder + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return result

# ── Conversion ──────────────────────────────────────────────────────────────────

func _convert(gif_path: String, abs_png: String, abs_json: String) -> bool:
	# Read raw bytes
	var f := FileAccess.open(gif_path, FileAccess.READ)
	if f == null:
		return false
	var bytes := f.get_buffer(f.get_length())
	f.close()

	if bytes.size() < 13:
		return false

	# Decode using the existing GDScript LZW decoder in GifLoader
	var frames: Array = GifLoader._decode_frames(bytes)
	if frames.is_empty():
		return false

	var n:  int = frames.size()
	var fw: int = (frames[0]["image"] as Image).get_width()
	var fh: int = (frames[0]["image"] as Image).get_height()

	# Build horizontal sprite sheet: width = fw * n, height = fh
	var sheet := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	var delays: Array = []
	for i: int in n:
		var img: Image = frames[i]["image"]
		sheet.blit_rect(img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
		delays.append(frames[i]["delay"])

	# Save PNG
	if sheet.save_png(abs_png) != OK:
		return false

	# Save JSON sidecar with frame layout and per-frame delays
	var meta := JSON.stringify({"cols": n, "w": fw, "h": fh, "delays": delays}, "\t")
	var jf := FileAccess.open(abs_json, FileAccess.WRITE)
	if jf == null:
		return false
	jf.store_string(meta)
	jf.close()
	return true
