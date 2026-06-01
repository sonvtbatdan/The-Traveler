# Renders one hand-cursor per owned autoclicker, tips flush against the
# silhouette of the largest "view_screen" sprite (alpha-edge detection).
# Cursors animate a sequential click jab inward then rebound.
class_name AutoClickerOverlay
extends CanvasLayer

const TIP_LEN      := 15.0   # local-space distance pivot → tip (matches _draw)
const REST_GAP     :=  2.0   # screen-px the tip hovers outside the edge at rest
const CLICK_DEPTH  :=  5.0   # screen-px the tip sinks into sprite at peak click
const CLICK_DUR    :=  0.22  # seconds for the jab thrust
const CLICK_PERIOD :=  3.0   # seconds between clicks
const ALPHA_THRESH :=  0.05  # alpha threshold for "opaque" during edge march
const RING_GAP     := 14.0   # extra outward px added per additional ring
const CURSOR_SLOT  := 11.0   # tangential px per cursor slot (cursor width 10 + 1px gap)
const PERIM_SAMPLE := 64     # edge samples used only for perimeter measurement

var _cursors: Array[Control] = []
var _t:       float          = 0.0

# Edge cache — _ring_size computed from silhouette perimeter; rebuilt when sprite rect changes
var _ring_size:  int            = 0
var _edge_pts:   Array[Vector2] = []
var _cache_rect: Rect2          = Rect2()
var _img_cache:  Image          = null
var _img_cache_path: String     = ""
var _hand_tex:   Texture2D      = null

func _ready() -> void:
	layer = 11
	_hand_tex = load("res://assets/screen/handcursor.png") as Texture2D
	GameManager.game_loaded.connect(_on_game_loaded)
	UpgradeManager.upgrade_purchased.connect(_on_purchased)
	UpgradeManager.upgrades_reset.connect(_on_reset)

func _on_game_loaded() -> void:
	var n := UpgradeManager.get_owned_count("autoclicker")
	for _i in n:
		_spawn_cursor()

func _on_purchased(id: String) -> void:
	if id == "autoclicker":
		_spawn_cursor()

func _on_reset() -> void:
	for c in _cursors:
		c.queue_free()
	_cursors.clear()
	_cache_rect = Rect2()

func _spawn_cursor() -> void:
	var c := _HandCursor.new(_hand_tex)
	add_child(c)
	_cursors.append(c)

# ── Scene queries ─────────────────────────────────────────────────────────────

func _get_view_ctrl() -> Control:
	var best_area := -1.0
	var best_ctrl: Control = null
	for node in get_tree().get_nodes_in_group("view_screen"):
		var ctrl := node as Control
		if not is_instance_valid(ctrl) or not ctrl.visible:
			continue
		var sz   := ctrl.size
		var area := sz.x * sz.y
		if area > best_area:
			best_area = area
			best_ctrl = ctrl
	return best_ctrl

func _in_edit_mode() -> bool:
	var dim := get_parent().get_node_or_null("EditMode/DimOverlay") as CanvasItem
	return is_instance_valid(dim) and dim.visible

# ── Edge cache ────────────────────────────────────────────────────────────────

func _rebuild_cache(ctrl: Control) -> void:
	_cache_rect = ctrl.get_global_rect()
	var img := _load_ctrl_image(ctrl)

	# ── Phase 1: sample PERIM_SAMPLE edge points at equal angles ──────────────────
	var sample := PackedVector2Array()
	sample.resize(PERIM_SAMPLE)
	for i in PERIM_SAMPLE:
		var a  := TAU / PERIM_SAMPLE * i - PI * 0.5
		var pt := _alpha_edge(img, _cache_rect, a) if img else Vector2(INF, INF)
		sample[i] = pt if not is_inf(pt.x) else _box_edge(_cache_rect, a)

	# ── Phase 2: cumulative arc lengths around the silhouette ─────────────────────
	var cum := PackedFloat32Array()
	cum.resize(PERIM_SAMPLE + 1)
	cum[0] = 0.0
	for i in PERIM_SAMPLE:
		cum[i + 1] = cum[i] + sample[i].distance_to(sample[(i + 1) % PERIM_SAMPLE])
	var perim: float = cum[PERIM_SAMPLE]

	_ring_size = max(3, int(perim / CURSOR_SLOT))

	# ── Phase 3: place _ring_size points at equal arc-length intervals ────────────
	# This guarantees exactly CURSOR_SLOT px between adjacent cursors regardless
	# of silhouette curvature (no overlap on narrow parts, no excess gap on wide parts).
	_edge_pts.resize(_ring_size)
	var seg := 0
	for i in _ring_size:
		var target := float(i) * CURSOR_SLOT
		while seg < PERIM_SAMPLE - 1 and cum[seg + 1] < target:
			seg += 1
		var t := 0.0
		if cum[seg + 1] > cum[seg]:
			t = (target - cum[seg]) / (cum[seg + 1] - cum[seg])
		_edge_pts[i] = sample[seg].lerp(sample[(seg + 1) % PERIM_SAMPLE], clampf(t, 0.0, 1.0))

# Try GPU data first; fall back to loading raw PNG from disk.
func _load_ctrl_image(ctrl: Control) -> Image:
	var tex_rect := ctrl.get_node_or_null("TextureRect") as TextureRect
	if not is_instance_valid(tex_rect) or not tex_rect.texture:
		return null

	var img := tex_rect.texture.get_image()
	if img:
		img.convert(Image.FORMAT_RGBA8)
		return img

	# CompressedTexture2D may not expose CPU data — load directly from file.
	var eo := ctrl as EditableObjectNode
	if not is_instance_valid(eo) or eo.source_path == "" or eo.is_group_layer():
		return null
	if eo.source_path == _img_cache_path and _img_cache != null:
		return _img_cache
	var disk_img := Image.load_from_file(eo.source_path)
	if disk_img:
		disk_img.convert(Image.FORMAT_RGBA8)
		_img_cache      = disk_img
		_img_cache_path = eo.source_path
	return disk_img

# March outward from sprite center along angle; return the last screen position
# whose corresponding image pixel is opaque (alpha > ALPHA_THRESH).
# Returns Vector2(INF, INF) when no opaque pixel is found — caller falls back to _box_edge.
func _alpha_edge(img: Image, rect: Rect2, angle: float) -> Vector2:
	var center := rect.get_center()
	var dx     := cos(angle)
	var dy     := sin(angle)
	var iw     := img.get_width()
	var ih     := img.get_height()
	var max_t  := rect.size.length() * 0.6

	var last_opaque := Vector2(INF, INF)
	var t := 0.0
	while t <= max_t:
		var wx := center.x + dx * t
		var wy := center.y + dy * t
		var ux := (wx - rect.position.x) / rect.size.x
		var uy := (wy - rect.position.y) / rect.size.y
		if ux < 0.0 or ux >= 1.0 or uy < 0.0 or uy >= 1.0:
			break
		var px := clampi(int(ux * float(iw)), 0, iw - 1)
		var py := clampi(int(uy * float(ih)), 0, ih - 1)
		if img.get_pixel(px, py).a > ALPHA_THRESH:
			last_opaque = Vector2(wx, wy)
		t += 1.0

	return last_opaque

# Fallback: intersection of ray with bounding rectangle.
func _box_edge(rect: Rect2, angle: float) -> Vector2:
	var center := rect.get_center()
	var hw     := rect.size.x * 0.5
	var hh     := rect.size.y * 0.5
	var dx     := cos(angle)
	var dy     := sin(angle)
	var t      := INF
	if absf(dx) > 1e-6:
		var tx := (hw if dx > 0.0 else -hw) / dx
		if tx > 0.0 and absf(dy * tx) <= hh + 1e-5:
			t = minf(t, tx)
	if absf(dy) > 1e-6:
		var ty := (hh if dy > 0.0 else -hh) / dy
		if ty > 0.0 and absf(dx * ty) <= hw + 1e-5:
			t = minf(t, ty)
	if t == INF:
		t = maxf(hw, hh)
	return center + Vector2(dx, dy) * t

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var n := _cursors.size()
	if n == 0:
		return

	if _in_edit_mode():
		for c in _cursors: c.visible = false
		return

	var ctrl := _get_view_ctrl()
	if not is_instance_valid(ctrl):
		for c in _cursors: c.visible = false
		return

	# Rebuild edge cache if sprite moved/resized
	var cur_rect := ctrl.get_global_rect()
	if cur_rect != _cache_rect:
		_rebuild_cache(ctrl)

	if _edge_pts.is_empty():
		return

	_t = fmod(_t + delta / CLICK_PERIOD, 1.0)

	for i in n:
		var c    := _cursors[i]
		c.visible = true

		var ring := i / _ring_size
		var slot := i % _ring_size
		var edge := _edge_pts[slot]

		# Direction and angle derived from actual edge position, not slot index —
		# this is what makes arc-length spacing work correctly.
		var dir := (edge - _cache_rect.get_center()).normalized()
		if dir.is_zero_approx():
			dir = Vector2.DOWN
		var angle := atan2(dir.y, dir.x)

		var phase   := fmod(_t - float(slot) / float(_ring_size) + 1.0, 1.0)
		var click_p := 0.0
		if phase < CLICK_DUR:
			click_p = sin(phase / CLICK_DUR * PI)

		var tip_base   := REST_GAP + float(ring) * RING_GAP
		var tip_offset := lerpf(tip_base, tip_base - CLICK_DEPTH, click_p)
		c.position = edge + dir * (TIP_LEN + tip_offset)
		c.rotation = angle - PI * 0.5

# ── Inner: hand cursor visual ─────────────────────────────────────────────────

class _HandCursor extends Control:
	var tex: Texture2D

	# tex: handcursor.png — index finger tip is at top-center of the image,
	# drawn at 10×10 px so that tip aligns with local (0, -TIP_LEN).
	func _init(t: Texture2D) -> void:
		tex          = t
		custom_minimum_size = Vector2(10.0, 10.0)
		mouse_filter = MOUSE_FILTER_IGNORE
		z_index      = 1

	func _draw() -> void:
		if not tex:
			return
		# Rect: 10×10, centered on x=0, top of image at y=-15 (= -TIP_LEN)
		draw_texture_rect(tex, Rect2(-5.0, -15.0, 10.0, 10.0), false)
