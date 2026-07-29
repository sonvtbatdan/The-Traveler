extends BoardBinder
class_name DockBinder
## RUNTIME for the "Dock" board — the between-run home screen, hosted by hub_screen.gd (see arena.gd's
## "RETURN TO DOCK" button → res://scenes/hub.tscn). hub_screen.gd listens to room_clicked below and
## decides what each room does; this binder only owns hover/click FEEDBACK, not game destinations.
##
## Room → destination (per design, 2026-07-26/27):
##   Equipment   → Loadout (hub_screen.gd's existing tab, reused as-is)
##   Mechanic    → Shop (existing tab, reused as-is)
##   Engineer    → Passives (existing tab) + Craft + Fragments, as 3 sub-tabs of one panel
##   Launch      → still directly launches a run (hub_screen.gd's old LAUNCH RUN button) — no map-select
##                 system exists to gate it on yet, so it can't be a "Coming Soon" like the rest
##   Constructor → Dock construction board (unlock dock sections) — not built, "Coming Soon"
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
const FONT_BODY := "res://assets/fonts/Gameplay.ttf"
const HOVER_SCALE := 1.05
const NO_HOVER_GROUPS := ["Background", "Frame"]   # backdrop layers, not a "function"
const BAR_H := 36.0                                 # hover name-bar height
const BAR_COLOR := Color(1.0, 1.0, 1.0, 0.40)        # translucent white
const BAR_SLIDE_TIME := 0.16
const BAR_Z := 239   # above every room/pilot item (max 237) but BELOW Frame (240) — Frame's window grid
                      # is meant to partially cover/clip the top of the bar, not sit behind it
const BAR_LIFT_PILOT := 5.0    # Launch + Pilot/Pilot2: nudge the docked bar up 5px
const BAR_LIFT_ROOM  := 15.0   # the 9 rooms: nudge the docked bar up 15px

var _click_player: AudioStreamPlayer = null
var _hover_bar: Control = null
var _hover_bar_label: Label = null
var _hover_tween: Tween = null
var _runtime_extras: Array = []

func build() -> void:
	clear()
	if _ed == null:
		return
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = SFX_HOVER
	_click_player.bus = "SFX"
	_ed.add_child(_click_player)
	_runtime_extras.append(_click_player)

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

	for g: Dictionary in (_ed._groups as Array):
		var gname := String(g.get("name", ""))
		if gname in NO_HOVER_GROUPS:
			continue
		if gname == "Launch":
			_wire_launch(g)
			continue
		for ch: Dictionary in (g.get("children", []) as Array):
			if String(ch.get("type", "")) != "item":
				continue
			var n = _ed._nodes.get(int(ch.get("id", -1)))
			if n != null and is_instance_valid(n):
				_wire_hover(n as Control, String(ch.get("file", "")))

## Grow 5% + hover SFX + name label above it; click emits room_clicked(name) — the host decides what to
## do with it (real destinations still get wired one at a time; everything else is a "Coming Soon" toast).
func _wire_hover(node: Control, file: String) -> void:
	node.pivot_offset = node.size * 0.5
	var label_text := file.capitalize()
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
		node.scale = Vector2(HOVER_SCALE, HOVER_SCALE)
		if _click_player != null:
			_click_player.play()
		_show_bar(label_text, node, lift))
	btn.mouse_exited.connect(func() -> void:
		node.scale = Vector2.ONE
		_hide_bar())
	btn.pressed.connect(func() -> void: room_clicked.emit(label_text))
	container().add_child(btn)
	_runtime_extras.append(btn)

## Launch: swap to the dedicated "launch hover" art (drawn by the artist for exactly this) instead of a
## generic scale, matching hud_binder.gd's _setup_hover_pair idiom — still gets the shared SFX + label.
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
		normal.visible = false
		if hover != null:
			hover.visible = true
		if _click_player != null:
			_click_player.play()
		_show_bar("Launch", normal, BAR_LIFT_PILOT))
	btn.mouse_exited.connect(func() -> void:
		normal.visible = true
		if hover != null:
			hover.visible = false
		_hide_bar())
	btn.pressed.connect(func() -> void: room_clicked.emit("Launch"))
	container().add_child(btn)
	_runtime_extras.append(btn)

## Slide the name-bar up from just below `over`'s bottom edge until it docks `lift` px above that edge
## (Launch/Pilot/Pilot2 use a smaller lift than the 9 rooms — see BAR_LIFT_PILOT/BAR_LIFT_ROOM).
func _show_bar(text: String, over: Control, lift: float) -> void:
	if _hover_bar == null:
		return
	_hover_bar_label.text = text
	_hover_bar.size = Vector2(over.size.x, BAR_H)
	container().move_child(_hover_bar, -1)   # belt-and-suspenders: always the last (top-most) sibling too
	var docked_pos := over.position + Vector2(0.0, over.size.y - BAR_H - lift)
	_hover_bar.position = docked_pos + Vector2(0.0, BAR_H)   # start just off the bottom edge
	_hover_bar.visible = true
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(_hover_bar, "position", docked_pos, BAR_SLIDE_TIME).set_ease(Tween.EASE_OUT)

## Slide the name-bar back down out of view.
func _hide_bar() -> void:
	if _hover_bar == null or not _hover_bar.visible:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	var target := _hover_bar.position + Vector2(0.0, BAR_H)
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
