extends Node2D
## LedLight — a small glowing/blinking light anchored on a creep (Creep Edit "Add Led" points). Same
## soft-glow drawing approach as energy_vortex.gd / the plume dot texture (creep_edit_mode.gd's
## _make_preview_plume()) — additive blend, a procedurally generated radial-falloff dot stretched to W×H,
## no external texture/particles needed.
##
## NOTE: intentionally NO class_name — instantiate via preload + .new() and type the var as Node2D, then call
## setup() dynamically. Typing by a fresh class_name can break a headless first-boot (same lesson as ZSlash/
## EnergyVortex).

const TEX_N := 32   # glow texture resolution — cheap, shared shape for any W×H via draw_texture_rect stretch

var w: float = 12.0
var h: float = 12.0
var color: Color = Color(1.0, 0.85, 0.35, 1.0)
var intensity: float = 1.0   # additive brightness multiplier (0 = off, 1 = default, >1 = overbright)
var blink_hz: float = 0.0    # 0 = steady; >0 = smooth brightness pulse at this frequency ("nhấp nháy")
var phase_deg: float = 0.0   # 2026-08-15 — shifts this LED's own blink cycle (0-360°); set increasing Phase
                              # across a row of LEDs (head→tail) to read as a running "wave" signal strip

var _t: float = 0.0
var _tex: Texture2D = null

func _ready() -> void:
	z_index = 3
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive → reads as a glowing light, not a flat sprite
	material = cm
	_tex = _build_glow_tex()

## Configure from a style dict (the same dict Creep Edit's LED panel edits + saves).
func setup(style: Dictionary) -> void:
	w         = float(style.get("w", w))
	h         = float(style.get("h", h))
	color     = style.get("color", color)
	intensity = float(style.get("intensity", intensity))
	blink_hz  = float(style.get("blink_hz", blink_hz))
	phase_deg = float(style.get("phase_deg", phase_deg))
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if blink_hz > 0.0:
		queue_redraw()

## 0-1 brightness factor from the Blink slider (0-60 Hz, "0 = không nhấp nháy, 60 = nháy 60Hz"). Steady at
## 1.0 when off; otherwise a smooth sine pulse between a dim floor and full brightness — reads as a flicker
## rather than a jarring hard on/off strobe, and stays well-defined at every Hz including 60.
func _blink_factor() -> float:
	if blink_hz <= 0.0:
		return 1.0
	return 0.15 + 0.85 * (0.5 + 0.5 * sin(TAU * blink_hz * _t - deg_to_rad(phase_deg)))

func _draw() -> void:
	if _tex == null:
		return
	var c := color
	c.a *= _blink_factor() * intensity
	var sz := Vector2(maxf(w, 0.5), maxf(h, 0.5))
	draw_texture_rect(_tex, Rect2(-sz * 0.5, sz), false, c)

## Soft radial-falloff dot (white, alpha only) stretched to W×H at draw time — same technique
## creep_edit_mode.gd's _make_preview_plume() uses for its particle dot.
func _build_glow_tex() -> Texture2D:
	var img := Image.create(TEX_N, TEX_N, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(TEX_N, TEX_N) * 0.5
	for iy in TEX_N:
		for ix in TEX_N:
			var d: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / (TEX_N * 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)
