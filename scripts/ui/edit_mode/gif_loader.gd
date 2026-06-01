class_name GifLoader
extends RefCounted

## Pure-GDScript animated GIF loader.
## Returns AnimatedTexture for multi-frame GIFs, ImageTexture for single-frame.

static func load_gif(path: String) -> Texture2D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()

	if bytes.size() < 13:
		return null
	# Verify "GIF" signature ('G','I','F')
	if bytes[0] != 71 or bytes[1] != 73 or bytes[2] != 70:
		return null

	var frames: Array = _decode_frames(bytes)
	if frames.is_empty():
		return null

	if frames.size() == 1:
		return ImageTexture.create_from_image(frames[0]["image"] as Image)

	# Build frame textures and store them as metadata on the first texture.
	# editable_object.gd reads this metadata to drive animation via _process().
	var frame_textures: Array = []
	var frame_delays: Array = []
	for fd: Dictionary in frames:
		frame_textures.append(ImageTexture.create_from_image(fd["image"] as Image))
		frame_delays.append(fd["delay"])

	var first_tex: ImageTexture = frame_textures[0] as ImageTexture
	first_tex.set_meta("gif_frames", frame_textures)
	first_tex.set_meta("gif_delays", frame_delays)
	return first_tex


static func _decode_frames(bytes: PackedByteArray) -> Array:
	var pos := 6  # skip 6-byte header

	var lsd_w: int = bytes[pos] | (bytes[pos + 1] << 8)
	var lsd_h: int = bytes[pos + 2] | (bytes[pos + 3] << 8)
	var packed: int = bytes[pos + 4]
	var gct_flag: bool  = (packed >> 7) != 0
	var gct_size: int   = packed & 7
	pos += 7  # Logical Screen Descriptor is 7 bytes

	var gct: PackedByteArray
	if gct_flag:
		var n: int = 1 << (gct_size + 1)
		gct = bytes.slice(pos, pos + n * 3)
		pos += n * 3

	var canvas := Image.create(lsd_w, lsd_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var restore_canvas: Image = null

	var gce_delay         := 0.1
	var gce_transparent   := -1
	var gce_disposal      := 0

	var frames: Array = []

	while pos < bytes.size() - 1:
		var b: int = bytes[pos]
		pos += 1

		if b == 0x3B:  # Trailer
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

			# Apply disposal of previous frame before drawing
			match gce_disposal:
				2: canvas.fill(Color.TRANSPARENT)
				3:
					if restore_canvas:
						canvas = restore_canvas.duplicate()
			if gce_disposal == 3:
				restore_canvas = canvas.duplicate()

			if pos >= bytes.size():
				break
			var mcs: int = bytes[pos]
			pos += 1

			# Collect LZW sub-blocks
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

			# Paint pixels onto canvas
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
			# Reset per-frame GCE state
			gce_delay       = 0.1
			gce_transparent = -1
			gce_disposal    = 0

		elif b == 0x21:  # Extension introducer
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
					var gp: int      = bytes[pos]
					gce_disposal     = (gp >> 3) & 7
					var has_transp: bool = (gp & 1) != 0
					var raw_d: int   = bytes[pos + 1] | (bytes[pos + 2] << 8)
					gce_delay        = raw_d / 100.0 if raw_d > 0 else 0.1
					gce_transparent  = bytes[pos + 3] if has_transp else -1
					pos += sub_len
				elif sub_len > 0:
					pos += mini(sub_len, bytes.size() - pos)
				# Block terminator
				if pos < bytes.size() and bytes[pos] == 0:
					pos += 1
			else:
				# Skip unknown extension sub-blocks
				while pos < bytes.size():
					var sub_len: int = bytes[pos]
					pos += 1
					if sub_len == 0:
						break
					pos += mini(sub_len, bytes.size() - pos)
		else:
			break  # Unknown block — stop parsing

	return frames


## LZW decompression (GIF variant — LSB-first bit packing).
static func _lzw_decode(data: PackedByteArray, min_code_size: int) -> PackedByteArray:
	var result := PackedByteArray()
	if data.is_empty() or min_code_size < 2 or min_code_size > 11:
		return result

	var clear_code: int = 1 << min_code_size
	var eoi_code:   int = clear_code + 1

	# Code table: each entry is a PackedByteArray of pixel indices.
	var code_table: Array = []
	for i: int in clear_code:
		code_table.append(PackedByteArray([i]))
	code_table.append(PackedByteArray())  # placeholder for clear_code
	code_table.append(PackedByteArray())  # placeholder for eoi_code

	var code_size: int = min_code_size + 1
	var next_code: int = eoi_code + 1
	var bit_pos:   int = 0
	var prev_code: int = -1

	while true:
		# Read next code (LSB-first)
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

		# First code after clear
		if prev_code == -1:
			if code < clear_code:
				result.append(code)
				prev_code = code
			continue

		var entry: PackedByteArray
		if code < code_table.size():
			entry = code_table[code]
			# skip empty placeholder entries (clear/eoi slots)
			if entry.is_empty() and code >= clear_code:
				break
		elif code == next_code:
			# Special case: code not yet added but equals next expected
			entry = code_table[prev_code].duplicate()
			entry.append(entry[0])
		else:
			break  # corrupted stream

		result.append_array(entry)

		if next_code < 4096:
			var new_entry: PackedByteArray = code_table[prev_code]
			new_entry = new_entry.duplicate()
			new_entry.append(entry[0])
			code_table.append(new_entry)
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1

		prev_code = code

	return result


## Rearrange interlaced pixel rows into normal top-to-bottom order.
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
