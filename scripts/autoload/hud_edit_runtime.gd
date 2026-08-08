extends Node
## HudEditRuntime — 2026-08-06, on request. A NEW, player-facing, permanent-storage HUD customization
## system: press-and-hold ANY opted-in Control for HOLD_SECONDS (3s) without moving the mouse to enter edit
## mode on it — a bounding-box overlay with 8 drag handles appears (4 corners = proportional rescale, keeping
## the opposite corner anchored; 4 edge midpoints = single-axis stretch, keeping the opposite edge anchored).
## Ctrl+Z reverts the last finished resize; Esc cancels the whole edit session (reverts to how the element
## looked before you started editing it THIS time); Enter confirms and PERSISTS the result to disk
## (user://hud_layout_overrides.cfg), so it survives a restart.
##
## Deliberately SEPARATE from the existing dev-only edit-mode family (hud_edit_mode.gd / boss_edit_mode.gd /
## creep_edit_mode.gd / fleet_edit_mode.gd, toggled by the `toggle_edit_mode` key) — this is a new, parallel,
## always-available PLAYER system, not a dev tool, and doesn't touch any of that code.
##
## Resize is implemented via Control.scale (a pure visual transform), NOT by mutating size/position — almost
## every candidate element lives inside a VBoxContainer/HBoxContainer/GridContainer, which would otherwise
## fight and immediately undo any manual size/position change during its own layout pass every frame. `scale`
## sits on top of the container-computed layout and is untouched by it, so this works no matter what kind of
## parent container an element happens to live in. Trade-off (disclosed, not hidden): a scaled-up element can
## visually overlap its neighbors, since the container still only reserves space for its UNSCALED size —
## accepted as the cost of one universal mechanism vs. bespoke reparenting per widget.
##
## Scope so far (2026-08-06): wired into the Dock screen only — dock_binder.gd's room icons + hub_screen.gd's
## chrome (Back button, coin icon/label, sub-tab buttons) + the Merchant grid cells and preview panel. NOT yet
## the Hub's other tabs (Loadout/Craft/Fragments/Passives) or any other scene — more scenes get wired in as
## they're specifically requested. Per spec, this only ever registers UI Controls, never world-space gameplay
## nodes, so "doesn't work on terrain/map/creep during play" is automatic — nothing in arena_enemy.gd /
## volcanic terrain / etc. calls register().

## Emitted right after a saved (Enter-confirmed) edit — `control` is the final state (already applied).
## dock_binder.gd listens for this to derive a room-independent OFFSET for the shared hover-bar, whose
## "natural" position varies per room and so can't just be overwritten with the raw absolute saved position
## the way every other (fixed-position) registered element can — see dock_binder.gd's _on_hud_edit_confirmed.
signal edit_confirmed(id: String, control: Control)

const SAVE_PATH := "user://hud_layout_overrides.cfg"
const HOLD_SECONDS := 3.0
const MOVE_CANCEL_PX := 6.0     # mouse drift beyond this during the hold cancels it (avoids false triggers)
const HANDLE_SIZE := 10.0       # on-screen handle grip size, px
const HANDLE_GRAB_MULT := 1.6   # handle click-tolerance = HANDLE_SIZE * this
const BOX_COLOR := Color(0.3, 0.9, 1.0, 0.9)
const HANDLE_COLOR := Color(1.0, 0.95, 0.3, 0.95)
const MIN_SCALE := 0.25
const MAX_SCALE := 4.0

enum Handle { TL, T, TR, R, BR, B, BL, L }

var _overrides: Dictionary = {}       # id -> {"scale":Vector2, "pivot":Vector2, "top_level":bool, "position":Vector2}
var _registered: Dictionary = {}      # id -> Control

# Hold-to-enter tracking (only relevant while nothing is being edited yet).
var _hold_id: String = ""
var _hold_control: Control = null
var _hold_t: float = 0.0
var _hold_start_mouse: Vector2 = Vector2.ZERO
var _mouse_down: bool = false

# Active edit session.
var _edit_id: String = ""
var _edit_control: Control = null
var _edit_entry_scale: Vector2 = Vector2.ONE     # state when THIS session began (Esc target)
var _edit_entry_pivot: Vector2 = Vector2.ZERO
var _edit_entry_position: Vector2 = Vector2.ZERO
var _edit_entry_top_level: bool = false

var _drag_handle: int = -1
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_scale: Vector2 = Vector2.ONE

# Body-drag (move, as opposed to a handle-drag resize) — 2026-08-06, on request ("chưa drag được item đi").
# Moving a Control that's normally laid out by a parent Container needs the SAME escape hatch as scale does
# for size: `top_level = true` makes its `position` relative to the nearest CanvasLayer instead of its
# parent's layout, so the container can no longer fight it every sort pass (mirrors why resize uses `scale`
# instead of `size` — see the file-level doc comment). Converted to top_level exactly once, the first time an
# element is ever moved; re-applied automatically by register() on every future rebuild once saved.
var _moving: bool = false
var _move_start_mouse: Vector2 = Vector2.ZERO
var _move_start_position: Vector2 = Vector2.ZERO

# Arrow-key nudge (2026-08-06, on request) — alternative to mouse-drag for moving the edited element.
const NUDGE_SPEED := 120.0   # px/sec while a direction is held
var _nudging: bool = false

var _undo_scale: Vector2 = Vector2.ONE           # state before the MOST RECENT finished drag (Ctrl+Z target)
var _undo_pivot: Vector2 = Vector2.ZERO
var _undo_position: Vector2 = Vector2.ZERO
var _undo_top_level: bool = false
var _has_undo: bool = false

var _edit_control_was_disabled: bool = false   # BaseButton-only — see _enter_edit/_exit_edit

var _overlay: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_overrides()
	_build_overlay()

func _build_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 200   # above absolutely everything else in the game
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE   # STOP only while actively editing — see _enter_edit
	_overlay.visible = false
	_overlay.draw.connect(_draw_overlay)
	cl.add_child(_overlay)

## Public: opt a Control into the hold-to-edit system. `id` must be STABLE and UNIQUE across the whole game
## (e.g. "dock.merchant.cell.gatling_gun.name") — it's both the undo/save key and how a saved override gets
## re-applied the next time this same logical element is (re)built. Dynamic UIs like the Merchant grid rebuild
## their Controls from scratch on every refresh; calling register() again with the same id on the NEW
## instance is exactly how it picks the saved look back up.
func register(control: Control, id: String) -> void:
	if control == null or not is_instance_valid(control):
		return
	_registered[id] = control
	if _overrides.has(id):
		var o: Dictionary = _overrides[id]
		control.pivot_offset = o.get("pivot", Vector2.ZERO)
		control.scale = o.get("scale", Vector2.ONE)
		if bool(o.get("top_level", false)):
			control.top_level = true
			control.position = o.get("position", control.position)
	control.tree_exiting.connect(func() -> void:
		if _registered.get(id) == control:
			_registered.erase(id)
		if _edit_control == control:
			_exit_edit(false)   # the thing being edited just got freed (e.g. a tab switch) — bail out quietly
	, CONNECT_ONE_SHOT)

## Public: the persisted BASE scale for `id` (Vector2.ONE if it has never been resized). For callers that
## ALSO drive their own transient scale effects on the same Control — e.g. dock_binder.gd's hover-zoom —
## reading this and multiplying on top of it (instead of overwriting `.scale` outright) is how the two
## systems cooperate instead of fighting over the same property every frame.
func get_base_scale(id: String) -> Vector2:
	return _overrides.get(id, {}).get("scale", Vector2.ONE)

## Public: true while `control` is the one currently being hold-to-edited. Callers with their own hover/press
## effects on a registered Control should skip touching it (transform AND click actions) while this is true —
## see dock_binder.gd's _wire_hover for the pattern.
func is_editing(control: Control) -> bool:
	return _edit_control == control

## Public: true while ANY edit session is active (not just for one specific control). 2026-08-06, on request:
## callers with hover-driven side effects shared across several sibling elements — e.g. dock_binder.gd's
## hover-bar, which every room's hover re-positions/re-sizes — should freeze ALL of those side effects while
## editing is happening ANYWHERE, not just guard the one element currently being edited. Otherwise hovering a
## DIFFERENT room mid-edit still re-triggers _show_bar() and stomps whatever the player is mid-drag on.
func is_active() -> bool:
	return _edit_control != null

func _process(delta: float) -> void:
	if _overlay == null:
		return
	var mouse := _overlay.get_global_mouse_position()
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if _edit_control != null and not is_instance_valid(_edit_control):
		_exit_edit(false)
		return

	if _edit_control != null:
		_process_editing(mouse, down, delta)
		return

	# Not editing anything yet — watch for a hold-to-enter on whatever's under the mouse. When several
	# registered elements overlap at this point (e.g. a room's hover-bar background + its text label both
	# sit on top of the room's own icon — 2026-08-06, on request: "giữ vào overlay pop up thì sửa pop-up,
	# giữ vào text ... thì sửa text, giữ vào ảnh preview thì sửa ảnh"), pick the SMALLEST-area match — the
	# most specific/topmost element under the cursor, standard nested-hit-test behavior — instead of
	# whichever happened to be registered last (arbitrary Dictionary iteration order).
	if down and not _mouse_down:
		_hold_id = ""
		_hold_control = null
		var best_area := INF
		for id: String in _registered:
			var c: Control = _registered[id]
			if not is_instance_valid(c) or not c.is_visible_in_tree():
				continue
			var r := _control_rect_global(c)
			if not r.has_point(mouse):
				continue
			var area: float = r.size.x * r.size.y
			if area < best_area:
				best_area = area
				_hold_id = id
				_hold_control = c
		_hold_t = 0.0
		_hold_start_mouse = mouse
	elif down and _hold_control != null:
		if mouse.distance_to(_hold_start_mouse) > MOVE_CANCEL_PX:
			_hold_control = null   # moved too much mid-press (a click/drag/scroll gesture) — not a hold
		else:
			_hold_t += delta
			if _hold_t >= HOLD_SECONDS:
				_enter_edit(_hold_control, _hold_id)
				_hold_control = null
	elif not down:
		_hold_control = null
		_hold_t = 0.0
	_mouse_down = down

## Global-space AABB of `c`'s local rect, correctly accounting for any scale/rotation/pivot already applied
## (Control.get_global_rect() does NOT include `scale`, only position+size — this does).
func _control_rect_global(c: Control) -> Rect2:
	var xform := c.get_global_transform_with_canvas()
	var p0 := xform * Vector2.ZERO
	var p1 := xform * Vector2(c.size.x, 0)
	var p2 := xform * c.size
	var p3 := xform * Vector2(0, c.size.y)
	var minv := p0.min(p1).min(p2).min(p3)
	var maxv := p0.max(p1).max(p2).max(p3)
	return Rect2(minv, maxv - minv)

func _enter_edit(control: Control, id: String) -> void:
	_edit_control = control
	_edit_id = id
	_edit_entry_scale = control.scale
	_edit_entry_pivot = control.pivot_offset
	_edit_entry_position = control.position
	_edit_entry_top_level = control.top_level
	_moving = false
	_drag_handle = -1
	_has_undo = false
	# Blocking the overlay's OWN input (mouse_filter STOP below) is not enough on its own: a Button already
	# armed itself on the original mouse-DOWN that started the 3s hold, and Godot fires `pressed` on release
	# regardless of what's drawn on top — so on release. Bug report: holding "MAIN MENU" for 3s still fired
	# the button's action the instant you let go. Fix (matches the reported request): explicitly disable the
	# BaseButton for the duration of the edit session so it can't process/deliver that release at all;
	# restored in _exit_edit.
	_edit_control_was_disabled = false
	if control is BaseButton:
		_edit_control_was_disabled = (control as BaseButton).disabled
		(control as BaseButton).disabled = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP   # block the game underneath while actively editing
	_overlay.visible = true
	_overlay.queue_redraw()

func _process_editing(mouse: Vector2, down: bool, delta: float) -> void:
	if not is_instance_valid(_edit_control):
		_exit_edit(false)
		return
	if _drag_handle == -1 and not _moving:
		_process_nudge(delta)   # arrow keys — only while not already mid mouse-drag/move
		if down and not _mouse_down:
			var h := _handle_at(mouse)
			if h != -1:
				_drag_handle = h
				_drag_start_mouse = mouse
				_drag_start_scale = _edit_control.scale
				_snapshot_undo()
			elif _control_rect_global(_edit_control).has_point(mouse):
				_start_move(mouse)
	elif _drag_handle != -1:
		if down:
			_apply_drag(mouse)
		else:
			_drag_handle = -1
			_has_undo = true
	else:   # _moving
		if down:
			_edit_control.position = _move_start_position + (mouse - _move_start_mouse)
		else:
			_moving = false
			_has_undo = true
	_overlay.queue_redraw()
	_mouse_down = down

## Arrow-key movement — 2026-08-06, on request ("Gán các phím mũi tên để di chuyển ảnh theo các hướng").
## Continuous (polled every frame, not per key-event) so holding a direction nudges smoothly, matching how
## mouse-drag already feels, rather than relying on the OS's own key-repeat timing/rate.
func _process_nudge(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):  dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT): dir.x += 1.0
	if Input.is_key_pressed(KEY_UP):    dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):  dir.y += 1.0
	if dir == Vector2.ZERO:
		if _nudging:
			_nudging = false
			_has_undo = true
		return
	if not _nudging:
		_snapshot_undo()
		_ensure_top_level()
		_nudging = true
	_edit_control.position += dir.normalized() * NUDGE_SPEED * delta

## Shared by _start_move and _process_nudge: the first time an element is ever repositioned (by either mouse
## or arrow keys), escape the parent Container's layout control the same way resize escapes it via `scale` —
## see the `_moving` field's doc comment. Computes the equivalent global position FIRST so flipping
## `top_level` on doesn't cause a visible jump.
func _ensure_top_level() -> void:
	if not _edit_control.top_level:
		var gpos := _edit_control.get_global_transform_with_canvas().origin
		_edit_control.top_level = true
		_edit_control.position = gpos

func _snapshot_undo() -> void:
	_undo_scale = _edit_control.scale
	_undo_pivot = _edit_control.pivot_offset
	_undo_position = _edit_control.position
	_undo_top_level = _edit_control.top_level

## Body-drag: reparent-free "detach from container layout" the first time an element is ever moved (see the
## _moving field's doc comment above), then track the drag 1:1 in the now-canvas-relative `position`.
func _start_move(mouse: Vector2) -> void:
	_snapshot_undo()
	_ensure_top_level()
	_moving = true
	_move_start_mouse = mouse
	_move_start_position = _edit_control.position

func _handle_at(mouse: Vector2) -> int:
	if _edit_control == null:
		return -1
	var pts := _handle_points()
	for i in pts.size():
		if mouse.distance_to(pts[i]) <= HANDLE_SIZE * HANDLE_GRAB_MULT:
			return i
	return -1

## The 8 handle positions in GLOBAL space, matching the Handle enum order (TL, T, TR, R, BR, B, BL, L).
func _handle_points() -> Array:
	var r := _control_rect_global(_edit_control)
	return [
		r.position,
		r.position + Vector2(r.size.x * 0.5, 0),
		r.position + Vector2(r.size.x, 0),
		r.position + Vector2(r.size.x, r.size.y * 0.5),
		r.position + r.size,
		r.position + Vector2(r.size.x * 0.5, r.size.y),
		r.position + Vector2(0, r.size.y),
		r.position + Vector2(0, r.size.y * 0.5),
	]

## Corner handles (TL/TR/BR/BL) scale BOTH axes together, uniformly, keeping the OPPOSITE corner fixed as the
## anchor (pivot_offset). Edge-midpoint handles (T/R/B/L) scale only the perpendicular axis, keeping the
## opposite edge fixed. The mouse delta is converted into the control's own LOCAL (unscaled) space first, so
## the drag distance reads correctly no matter what ancestor transforms are already in effect.
func _apply_drag(mouse: Vector2) -> void:
	var c := _edit_control
	var base_size: Vector2 = c.size if c.size.x > 0.0 and c.size.y > 0.0 else Vector2(1, 1)
	var delta := mouse - _drag_start_mouse
	var xform := c.get_global_transform_with_canvas()
	var local_delta: Vector2 = xform.affine_inverse().basis_xform(delta)
	var lo := Vector2(MIN_SCALE, MIN_SCALE)
	var hi := Vector2(MAX_SCALE, MAX_SCALE)

	match _drag_handle:
		Handle.BR:
			c.pivot_offset = Vector2.ZERO
			var f: float = 1.0 + maxf(local_delta.x / base_size.x, local_delta.y / base_size.y)
			c.scale = (_drag_start_scale * f).clamp(lo, hi)
		Handle.TL:
			c.pivot_offset = c.size
			var f2: float = 1.0 - minf(local_delta.x / base_size.x, local_delta.y / base_size.y)
			c.scale = (_drag_start_scale * f2).clamp(lo, hi)
		Handle.TR:
			c.pivot_offset = Vector2(0, c.size.y)
			var f3: float = 1.0 + maxf(local_delta.x / base_size.x, -local_delta.y / base_size.y)
			c.scale = (_drag_start_scale * f3).clamp(lo, hi)
		Handle.BL:
			c.pivot_offset = Vector2(c.size.x, 0)
			var f4: float = 1.0 + maxf(-local_delta.x / base_size.x, local_delta.y / base_size.y)
			c.scale = (_drag_start_scale * f4).clamp(lo, hi)
		Handle.R:
			c.pivot_offset = Vector2(0, c.size.y * 0.5)
			var fx: float = 1.0 + local_delta.x / base_size.x
			c.scale = Vector2(clampf(_drag_start_scale.x * fx, MIN_SCALE, MAX_SCALE), c.scale.y)
		Handle.L:
			c.pivot_offset = Vector2(c.size.x, c.size.y * 0.5)
			var fx2: float = 1.0 - local_delta.x / base_size.x
			c.scale = Vector2(clampf(_drag_start_scale.x * fx2, MIN_SCALE, MAX_SCALE), c.scale.y)
		Handle.B:
			c.pivot_offset = Vector2(c.size.x * 0.5, 0)
			var fy: float = 1.0 + local_delta.y / base_size.y
			c.scale = Vector2(c.scale.x, clampf(_drag_start_scale.y * fy, MIN_SCALE, MAX_SCALE))
		Handle.T:
			c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
			var fy2: float = 1.0 - local_delta.y / base_size.y
			c.scale = Vector2(c.scale.x, clampf(_drag_start_scale.y * fy2, MIN_SCALE, MAX_SCALE))

func _draw_overlay() -> void:
	if _edit_control == null or not is_instance_valid(_edit_control):
		return
	var r := _control_rect_global(_edit_control)
	_overlay.draw_rect(r, BOX_COLOR, false, 2.0)
	for p: Vector2 in _handle_points():
		_overlay.draw_rect(Rect2(p - Vector2(HANDLE_SIZE, HANDLE_SIZE) * 0.5, Vector2(HANDLE_SIZE, HANDLE_SIZE)), HANDLE_COLOR, true)

const _NUDGE_KEYS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

func _unhandled_input(event: InputEvent) -> void:
	if _edit_control == null:
		return
	if event is InputEventKey and (event.keycode in _NUDGE_KEYS):
		# Consume every arrow-key event (press/release/OS auto-repeat) while editing so it never reaches
		# gameplay underneath (e.g. ship movement) — the actual nudge itself is driven by _process_nudge()
		# polling Input.is_key_pressed() every frame, not by these events.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_exit_edit(false)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_exit_edit(true)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z and event.ctrl_pressed:
			if _has_undo and is_instance_valid(_edit_control):
				_edit_control.scale = _undo_scale
				_edit_control.pivot_offset = _undo_pivot
				_edit_control.top_level = _undo_top_level
				_edit_control.position = _undo_position
				_has_undo = false
				_overlay.queue_redraw()
			get_viewport().set_input_as_handled()

func _exit_edit(save: bool) -> void:
	if _edit_control != null and is_instance_valid(_edit_control):
		if save:
			_overrides[_edit_id] = {
				"scale": _edit_control.scale, "pivot": _edit_control.pivot_offset,
				"top_level": _edit_control.top_level, "position": _edit_control.position,
			}
			_save_overrides()
			edit_confirmed.emit(_edit_id, _edit_control)
		else:
			_edit_control.scale = _edit_entry_scale
			_edit_control.pivot_offset = _edit_entry_pivot
			_edit_control.top_level = _edit_entry_top_level
			_edit_control.position = _edit_entry_position
		if _edit_control is BaseButton:
			(_edit_control as BaseButton).disabled = _edit_control_was_disabled
	_edit_control = null
	_edit_id = ""
	_drag_handle = -1
	_moving = false
	_has_undo = false
	if _overlay != null:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.visible = false

const _OVERRIDE_FIELDS := ["scale", "pivot", "top_level", "position"]   # dict keys <-> ".field" cfg suffixes

func _load_overrides() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("hud_edit"):
		return
	for key: String in cfg.get_section_keys("hud_edit"):
		for field: String in _OVERRIDE_FIELDS:
			var suffix := "." + field
			if key.ends_with(suffix):
				var base_id := key.substr(0, key.length() - suffix.length())
				if not _overrides.has(base_id):
					_overrides[base_id] = {}
				_overrides[base_id][field] = cfg.get_value("hud_edit", key)
				break

func _save_overrides() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # preserve the file if it somehow ever gains other sections
	var defaults := {"scale": Vector2.ONE, "pivot": Vector2.ZERO, "top_level": false, "position": Vector2.ZERO}
	for id: String in _overrides:
		var o: Dictionary = _overrides[id]
		for field: String in _OVERRIDE_FIELDS:
			cfg.set_value("hud_edit", id + "." + field, o.get(field, defaults[field]))
	cfg.save(SAVE_PATH)
