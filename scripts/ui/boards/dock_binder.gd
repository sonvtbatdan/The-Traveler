extends BoardBinder
class_name DockBinder
## RUNTIME for the "Dock" board — the between-run home screen, hosted by hub_screen.gd (see arena.gd's
## "RETURN TO DOCK" button → res://scenes/hub.tscn). hub_screen.gd listens to room_clicked below and
## decides what each room does; this binder only owns hover/click FEEDBACK, not game destinations.
##
## Room → destination (per design, 2026-07-26/27):
##   Equipment   → Loadout (hub_screen.gd's existing tab, reused as-is)
##   Merchant    → Shop (existing tab, reused as-is; room renamed from "Mechanic" 2026-08-05 — see
##                 ROOM_NAME_OVERRIDE below, the underlying asset/group is still named "mechanic")
##   Engineer    → Craft + Fragments, as 2 sub-tabs of one panel (Passives moved OUT to Constructor, below —
##                 2026-08-06, on request)
##   Launch      → still directly launches a run (hub_screen.gd's old LAUNCH RUN button) — no map-select
##                 system exists to gate it on yet, so it can't be a "Coming Soon" like the rest
##   Constructor → "Construction" panel (2026-08-06, on request): Pilot Room's 2-stage coin purchase, the
##                 Trading Hub (shown only once the Mechanic is rescued — flavor framing over the existing
##                 Dock-interest system, not a separate mechanic), then Passives (moved here from Engineer)
##   Codex       → Lore/item codex — not built, "Coming Soon"
##   Trophy      → Achievements board — not built, "Coming Soon"
##   Bridge      → Quest board — not built, "Coming Soon"
##   Instructor  → How-to-play / tutorial guide (proposed 2026-07-27, unconfirmed) — not built, "Coming Soon"
##   Pilot       → Pilot-select board (both Pilot + Pilot2 plaques) — not built, "Coming Soon"
##   Beacon      → Beacon board — not built, "Coming Soon"
##
## Layout (author-positioned 2026-07-27): Background + Frame fill the screen; the 9 room renders sit as
## small windows over the cutaway-ship background, each in its own group, all visible at once; Launch is
## a press-pair (launch.png ⇄ "launch hover.png"); Pilot/Pilot2 are two plaque instances of the same art.
##
## Hover (2026-07-27, bar redesign 2026-07-27): every function image — the 9 rooms + Pilot/Pilot2 — grows
## 5%, plays the same hover SFX as the Level Up board's weapon/aux cards (uiclick.wav, see
## arena_levelup_ui.gd's _board_make_choice), and a translucent white (40% alpha) name-bar slides up over
## its bottom edge with its capitalized name centered inside (_show_bar/_hide_bar — one shared bar,
## repositioned per hover). The bar's z (BAR_Z=239) sits BELOW Frame (240) on purpose — Frame's window
## grid partially covers/clips the top of the bar instead of the bar floating above it. Launch instead
## swaps to its own dedicated "launch hover" art (same idiom as hud_binder.gd's _setup_hover_pair) since
## the artist already drew a lit-up state for it, but still plays the SFX + shows the "Launch" name-bar.

## Emitted when a function image is clicked — `room_name` is the capitalized name shown on hover
## ("Equipment", "Launch", "Pilot" for both Pilot/Pilot2…). The host (e.g. hub_screen.gd) decides what
## each name actually does; this binder only knows about hover/click feedback, not game destinations.
signal room_clicked(room_name: String)

const SFX_HOVER := preload("res://assets/audio/sfx/uiclick.wav")
const FONT_BODY := "res://assets/fonts/mandalore/mandalore.ttf"
const HOVER_SCALE := 1.05
const NO_HOVER_GROUPS := ["Background", "Frame"]   # backdrop layers, not a "function"
const BAR_H := 36.0                                 # hover name-bar height
const BAR_COLOR := Color(1.0, 1.0, 1.0, 0.40)        # translucent white
const BAR_SLIDE_TIME := 0.16
const BAR_Z := 239   # above every room/pilot item (max 237) but BELOW Frame (240) — Frame's window grid
                      # is meant to partially cover/clip the top of the bar, not sit behind it
const BAR_LIFT_PILOT := 5.0    # Launch + Pilot/Pilot2: nudge the docked bar up 5px
const BAR_LIFT_ROOM  := 15.0   # the 9 rooms: nudge the docked bar up 15px

# Room display-name override, keyed by the room's own asset `file` name (label_text normally = file.capitalize()
# — see _wire_hover below). 2026-08-05, on request: "Mechanic" room renamed to "Merchant" for the PLAYER-FACING
# hover-bar/panel label only — the underlying asset stays assets/hud/dock/mechanic.png (and config/boards/
# dock.cfg's group is still literally named "Mechanic") on purpose, same "keep internal id, override display
# only" precedent as MetaManager.MAP_DEFS's rubicon/default → Electric/Space rename (see its own doc comment).
const ROOM_NAME_OVERRIDE := {"mechanic": "Merchant"}

# ── Hover-bar move OFFSET (2026-08-06, on request) ──────────────────────────────────────────────────────
# _hover_bar is ONE shared Control reused for every room, repositioned fresh by _show_bar() on every single
# hover — so it can't just take HudEditRuntime's raw absolute saved position the way a fixed-position element
# (an icon, a button) can: that absolute spot was only ever correct for whichever room happened to be hovered
# at the moment it was saved. Instead, HudEditRuntime.edit_confirmed tells us the ABSOLUTE final position, we
# subtract the "natural" (un-moved) position that was in effect for that same moment (_bar_natural_pos, kept
# fresh by every _show_bar() call — hover is frozen while editing, so it's still accurate when the signal
# fires), and persist the resulting DELTA — which then applies consistently on top of whatever room is
# hovered next, forever, room-independent.
const BAR_OFFSET_SAVE_PATH := "user://hud_layout_overrides.cfg"   # same file HudEditRuntime itself uses
var _bar_offset: Vector2 = Vector2.ZERO
var _bar_natural_pos: Vector2 = Vector2.ZERO   # container-local space; refreshed on every _show_bar() call
var _bar_icon_bottom: float = 0.0              # container-local; the hovered room's own bottom edge, for
                                                # _hide_bar()'s containment clamp (see _show_bar()'s doc comment)

var _click_player: AudioStreamPlayer = null
var _hover_bar: Control = null
var _hover_bar_label: Label = null
var _hover_tween: Tween = null
var _runtime_extras: Array = []

# ── Room locks (2026-08-06, on request) ─────────────────────────────────────────────────────────────
# Every room that placed a "<file> lock" item in dock.cfg (see MetaManager.ROOM_UNLOCK_DEFS for the full
# id list + unlock conditions) gets an entry here: {"room_id": String, "node": Control, "main_node":
# Control} — `node` is the lock art, `main_node` the room's own art; the two are shown EXCLUSIVELY (never
# both at once — locked shows only the lock file, unlocked shows only the room file), kept in sync by
# _on_meta_changed() whenever MetaManager.is_room_unlocked() flips. While locked, _wire_hover's hover/click
# handlers also early-return (no scale/SFX/name-bar/room_clicked at all — a locked room does nothing to the
# mouse, per design). `room_id` = the group's own name lowercased ("Beacon"→"beacon", "Pilot2"→"pilot2"),
# which is exactly MetaManager.ROOM_UNLOCK_DEFS's key space — the group name IS the room id, no separate
# mapping table to keep in sync.
var _locks: Array = []

func build() -> void:
	clear()
	if _ed == null:
		return
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = SFX_HOVER
	_click_player.bus = "SFX"
	_ed.add_child(_click_player)
	_runtime_extras.append(_click_player)
	_load_bar_offset()
	_locks.clear()
	if not HudEditRuntime.edit_confirmed.is_connected(_on_hud_edit_confirmed):
		HudEditRuntime.edit_confirmed.connect(_on_hud_edit_confirmed)
	if not MetaManager.meta_changed.is_connected(_on_meta_changed):
		MetaManager.meta_changed.connect(_on_meta_changed)

	# Shared hover name-bar: a translucent white strip that slides up over the bottom edge of whichever
	# function image is hovered, with its name centered inside (replaces the old floating yellow label).
	_hover_bar = Control.new()
	_hover_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_bar.z_index = BAR_Z
	_hover_bar.z_as_relative = false   # ignore container()'s own z_index too — z is exactly BAR_Z, no surprises
	_hover_bar.visible = false
	container().add_child(_hover_bar)
	_runtime_extras.append(_hover_bar)

	var bg := ColorRect.new()
	bg.color = BAR_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_bar.add_child(bg)

	_hover_bar_label = Label.new()
	var font := load(FONT_BODY) as Font
	if font != null:
		_hover_bar_label.add_theme_font_override("font", font)
	_hover_bar_label.add_theme_font_size_override("font_size", 24)
	_hover_bar_label.add_theme_color_override("font_color", Color(0.08, 0.09, 0.13))
	_hover_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hover_bar_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hover_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_bar.add_child(_hover_bar_label)

	# 2026-08-06, on request — 3 distinct hold-to-edit targets instead of the hover-bar area only ever
	# resizing the room's own icon (HudEditRuntime's smallest-area-wins hit-test now picks whichever of these
	# actually sits under the cursor): "giữ vào overlay pop up thì sửa pop-up" → _hover_bar itself; "giữ vào
	# text ... thì sửa text" → _hover_bar_label; "giữ vào ảnh preview thì sửa ảnh" → each room's own icon
	# (registered separately in _wire_hover/_wire_launch below). RESIZE (scale) is safe to persist here since
	# nothing else ever touches `_hover_bar`'s `.scale`. MOVE has a caveat, disclosed rather than hidden:
	# `_show_bar()` unconditionally re-sets `.size`/tweens `.position` on every single hover, so a saved MOVE
	# override on the bar itself won't stay put across hover cycles the way a moved icon does — resizing it is
	# solid, relocating it is not yet.
	HudEditRuntime.register(_hover_bar, "dock.hover_bar")
	HudEditRuntime.register(_hover_bar_label, "dock.hover_bar.label")

	for g: Dictionary in (_ed._groups as Array):
		var gname := String(g.get("name", ""))
		if gname in NO_HOVER_GROUPS:
			continue
		if gname == "Launch":
			_wire_launch(g)
			continue
		# A room group holds its own icon item PLUS, if it's lockable, a second item whose file ends in
		# " lock" (e.g. "beacon" + "beacon lock") — split them out instead of wiring both as hoverable.
		var main_node: Control = null
		var main_file := ""
		var lock_node: Control = null
		for ch: Dictionary in (g.get("children", []) as Array):
			if String(ch.get("type", "")) != "item":
				continue
			var n = _ed._nodes.get(int(ch.get("id", -1)))
			if n == null or not is_instance_valid(n):
				continue
			var file := String(ch.get("file", ""))
			if file.ends_with(" lock"):
				lock_node = n as Control
			else:
				main_node = n as Control
				main_file = file
		if main_node != null:
			_wire_hover(main_node, main_file, gname.to_lower(), lock_node)

## Grow 5% + hover SFX + name label above it; click emits room_clicked(name) — the host decides what to
## do with it (real destinations still get wired one at a time; everything else is a "Coming Soon" toast).
##
## 2026-08-06, on request: `node` is now also HudEditRuntime-registered ("dock.room.<file>") so it can be
## hold-to-edit resized/moved like everything else on the Dock. That system ALSO drives `node.scale` (for the
## persisted resize) and `node.pivot_offset` — both properties this function's own hover-zoom already used —
## so instead of the hover effect overwriting `.scale` outright (which would fight/flicker against a saved
## resize), it now multiplies HOVER_SCALE on top of HudEditRuntime's persisted BASE scale.
##
## Follow-up (same day, on request): hover is now frozen COMPLETELY — not just "don't touch the element being
## edited" but "no hover effect for ANY room at all" — for as long as ANY edit session is active anywhere
## (`HudEditRuntime.is_active()`, not the narrower per-control `is_editing()`). This is what makes moving the
## shared `_hover_bar`/`_hover_bar_label` stable: previously, hovering a DIFFERENT room mid-edit would still
## call `_show_bar()` and stomp the very bar being repositioned. Also still guards the click handler for the
## same reason as before: without it, releasing the mouse after a hold-to-edit resize would immediately fire
## room_clicked and navigate away (the same class of bug already fixed for the Hub's own Buttons via
## HudEditRuntime._enter_edit's BaseButton-disable, which doesn't reach `btn` here since it's a SEPARATE
## invisible click-catcher from `node`, the thing actually being edited).
## `room_id` = the group's own name lowercased (see _locks' doc comment above); `lock_node` is that
## room's "<file> lock" overlay Control if dock.cfg placed one in the same group, else null (a room with
## no lock overlay — Bridge, Launch's own `node` here — is always treated as unlocked, no gating at all).
func _wire_hover(node: Control, file: String, room_id: String, lock_node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	var reg_id := "dock.room." + file
	HudEditRuntime.register(node, reg_id)
	if lock_node != null:
		lock_node.pivot_offset = lock_node.size * 0.5
		lock_node.mouse_filter = Control.MOUSE_FILTER_IGNORE   # decorative only — the room's own btn below catches input
		# Exclusive toggle (2026-08-06, on request): the lock file and the room's own file are never both on
		# screen at once — locked shows ONLY the lock art, unlocked shows ONLY the room art, not lock-over-art.
		var unlocked := MetaManager.is_room_unlocked(room_id)
		lock_node.visible = not unlocked
		node.visible = unlocked
		_locks.append({"room_id": room_id, "node": lock_node, "main_node": node})
	var label_text := String(ROOM_NAME_OVERRIDE.get(file, file.capitalize()))
	var lift := BAR_LIFT_PILOT if file == "pilot" else BAR_LIFT_ROOM
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.position = node.position
	btn.size = node.size
	btn.z_index = node.z_index + 1
	btn.mouse_entered.connect(func() -> void:
		if HudEditRuntime.is_active():
			return
		if lock_node != null and not MetaManager.is_room_unlocked(room_id):
			return   # locked: no hover effect at all, per design
		node.scale = HudEditRuntime.get_base_scale(reg_id) * HOVER_SCALE
		if _click_player != null:
			_click_player.play()
		_show_bar(label_text, node, lift))
	btn.mouse_exited.connect(func() -> void:
		if HudEditRuntime.is_active():
			return
		if lock_node != null and not MetaManager.is_room_unlocked(room_id):
			return
		node.scale = HudEditRuntime.get_base_scale(reg_id)
		_hide_bar())
	btn.pressed.connect(func() -> void:
		if HudEditRuntime.is_active():
			return
		if lock_node != null and not MetaManager.is_room_unlocked(room_id):
			return   # locked: click does nothing
		room_clicked.emit(label_text))
	container().add_child(btn)
	_runtime_extras.append(btn)

## MetaManager.meta_changed listener — refreshes every locked room's lock/art visibility (covers unlocks
## that happen while the Dock is already on-screen, e.g. buying a weapon unlocks Equipment mid-visit).
## Keeps the same exclusive toggle as _wire_hover's initial setup — never both visible at once.
func _on_meta_changed() -> void:
	for entry: Dictionary in _locks:
		var room_id := String(entry.get("room_id", ""))
		var unlocked := MetaManager.is_room_unlocked(room_id)
		var lock_n: Control = entry.get("node")
		if lock_n != null and is_instance_valid(lock_n):
			lock_n.visible = not unlocked
		var main_n: Control = entry.get("main_node")
		if main_n != null and is_instance_valid(main_n):
			main_n.visible = unlocked

## Launch: swap to the dedicated "launch hover" art (drawn by the artist for exactly this) instead of a
## generic scale, matching hud_binder.gd's _setup_hover_pair idiom — still gets the shared SFX + label.
## No scale-conflict with HudEditRuntime here (this uses a visibility swap, not `.scale`), but `normal` is
## still registered so Launch is hold-to-edit resizable/movable like every other room. Hover/click are frozen
## via is_active() (not the narrower is_editing()) the same way _wire_hover's are — see that function's doc
## comment for why "any edit session active anywhere" is the right freeze condition, not just "this element".
func _wire_launch(g: Dictionary) -> void:
	var normal: Control = null
	var hover: Control = null
	for ch: Dictionary in (g.get("children", []) as Array):
		if String(ch.get("type", "")) != "item":
			continue
		var n = _ed._nodes.get(int(ch.get("id", -1)))
		if n == null or not is_instance_valid(n):
			continue
		match String(ch.get("file", "")):
			"launch": normal = n as Control
			"launch hover": hover = n as Control
	if normal == null:
		return
	normal.visible = true
	if hover != null:
		hover.visible = false
	HudEditRuntime.register(normal, "dock.room.launch")
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.position = normal.position
	btn.size = normal.size
	btn.z_index = normal.z_index + 2
	btn.mouse_entered.connect(func() -> void:
		if HudEditRuntime.is_active():
			return
		normal.visible = false
		if hover != null:
			hover.visible = true
		if _click_player != null:
			_click_player.play()
		_show_bar("Launch", normal, BAR_LIFT_PILOT))
	btn.mouse_exited.connect(func() -> void:
		if HudEditRuntime.is_active():
			return
		normal.visible = true
		if hover != null:
			hover.visible = false
		_hide_bar())
	btn.pressed.connect(func() -> void:
		if not HudEditRuntime.is_active():
			room_clicked.emit("Launch"))
	container().add_child(btn)
	_runtime_extras.append(btn)

## Slide the name-bar up from just below `over`'s bottom edge until it docks `lift` px above that edge
## (Launch/Pilot/Pilot2 use a smaller lift than the 9 rooms — see BAR_LIFT_PILOT/BAR_LIFT_ROOM).
##
## 2026-08-06, on request: if the player has ever hold-to-edit MOVED the bar (HudEditRuntime flipped it to
## `top_level`), `docked_pos` — computed in `over`'s (container-local) space — must first be converted into
## the SAME canvas/global space `_hover_bar.position` now lives in, then `_bar_offset` (the player's saved
## delta from wherever they dragged it, room-independent — see the field's doc comment above) is added on
## top. Before any move, `_hover_bar.top_level` is still false and `_bar_offset` is still zero, so this is a
## no-op and behaves exactly as it always did.
##
## Bug fix, same day: the slide-UP animation's START position (BAR_H below the docked target, "off the bottom
## edge") overshot `over`'s own bottom edge by BAR_H−lift px (21px for the 9 regular rooms, 31px for Launch/
## Pilot) — with rooms packed close together on the board, that overshoot visibly bled into whichever room
## sits below (reported worst on Launch/Bridge/Beacon). Clamped so the bar's bottom edge never starts past
## `over`'s own bottom edge, and its top edge never rises past `over`'s own top edge — the whole rise-up
## animation now stays fully inside the hovered room's own icon bounds, not just the resting position.
func _show_bar(text: String, over: Control, lift: float) -> void:
	if _hover_bar == null:
		return
	_hover_bar_label.text = MandaloreText.a(text)
	_hover_bar.size = Vector2(over.size.x, BAR_H)
	container().move_child(_hover_bar, -1)   # belt-and-suspenders: always the last (top-most) sibling too
	var icon_top := over.position.y
	var icon_bottom := over.position.y + over.size.y
	_bar_icon_bottom = icon_bottom   # remembered for _hide_bar()'s own containment clamp
	var docked_y := maxf(icon_bottom - BAR_H - lift, icon_top)          # top edge clamp (defensive)
	var docked_pos := Vector2(over.position.x, docked_y)
	_bar_natural_pos = docked_pos   # remembered for _on_hud_edit_confirmed's offset math
	var start_y := minf(docked_pos.y + BAR_H, icon_bottom - BAR_H)      # bottom edge clamp (the actual bug)
	var start := Vector2(over.position.x, start_y)
	var target := docked_pos
	if _hover_bar.top_level:
		var xform := container().get_global_transform_with_canvas()
		target = xform * docked_pos + _bar_offset
		start = xform * start + _bar_offset
	_hover_bar.position = start
	_hover_bar.visible = true
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(_hover_bar, "position", target, BAR_SLIDE_TIME).set_ease(Tween.EASE_OUT)

## HudEditRuntime.edit_confirmed listener: only cares about "dock.hover_bar" — derives + persists the
## room-independent move offset (see the field's doc comment above _bar_offset).
func _on_hud_edit_confirmed(id: String, control: Control) -> void:
	if id != "dock.hover_bar" or _hover_bar == null:
		return
	var xform := container().get_global_transform_with_canvas()
	_bar_offset = control.position - xform * _bar_natural_pos
	_save_bar_offset()

func _load_bar_offset() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BAR_OFFSET_SAVE_PATH) != OK:
		return
	_bar_offset = cfg.get_value("dock_binder", "hover_bar_offset", Vector2.ZERO)

func _save_bar_offset() -> void:
	var cfg := ConfigFile.new()
	cfg.load(BAR_OFFSET_SAVE_PATH)   # preserve HudEditRuntime's own [hud_edit] section in the same file
	cfg.set_value("dock_binder", "hover_bar_offset", _bar_offset)
	cfg.save(BAR_OFFSET_SAVE_PATH)

## Slide the name-bar back down out of view. Same containment fix as _show_bar()'s (2026-08-06): clamps the
## slide-down target so the bar's bottom edge doesn't dip past the just-hovered room's own bottom edge
## (`_bar_icon_bottom`, set by the _show_bar() call that necessarily preceded this one) — otherwise this
## animation overshot by the same BAR_H−lift px in the opposite direction.
func _hide_bar() -> void:
	if _hover_bar == null or not _hover_bar.visible:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	var local_target_y := minf(_bar_natural_pos.y + BAR_H, _bar_icon_bottom - BAR_H)
	var target: Vector2
	if _hover_bar.top_level:
		var xform := container().get_global_transform_with_canvas()
		target = xform * Vector2(_bar_natural_pos.x, local_target_y) + _bar_offset
	else:
		target = Vector2(_bar_natural_pos.x, local_target_y)
	_hover_tween = create_tween()
	_hover_tween.tween_property(_hover_bar, "position", target, BAR_SLIDE_TIME).set_ease(Tween.EASE_IN)
	_hover_tween.tween_callback(func() -> void: _hover_bar.visible = false)

func clear() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	for n in _runtime_extras:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_runtime_extras.clear()
	_click_player = null
	_hover_bar = null
	_hover_bar_label = null
	_locks.clear()
