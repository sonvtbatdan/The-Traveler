extends CanvasLayer
## Yu-Gi-Oh-style weapon FUSION cutscene. play(def_id_a, def_id_b, result_def_id) runs a ~3s sequence while
## the tree is paused (PROCESS_MODE_ALWAYS), then emits `finished`:
##   • SUCTION — the two source weapon icons spaghettify and spiral into a growing black hole.
##   • NOVA    — a blinding white flash + expanding light ring as the fusion completes.
##   • REVEAL  — the fused weapon icon blooms in (placeholder = source-icon stack until the real art lands).
## Self-contained + pause-safe: all visuals are analytic (driven by one elapsed-time `_t` in _process) + a custom
## _draw for the black hole / nova ring, so it needs neither the arena WorldEnvironment nor any screen texture.
## Found by the level-up UI via group "arena_fusion_cutscene"; it awaits `finished` before performing the fuse.

signal finished

const SUCTION_T := 1.4
const NOVA_T    := 0.7
const REVEAL_T  := 1.0
const TOTAL_T   := SUCTION_T + NOVA_T + REVEAL_T

const ICON_START_OFFSET := 190.0   # how far left/right the source icons start from centre (px)
const ICON_SIZE         := 96.0

var _playing := false
var _t := 0.0
var _center := Vector2.ZERO
var _canvas: Control = null        # full-rect host for _draw (black hole + nova ring)
var _backdrop: ColorRect = null
var _flash: ColorRect = null
var _icon_a: TextureRect = null
var _icon_b: TextureRect = null
var _result: TextureRect = null

func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("arena_fusion_cutscene")
	visible = false
	set_process(false)

## Run the cutscene. Returns immediately; the caller should `await <node>.finished`.
func play(def_id_a: String, def_id_b: String, result_def_id: String) -> void:
	if _playing:
		return
	_playing = true
	_t = 0.0
	_build(def_id_a, def_id_b, result_def_id)
	visible = true
	set_process(true)
	_sfx("res://assets/audio/sfx/uialert.wav")

func _build(def_id_a: String, def_id_b: String, result_def_id: String) -> void:
	for c in get_children():
		c.queue_free()
	var vp := get_viewport().get_visible_rect().size
	_center = vp * 0.5

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow clicks during the cutscene
	add_child(_backdrop)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_script(_CanvasScript)
	_canvas.set("owner_cutscene", self)
	add_child(_canvas)

	_icon_a = _make_icon(def_id_a)
	_icon_b = _make_icon(def_id_b)
	add_child(_icon_a)
	add_child(_icon_b)

	_result = _make_icon(result_def_id)
	_result.modulate = Color(1, 1, 1, 0)
	_result.scale = Vector2.ZERO
	add_child(_result)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

func _make_icon(def_id: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = Vector2(ICON_SIZE, ICON_SIZE)
	tr.pivot_offset = Vector2(ICON_SIZE, ICON_SIZE) * 0.5
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = InventoryManager.get_icon(def_id) if def_id != "" else null
	if tex != null:
		tr.texture = tex
	else:
		tr.modulate = Color(1.0, 0.82, 0.30)   # gold placeholder tint if no art
	return tr

func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var center := _center

	# ── Phase 1: SUCTION ──
	if _t < SUCTION_T:
		var u := clampf(_t / SUCTION_T, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)   # smoothstep ease
		_backdrop.color = Color(0, 0, 0, 0.72 * clampf(_t / 0.3, 0.0, 1.0))
		_place_suck(_icon_a, center + Vector2(-ICON_START_OFFSET, -20.0), e, u)
		_place_suck(_icon_b, center + Vector2(ICON_START_OFFSET, -20.0), e, u)
	# ── Phase 2: NOVA ──
	elif _t < SUCTION_T + NOVA_T:
		var nu := clampf((_t - SUCTION_T) / NOVA_T, 0.0, 1.0)
		_icon_a.visible = false
		_icon_b.visible = false
		_backdrop.color = Color(0, 0, 0, 0.72)
		# Flash spikes to white instantly then fades over the phase.
		_flash.color = Color(1, 1, 1, clampf(1.0 - nu, 0.0, 1.0) if nu > 0.1 else nu / 0.1)
	# ── Phase 3: REVEAL ──
	elif _t < TOTAL_T:
		var ru := clampf((_t - SUCTION_T - NOVA_T) / REVEAL_T, 0.0, 1.0)
		_flash.color = Color(1, 1, 1, 0)
		# Result icon pops in (overshoot), centred, then everything fades at the tail.
		var grow := clampf(ru / 0.4, 0.0, 1.0)
		var s := _overshoot(grow) * 1.6
		_result.scale = Vector2(s, s)
		_result.position = center - _result.size * 0.5 * s
		_result.modulate = Color(1, 1, 1, clampf(ru / 0.25, 0.0, 1.0))
		var fade := clampf((ru - 0.7) / 0.3, 0.0, 1.0)
		_backdrop.color = Color(0, 0, 0, 0.72 * (1.0 - fade))
		_result.modulate.a = 1.0 - fade
	else:
		_end()
		return

	if _t >= SUCTION_T and _t < SUCTION_T + 0.05:
		_sfx("res://assets/audio/sfx/gunboom1.wav")   # the nova boom (fires once on the suction→nova boundary)
	_canvas.queue_redraw()

## Position/scale/rotation for an icon being sucked into the centre (spaghettify: thin across, stretched toward it).
func _place_suck(tr: TextureRect, start: Vector2, e: float, u: float) -> void:
	if tr == null:
		return
	var pos := start.lerp(_center, e)
	var to_center := (_center - pos)
	tr.position = pos - tr.size * 0.5
	var sx := lerpf(1.0, 0.06, e)
	var sy := lerpf(1.0, 1.9, e) * lerpf(1.0, 0.1, clampf((u - 0.7) / 0.3, 0.0, 1.0))
	tr.scale = Vector2(sx, sy)
	tr.rotation = to_center.angle() + PI * 0.5 + u * TAU * 1.5   # align stretch toward centre + accelerating spin

func _overshoot(x: float) -> float:
	var c := 1.70158
	var p := x - 1.0
	return 1.0 + (c + 1.0) * p * p * p + c * p * p

func _end() -> void:
	_playing = false
	set_process(false)
	visible = false
	finished.emit()

func _sfx(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# Black-hole / nova-ring drawing (a small inner script set on _canvas so its _draw runs in screen space).
const _CanvasScript := preload("res://scripts/gameplay/arena_fusion_cutscene_canvas.gd")
