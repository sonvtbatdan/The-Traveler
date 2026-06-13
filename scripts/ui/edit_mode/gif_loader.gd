class_name GifLoader
extends RefCounted

## Animated GIF loader — two code paths:
##
##  1. Sprite sheet (fast): if tools/convert_gifs.gd has been run, a
##     "<name>.sheet.png" + "<name>.sheet.json" exist next to the .gif.
##     The PNG is loaded by Godot's native importer (stb_image, GPU upload)
##     and sliced into per-frame AtlasTextures — no GDScript LZW needed.
##
##  2. GDScript fallback: the original pure-GDScript LZW decoder. Used the
##     first time (before conversion) or for any GIF that wasn't converted.
##
## Both paths return the same format expected by callers:
##   • Single-frame  → plain Texture2D
##   • Multi-frame   → first-frame Texture2D with metadata:
##       "gif_frames"  Array[Texture2D]  — one per frame
##       "gif_delays"  Array[float]      — seconds per frame

# In-memory cache (path → Texture2D). Prevents re-decoding within one session.
static var _cache: Dictionary = {}

# ---------------------------------------------------------------------------
# Public API — unchanged from original; all call sites stay the same.
# ---------------------------------------------------------------------------

static func load_gif(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path] as Texture2D

	var result := _load_from_sheet(path)
	if result == null:
		result = _load_via_gdscript(path)

	if result != null:
		_cache[path] = result
	return result

# ---------------------------------------------------------------------------
# Path 1 — sprite sheet (fast, native PNG)
# ---------------------------------------------------------------------------

static func _load_from_sheet(gif_path: String) -> Texture2D:
	var base      := gif_path.get_basename()
	var png_path  := base + ".sheet.png"
	var json_path := base + ".sheet.json"

	# Quick file-system check before doing anything heavier
	var abs_png  := ProjectSettings.globalize_path(png_path)
	var abs_json := ProjectSettings.globalize_path(json_path)
	if not FileAccess.file_exists(abs_png) or not FileAccess.file_exists(abs_json):
		return null

	# Read JSON sidecar
	var jf := FileAccess.open(abs_json, FileAccess.READ)
	if jf == null:
		return null
	var meta: Variant = JSON.parse_string(jf.get_as_text())
	jf.close()
	if not meta is Dictionary:
		return null

	var cols: int  = int(meta.get("cols", 1))
	var fw:   int  = int(meta.get("w",    1))
	var fh:   int  = int(meta.get("h",    1))
	var delays: Array = meta.get("delays", [])

	# Load the sprite sheet via FileAccess so the raw PNG bytes are always used.
	# Never use ResourceLoader/load() here: Godot's importer may pad non-POT
	# textures internally, making AtlasTexture region coordinates wrong and
	# causing visible misalignment. FileAccess bypasses the import pipeline and
	# also works inside an exported PCK (as long as *.sheet.png is in the export
	# non-resource filter).
	var sheet_tex: Texture2D
	var pf := FileAccess.open(png_path, FileAccess.READ)
	if pf != null:
		var img := Image.new()
		if img.load_png_from_buffer(pf.get_buffer(pf.get_length())) == OK:
			sheet_tex = ImageTexture.create_from_image(img)
	if sheet_tex == null:
		# Fallback: try the absolute OS path (works in editor, not in PCK)
		var img2 := Image.load_from_file(abs_png)
		if img2 != null:
			sheet_tex = ImageTexture.create_from_image(img2)

	if sheet_tex == null:
		return null

	# Single-frame shortcut
	if cols <= 1:
		return sheet_tex

	# Slice into per-frame AtlasTextures (all share the same ImageTexture upload).
	# filter_clip prevents bilinear sampling from bleeding into adjacent frames.
	var frame_textures: Array = []
	for i: int in cols:
		var atlas := AtlasTexture.new()
		atlas.atlas       = sheet_tex
		atlas.region      = Rect2(i * fw, 0, fw, fh)
		atlas.filter_clip = true
		frame_textures.append(atlas)

	# Pad delays array if JSON is shorter than frame count
	while delays.size() < cols:
		delays.append(0.1)

	var first := frame_textures[0] as AtlasTexture
	first.set_meta("gif_frames", frame_textures)
	first.set_meta("gif_delays", delays)
	return first

# ---------------------------------------------------------------------------
# Path 2 — GDScript LZW fallback (slow, always available)
# ---------------------------------------------------------------------------

static func _load_via_gdscript(path: String) -> Texture2D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()

	if bytes.size() < 13:
		return null
	if bytes[0] != 71 or bytes[1] != 73 or bytes[2] != 70:  # 'G','I','F'
		return null

	var frames: Array = _decode_frames(bytes)
	if frames.is_empty():
		return null

	_auto_convert(path, frames)

	if frames.size() == 1:
		return ImageTexture.create_from_image(frames[0]["image"] as Image)

	var frame_textures: Array = []
	var frame_delays:   Array = []
	for fd: Dictionary in frames:
		frame_textures.append(ImageTexture.create_from_image(fd["image"] as Image))
		frame_delays.append(fd["delay"])

	var first_tex: ImageTexture = frame_textures[0] as ImageTexture
	first_tex.set_meta("gif_frames", frame_textures)
	first_tex.set_meta("gif_delays", frame_delays)
	return first_tex

# Auto-convert GIF to sprite sheet on first load so future sessions use Path 1.
# Writes <name>.sheet.png + <name>.sheet.json next to the .gif.
# No-ops in exported PCKs (res:// is read-only); safe to call always.
static func _auto_convert(gif_path: String, frames: Array) -> void:
	if frames.is_empty():
		return
	var base      := gif_path.get_basename()
	var abs_png   := ProjectSettings.globalize_path(base + ".sheet.png")
	var abs_json  := ProjectSettings.globalize_path(base + ".sheet.json")
	if FileAccess.file_exists(abs_png):
		return

	var n:  int = frames.size()
	var fw: int = (frames[0]["image"] as Image).get_width()
	var fh: int = (frames[0]["image"] as Image).get_height()

	var sheet := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	var delays: Array = []
	for i: int in n:
		sheet.blit_rect(frames[i]["image"] as Image, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
		delays.append(frames[i]["delay"])

	if sheet.save_png(abs_png) != OK:
		return
	var jf := FileAccess.open(abs_json, FileAccess.WRITE)
	if jf == null:
		return
	jf.store_string(JSON.stringify({"cols": n, "w": fw, "h": fh, "delays": delays}, "\t"))
	jf.close()
	print("GifLoader: auto-converted %s → %d-frame sheet" % [gif_path.get_file(), n])

# ---------------------------------------------------------------------------
# GDScript LZW decoder (called by both _load_via_gdscript and convert_gifs.gd)
# ---------------------------------------------------------------------------

static func _decode_frames(bytes: PackedByteArray) -> Array:
	var pos := 6

	var lsd_w: int = bytes[pos] | (bytes[pos + 1] << 8)
	var lsd_h: int = bytes[pos + 2] | (bytes[pos + 3] << 8)
	var packed: int = bytes[pos + 4]
	var gct_flag: bool = (packed >> 7) != 0
	var gct_size: int  = packed & 7
	pos += 7

	if lsd_w <= 0 or lsd_h <= 0:
		return []

	var gct: PackedByteArray
	if gct_flag:
		var n: int = 1 << (gct_size + 1)
		gct = bytes.slice(pos, pos + n * 3)
		pos += n * 3

	var canvas := Image.create(lsd_w, lsd_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var restore_canvas: Image = null

	var gce_delay       := 0.1
	var gce_transparent := -1
	var gce_disposal    := 0
	var frames: Array   = []

	while pos < bytes.size() - 1:
		var b: int = bytes[pos]
		pos += 1

		if b == 0x3B:
			break

		elif b == 0x2C:  # Image Descriptor
			if pos + 9 > bytes.size():
				break
			var ix: int = bytes[pos] | (bytes[pos + 1] << 8)
			var iy: int = bytes[pos + 2] | (bytes[pos + 3] << 8)
			var iw: int = bytes[pos + 4] | (bytes[pos + 5] << 8)
			var ih: int = bytes[pos + 6] | (bytes[pos + 7] << 8)
			var ipk: int = bytes[pos + 8]
			var lct_flag:   bool = (ipk >> 7) != 0
			var interlaced: bool = ((ipk >> 6) & 1) != 0
			var lct_size:   int  = ipk & 7
			pos += 9

			var color_table := gct
			if lct_flag:
				var n: int = 1 << (lct_size + 1)
				if pos + n * 3 <= bytes.size():
					color_table = bytes.slice(pos, pos + n * 3)
					pos += n * 3

			# All game sprites are complete images per frame — always clear before drawing.
			# disposal=1 (keep canvas) caused frame stacking; we unconditionally clear instead.
			# disposal=3 (restore previous) restore is a no-op when we always clear.
			var pre_frame_canvas: Image = null
			canvas.fill(Color.TRANSPARENT)

			if pos >= bytes.size():
				break
			var mcs: int = bytes[pos]
			pos += 1

			var lzw_data := PackedByteArray()
			while pos < bytes.size():
				var sub_len: int = bytes[pos]
				pos += 1
				if sub_len == 0:
					break
				var end := mini(pos + sub_len, bytes.size())
				lzw_data.append_array(bytes.slice(pos, end))
				pos += sub_len

			var indices := _lzw_decode(lzw_data, mcs)
			if interlaced:
				indices = _deinterlace(indices, iw, ih)

			var pi := 0
			for py: int in ih:
				for px: int in iw:
					if pi >= indices.size():
						break
					var idx: int = indices[pi]
					pi += 1
					if idx == gce_transparent:
						continue
					var ct_off: int = idx * 3
					if ct_off + 2 >= color_table.size():
						continue
					if ix + px < lsd_w and iy + py < lsd_h:
						canvas.set_pixel(ix + px, iy + py, Color8(
							color_table[ct_off],
							color_table[ct_off + 1],
							color_table[ct_off + 2]
						))

			frames.append({"image": canvas.duplicate(), "delay": maxf(gce_delay, 0.02)})
			gce_delay       = 0.1
			gce_transparent = -1
			gce_disposal    = 0

		elif b == 0x21:  # Extension
			if pos >= bytes.size():
				break
			var label: int = bytes[pos]
			pos += 1
			if label == 0xF9:  # Graphic Control Extension
				if pos >= bytes.size():
					break
				var sub_len: int = bytes[pos]
				pos += 1
				if sub_len == 4 and pos + 4 <= bytes.size():
					var gp: int       = bytes[pos]
					gce_disposal      = (gp >> 3) & 7
					var has_transp: bool = (gp & 1) != 0
					var raw_d: int    = bytes[pos + 1] | (bytes[pos + 2] << 8)
					gce_delay         = raw_d / 100.0 if raw_d > 0 else 0.1
					gce_transparent   = bytes[pos + 3] if has_transp else -1
					pos += sub_len
				elif sub_len > 0:
					pos += mini(sub_len, bytes.size() - pos)
				if pos < bytes.size() and bytes[pos] == 0:
					pos += 1
			else:
				while pos < bytes.size():
					var sub_len: int = bytes[pos]
					pos += 1
					if sub_len == 0:
						break
					pos += mini(sub_len, bytes.size() - pos)
		else:
			break

	return frames


static func _lzw_decode(data: PackedByteArray, min_code_size: int) -> PackedByteArray:
	var result := PackedByteArray()
	if data.is_empty() or min_code_size < 2 or min_code_size > 11:
		return result

	var clear_code: int = 1 << min_code_size
	var eoi_code:   int = clear_code + 1

	var code_table: Array = []
	for i: int in clear_code:
		code_table.append(PackedByteArray([i]))
	code_table.append(PackedByteArray())
	code_table.append(PackedByteArray())

	var code_size: int = min_code_size + 1
	var next_code: int = eoi_code + 1
	var bit_pos:   int = 0
	var prev_code: int = -1

	while true:
		var code := 0
		var filled := 0
		while filled < code_size:
			var byte_idx: int = bit_pos >> 3
			if byte_idx >= data.size():
				return result
			var bit_off: int = bit_pos & 7
			var avail:   int = 8 - bit_off
			var need:    int = code_size - filled
			var take:    int = mini(avail, need)
			code  |= ((data[byte_idx] >> bit_off) & ((1 << take) - 1)) << filled
			filled  += take
			bit_pos += take

		if code == eoi_code:
			break
		if code == clear_code:
			while code_table.size() > eoi_code + 1:
				code_table.pop_back()
			code_size = min_code_size + 1
			next_code = eoi_code + 1
			prev_code = -1
			continue
		if prev_code == -1:
			if code < clear_code:
				result.append(code)
				prev_code = code
			continue

		var entry: PackedByteArray
		if code < code_table.size():
			entry = code_table[code]
			if entry.is_empty() and code >= clear_code:
				break
		elif code == next_code:
			entry = code_table[prev_code].duplicate()
			entry.append(entry[0])
		else:
			break

		result.append_array(entry)

		if next_code < 4096:
			var new_entry: PackedByteArray = code_table[prev_code].duplicate()
			new_entry.append(entry[0])
			code_table.append(new_entry)
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1

		prev_code = code

	return result


static func _deinterlace(pixels: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(w * h)
	var src_row := 0
	for pass_data: Array in [[0, 8], [4, 8], [2, 4], [1, 2]]:
		var dst_row: int = pass_data[0]
		var step:    int = pass_data[1]
		while dst_row < h:
			for x: int in w:
				var si: int = src_row * w + x
				var di: int = dst_row * w + x
				if si < pixels.size() and di < result.size():
					result[di] = pixels[si]
			src_row += 1
			dst_row += step
	return result
