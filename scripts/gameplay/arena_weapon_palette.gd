extends CanvasLayer
## F12 weapon palette (arena). A drag-and-drop spawn tool: opening it pauses the game and shows a panel of all
## arena weapons (Gatling / Lasgun / Arc / Gauss). Drag a weapon thumbnail onto the ground and a pickup drops
## at that world spot — walk over it (after closing) and the weapon activates + accumulates (VS-style).
## Self-contained: owns its F12 toggle + ESC close. Replaces the old direct-spawn F12 in arena_debug_spawn.gd.

# kind → inventory def_id (for the icon) + display label.
# Labels = spawn display names (canonical source: arena_weapons.WEAPON_INFO).
const WEAPONS := [
	{"kind": "gatling_gun", "def_id": "gatling_gun",  "label": "Gatling Gun"},
	{"kind": "death_beam",  "def_id": "death_beam",       "label": "Laser"},
	{"kind": "arc",     "def_id": "arc",          "label": "Lightning"},
	{"kind": "gauss",   "def_id": "gauss", "label": "Gauss"},
	{"kind": "orbital", "def_id": "defensive_orbitals",     "label": "Defensive Orbitals"},
	{"kind": "void",    "def_id": "rift_maker",   "label": "Rift Maker"},
	{"kind": "red_x",   "def_id": "dragons_breath",        "label": "Dragon's Breath"},
	{"kind": "chemtrail", "def_id": "chemtrail",  "label": "Chemtrail"},
	{"kind": "mortar",      "def_id": "mortar",          "label": "Little Man"},
	{"kind": "ultrasonicator",     "def_id": "sonic_wave",    "label": "Ultrasonicator"},
	{"kind": "z_sword",    "def_id": "z_sword",       "label": "Z-Sword"},
	{"kind": "ionizing_field",    "def_id": "ionizing_field","label": "Ionizer"},
	{"kind": "aliwa", "def_id": "boomerang",     "label": "Boomerang"},
	{"kind": "venomancer",  "def_id": "parasite_cloud","label": "Venomancer"},
	{"kind": "yari", "def_id": "moroboshi",     "label": "Yari"},
	{"kind": "swarm",     "def_id": "swarm_host",    "label": "Offensive Orbitals"},
	{"kind": "viper",     "def_id": "space_snake",   "label": "VIPER"},
	{"kind": "homing",    "def_id": "homing_missile","label": "Homing"},
]

const THUMB := Vector2(56, 56)

const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")  # for FUSION_DEFS (fused weapons auto-listed)

var _open := false
var _panel: Panel = null

## The base weapons plus every fused weapon (from FUSION_DEFS) — so any fusion auto-appears in F12 for testing.
## Spawning a fusion kind directly grants it via acquire_weapon (skips the combine cutscene).
func _palette_entries() -> Array:
	var entries := WEAPONS.duplicate()
	for fid: String in (ArenaWeapons.FUSION_DEFS as Dictionary).keys():
		var rec: Dictionary = ArenaWeapons.FUSION_DEFS[fid]
		entries.append({"kind": fid, "def_id": String(rec.get("def_id", "")), "label": String(rec.get("label", fid))})
	return entries

func _ready() -> void:
	layer = 101                                   # above the debug fire-rate UI
	process_mode = Node.PROCESS_MODE_ALWAYS       # keep working while the tree is paused
	add_to_group("arena_weapon_palette")
	visible = false
	_build_ui()

# ── UI ──────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Full-screen drop zone (dim backdrop). Accepts weapon drags anywhere on the battlefield.
	var zone := _DropZone.new()
	zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	zone.spawn_cb = Callable(self, "_spawn_weapon")
	add_child(zone)

	# Top-centre panel with the weapon thumbnails — laid out in 2 rows so the (17 base + fused) list fits on screen.
	var entries := _palette_entries()
	var cols := int(ceil(entries.size() / 2.0))
	var panel_w := float(cols) * (THUMB.x + 14.0) + 28.0
	var panel_h := 232.0
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(panel_w, panel_h)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -panel_w * 0.5
	_panel.offset_right = panel_w * 0.5
	_panel.offset_top = 18
	_panel.offset_bottom = 18 + panel_h
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.09, 0.13, 0.96)
	ps.set_border_width_all(1)
	ps.border_color = Color(0.4, 0.55, 0.85, 0.9)
	ps.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", ps)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12; vb.offset_top = 8; vb.offset_right = -12; vb.offset_bottom = -8
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "WEAPONS  [F12]  —  drag onto the ground"
	title.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	vb.add_child(title)

	var grid := GridContainer.new()
	grid.columns = cols   # 2 rows (ceil(count/2) per row)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for w: Dictionary in entries:
		grid.add_child(_make_thumb(w))

	var bottom := HBoxContainer.new()
	vb.add_child(bottom)
	var dummy := Button.new()
	dummy.text = "Spawn Dummy"
	dummy.tooltip_text = "Drop an invincible target dummy that blocks the beam (takes no damage)"
	dummy.pressed.connect(_spawn_dummy)
	bottom.add_child(dummy)
	var bee := Button.new()
	bee.text = "Spawn Bee"
	bee.tooltip_text = "Spawn animalbee flock (has thrust-point plumes — use to test plume VFX)"
	bee.pressed.connect(_spawn_bee)
	bottom.add_child(bee)
	var clear := Button.new()
	clear.text = "Clear pickups"
	clear.pressed.connect(_clear_pickups)
	bottom.add_child(clear)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_toggle)
	bottom.add_child(close)

func _make_thumb(w: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var btn := _Thumb.new()
	btn.kind = String(w["kind"])
	btn.custom_minimum_size = THUMB
	btn.expand_icon = true
	btn.mouse_default_cursor_shape = Control.CURSOR_DRAG
	btn.tooltip_text = "Click to equip %s (on the ship), or drag it onto the battlefield" % String(w["label"])
	# Click = spawn the pickup right on the ship (auto-collects on close). Drag = place it on the ground.
	btn.pressed.connect(_spawn_on_player.bind(String(w["kind"])))
	var tex := InventoryManager.get_icon(String(w["def_id"]))
	if tex != null:
		btn.icon = tex
		btn.drag_icon = tex
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		var shade := 0.12 if state == "normal" else (0.18 if state == "hover" else 0.08)
		s.bg_color = Color(shade, shade + 0.02, shade + 0.06, 0.95)
		s.set_border_width_all(1)
		s.border_color = Color(0.4, 0.55, 0.85, 0.9)
		s.set_corner_radius_all(6)
		btn.add_theme_stylebox_override(state, s)
	box.add_child(btn)

	var lbl := Label.new()
	lbl.text = String(w["label"])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	box.add_child(lbl)
	return box

# ── Actions ──────────────────────────────────────────────────────────────────────
## Drop callback: spawn a pickup of `kind` at the current world mouse position.
func _spawn_weapon(kind: String) -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons == null or not weapons.has_method("spawn_weapon_pickup"):
		return
	var wpos: Vector2 = (weapons as Node2D).get_global_mouse_position()
	weapons.spawn_weapon_pickup(kind, wpos)

## Click handler: spawn the pickup ON the ship and close (so it auto-collects → reliable "equip", no walking).
func _spawn_on_player(kind: String) -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons == null or not weapons.has_method("spawn_weapon_pickup"):
		return
	var player := get_tree().get_first_node_in_group("player")
	var pos: Vector2 = (player as Node2D).global_position if player != null else Vector2.ZERO
	weapons.spawn_weapon_pickup(kind, pos)
	if _open:
		_toggle()   # unpause so the pickup's _process runs and collects it immediately

## Drop an invincible target dummy near the ship (blocks the beam, takes no damage), then close.
func _spawn_dummy() -> void:
	var wd := get_tree().get_first_node_in_group("wave_director")
	var player := get_tree().get_first_node_in_group("player")
	if wd == null or player == null or not wd.has_method("spawn_dummy_near"):
		return
	wd.spawn_dummy_near((player as Node2D).global_position + Vector2(150, 0))
	if _open:
		_toggle()

func _spawn_bee() -> void:
	var mgr := get_tree().get_first_node_in_group("enemy_manager")
	if mgr == null or not mgr.has_method("spawn_bee"):
		return
	mgr.spawn_bee()
	if _open:
		_toggle()

func _clear_pickups() -> void:
	for n in get_tree().get_nodes_in_group("debug_weapon_pickup"):
		if is_instance_valid(n):
			n.queue_free()

## Open the palette (pauses the game). Public entry for weapon-test mode (arena.gd auto-opens it on boot).
func open() -> void:
	if not _open:
		_toggle()

func _toggle() -> void:
	_open = not _open
	visible = _open
	get_tree().paused = _open

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_F12:
		_toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _open:
		_toggle()
		get_viewport().set_input_as_handled()

# ── Inner classes ────────────────────────────────────────────────────────────────
## A weapon thumbnail that is a drag source. Drag data = {"kind": <weapon kind>}.
class _Thumb extends Button:
	var kind: String = ""
	var drag_icon: Texture2D = null

	func _get_drag_data(_pos: Vector2) -> Variant:
		var tr := TextureRect.new()
		tr.texture = drag_icon if drag_icon != null else icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(48, 48)
		tr.size = Vector2(48, 48)
		tr.modulate = Color(1, 1, 1, 0.8)
		set_drag_preview(tr)
		return {"kind": kind}

## Full-screen drop target. Accepts a weapon drag and forwards the kind to spawn_cb.
class _DropZone extends Control:
	var spawn_cb: Callable

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has("kind")

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if spawn_cb.is_valid():
			spawn_cb.call(String((data as Dictionary)["kind"]))
