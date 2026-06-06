extends RefCounted

static func load_png_sprite(path: String) -> Object:
	"""Load PNG sprite sheet and return object with gif_frames metadata"""
	var png_path := path.get_basename() + ".png"
	var json_path := path.get_basename() + ".json"

	# Load PNG image
	var png_tex := load(png_path) as Texture2D
	if png_tex == null:
		return null

	# Load JSON metadata
	var json_text := FileAccess.get_file_as_string(json_path)
	if json_text.is_empty():
		return null

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		return null

	var meta: Dictionary = json.data as Dictionary
	if meta.is_empty():
		return null

	# Extract sprite sheet info
	var frame_width: int = meta.get("frame_width", 0)
	var frame_height: int = meta.get("frame_height", 0)
	var frame_count: int = meta.get("frame_count", 0)
	var frames_data: Array = meta.get("frames", [])

	if frame_width <= 0 or frame_height <= 0 or frame_count <= 0:
		return null

	# Cut PNG into individual frames
	var image := png_tex.get_image()
	var frames: Array = []
	var delays: Array = []

	for i in range(frame_count):
		if i >= frames_data.size():
			break

		var frame_data: Dictionary = frames_data[i]
		var x: int = frame_data.get("x", i * frame_width)
		var y: int = frame_data.get("y", 0)
		var delay: float = frame_data.get("delay", 0.1)

		# Extract frame region
		var frame_img := Image.create(frame_width, frame_height, false, Image.FORMAT_RGBA8)
		for py in range(frame_height):
			for px in range(frame_width):
				var src_x := x + px
				var src_y := y + py
				if src_x < image.get_width() and src_y < image.get_height():
					frame_img.set_pixel(px, py, image.get_pixel(src_x, src_y))

		# Convert to ImageTexture
		var frame_tex := ImageTexture.create_from_image(frame_img)
		frames.append(frame_tex)
		delays.append(delay)

	# Return first frame texture with gif_frames metadata (compatible with GifLoader)
	if frames.is_empty():
		return png_tex

	var first_frame := frames[0] as Texture2D
	first_frame.set_meta("gif_frames", frames)
	first_frame.set_meta("gif_delays", delays)
	return first_frame
