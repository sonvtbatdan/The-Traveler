extends MultiMeshInstance2D
## Tier-2 plume batching: a SINGLE MultiMesh node that renders EVERY enemy plume in one draw call.
##
## Tier-1 gave each flipbook enemy a Sprite2D per thrust point (no particle sim, but still a node per plume).
## This removes those nodes: enemies register their plumes here (add_plume → a STABLE slot handle), write
## pos/rot/frame each frame (write_plume) or hide them off-screen (hide_plume), and free them on death
## (free_plume). Frame selection + additive glow happen in a canvas_item shader that reads INSTANCE_CUSTOM.x
## (the flipbook frame index) against a baked horizontal atlas of PLUME frames. Lives at world origin on the
## sharp gameplay plane → instance transforms ARE world positions. Found by callers via group "arena_plume_mgr".
##
## Slots use a free-list (never swap-remove) so an enemy's handle stays valid for its whole life; a freed slot
## goes scale-0 (a degenerate, effectively free quad) and is reused by the next add_plume.

const FRAMES     := 14      # flipbook frames baked into the atlas (must match arena_enemy.PLUME_FB_FRAMES)
const FRAME_W    := 44      # per-frame atlas cell width (px); canonical jet points +X
const FRAME_H    := 32      # per-frame atlas cell height (px)
const MAX_PLUMES := 12000   # MultiMesh buffer size (stable slots; freed slots reused via _free)

var _free: Array[int] = []   # reusable slot indices (stable handles → free-list)
var _count: int = 0          # high-water slot count = visible_instance_count

const SHADER_CODE := "shader_type canvas_item;\n" \
	+ "render_mode blend_add, unshaded;\n" \
	+ "uniform sampler2D atlas : source_color, filter_linear;\n" \
	+ "uniform float frames;\n" \
	+ "varying flat float v_frame;\n" \
	+ "void vertex() { v_frame = INSTANCE_CUSTOM.x; }\n" \
	+ "void fragment() {\n" \
	+ "	float cell = 1.0 / frames;\n" \
	+ "	vec2 uv = vec2((floor(v_frame) + UV.x) * cell, UV.y);\n" \
	+ "	vec4 t = texture(atlas, uv);\n" \
	+ "	COLOR = vec4(t.rgb * COLOR.rgb, t.a * COLOR.a);\n" \
	+ "}\n"

func _ready() -> void:
	add_to_group("arena_plume_mgr")
	_ensure_built()

## Build the MultiMesh + shader lazily (idempotent) so a plume registered before _ready can't hit a null buffer.
func _ensure_built() -> void:
	if multimesh != null:
		return
	z_index = 1               # plumes read above the enemy bodies (matches the old CPUParticles2D z_index)
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var atlas := _bake_atlas()
	texture = atlas           # (unused by the shader, but keeps a valid canvas texture)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE   # unit quad, centered; scaled per-instance to the plume footprint
	mm.mesh = quad
	mm.instance_count = MAX_PLUMES
	mm.visible_instance_count = 0
	multimesh = mm
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("atlas", atlas)
	mat.set_shader_parameter("frames", float(FRAMES))
	material = mat

## Reserve a plume slot with a fixed tint. Returns a stable handle (slot index), or -1 if the buffer is full.
func add_plume(tint: Color) -> int:
	_ensure_built()
	var slot: int
	if not _free.is_empty():
		slot = _free.pop_back()
	elif _count < MAX_PLUMES:
		slot = _count
		_count += 1
		multimesh.visible_instance_count = _count
	else:
		return -1
	multimesh.set_instance_color(slot, tint)
	multimesh.set_instance_custom_data(slot, Color(0.0, 0.0, 0.0, 0.0))
	_hide(slot)
	return slot

## Place + animate a plume this frame: full transform (pos/rot/scale) + the flipbook frame (custom data).
func write_plume(slot: int, pos: Vector2, rot: float, scale_px: float, frame: int) -> void:
	if slot < 0 or multimesh == null:
		return
	multimesh.set_instance_transform_2d(slot, Transform2D(rot, Vector2(scale_px, scale_px), 0.0, pos))
	multimesh.set_instance_custom_data(slot, Color(float(frame), 0.0, 0.0, 0.0))

## Collapse a plume to nothing (off-screen) without releasing its slot.
func hide_plume(slot: int) -> void:
	if slot >= 0:
		_hide(slot)

## Release a plume slot back to the free-list (enemy died / despawned).
func free_plume(slot: int) -> void:
	if slot < 0:
		return
	_hide(slot)
	_free.append(slot)

func _hide(slot: int) -> void:
	if multimesh == null:
		return
	multimesh.set_instance_transform_2d(slot, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))

## Bake the shared atlas: FRAMES cells in a horizontal strip. Each cell is a white additive "jet" (emitter at
## centre, teardrop toward +X) that flickers per frame. Tint + additive blend happen in the shader.
func _bake_atlas() -> ImageTexture:
	var img := Image.create(FRAME_W * FRAMES, FRAME_H, false, Image.FORMAT_RGBA8)
	for f in FRAMES:
		var ph := TAU * float(f) / float(FRAMES)
		for iy in FRAME_H:
			for ix in FRAME_W:
				var nx := (float(ix) + 0.5) / float(FRAME_W)
				var ny := (float(iy) + 0.5) / float(FRAME_H)
				var dx := nx - 0.5
				var dy := ny - 0.5
				var tail := clampf(dx / 0.5, 0.0, 1.0)              # 0 at centre → 1 at +X tip
				var width := 0.10 + 0.16 * (1.0 - tail)             # narrows toward the tip
				var cross: float = exp(-(dy * dy) / (2.0 * width * width))
				var flick := 0.70 + 0.30 * sin(ph + tail * TAU)
				var body := (1.0 - tail) * cross * flick            # jet body, brightest near centre
				var core: float = exp(-(dx * dx + dy * dy) / (2.0 * 0.02))   # hot centre blob
				var a := clampf(body * 0.85 + core * 0.9, 0.0, 1.0)
				img.set_pixel(f * FRAME_W + ix, iy, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
