extends Node2D
## lasgun_ani_5_caps — traveling packet glints for lasgun_ani_5 (soft additive glow blobs racing along
## the beam). Split into its own CanvasItem so it can carry a plain additive CanvasItemMaterial
## independent from the body's ShaderMaterial and the muzzle/impact procedural-fx materials. Unmodified
## copy of the packet block from lasgun_ani_1.gd — not a CPU hot path (<=3 draw calls/frame), so it
## stays exactly as it was to avoid any visual drift.

var beam   # untyped back-reference to the parent lasgun_ani_5.gd instance (dynamic access to its @export tunables)

var _packet_tex: Texture2D = null

# Per-frame state, pushed by the parent's _process() before it calls queue_redraw() on this node.
var _from := Vector2.ZERO
var _ang := 0.0
var _conv := Vector2.ZERO
var _L := 0.0
var _activation := 0.0
var _t := 0.0
var _bright := 1.0
var _thick := 0.0
var _center_y := 0.0

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	_packet_tex = _make_glow_tex(64)

## Soft radial-alpha glow: white core (alpha 1) fading smoothly to transparent at the rim (alpha 0).
func _make_glow_tex(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

## Piece colour: rgb scaled by `bright` (additive over-bright) + alpha = base.a * activation * alpha_mul.
func _lit(base: Color, bright: float, alpha_mul: float) -> Color:
	return Color(base.r * bright, base.g * bright, base.b * bright, base.a * _activation * alpha_mul)

func _draw() -> void:
	if _activation <= 0.0001:
		return
	draw_set_transform(_from, _ang, Vector2.ONE)

	# ── Traveling packets: soft additive glints racing convergence → impact ──
	if beam.packet_enabled and _packet_tex != null and _L - _conv.x > 4.0:
		var pcol := _lit(beam.packet_color, _bright, 1.0)
		var ph_h := maxf(1.0, _thick * beam.packet_width)
		for i in maxi(1, beam.packet_count):
			var ph := fposmod(_t * beam.packet_speed + float(i) / float(maxi(1, beam.packet_count)), 1.0)
			var px := lerpf(_conv.x, _L, ph)
			var edge := minf(ph, 1.0 - ph) / 0.15
			var pc := Color(pcol.r, pcol.g, pcol.b, pcol.a * clampf(edge, 0.0, 1.0))
			draw_texture_rect(_packet_tex,
				Rect2(px - beam.packet_len * 0.5, _center_y - ph_h * 0.5, beam.packet_len, ph_h), false, pc)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
