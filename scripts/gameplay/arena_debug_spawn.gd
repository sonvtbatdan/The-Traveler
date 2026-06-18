extends CanvasLayer
## Debug spawner for the non-planet celestial bodies. Keys (all confirmed unbound elsewhere):
##   F5  = asteroid field near the player      Shift+F5  = clear debug asteroid fields
##   F9  = comet near the player               Shift+F9  = clear debug comets
##   F10 = planet WITH moons near the player    Shift+F10 = clear debug planets (incl. their moons)
##   F11 = next gas/dust structure near player  Shift+F11 = clear debug structures
##         (cycles ring nebula → reflection → dark → pillars each press)
##   F12 = Lasgun weapon pickup near the player  Shift+F12 = clear uncollected weapon pickups
## (F6 = planet menu, F7 = wave editor — left alone.) Moons also spawn automatically with F6/streamed planets.

const FR_STEP        := 0.5    # fire-rate mult change per +/- press (tune for faster/slower testing)
const GAT_INTERVAL   := 0.09   # mirrors arena_weapons.gd GAT_FIRE_INTERVAL (keep in sync if changed)
const FR_MULT_MIN    := 0.5    # clamp floor so fire rate can't go negative or too slow

var _rng := RandomNumberGenerator.new()
var _struct_cycle: int = 0   # F11 steps through the four structure types
var _fr_label: Label = null
var _dev_ui_root: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("arena_debug_spawn")
	_rng.randomize()
	_build_fire_rate_ui()

func set_dev_ui_visible(v: bool) -> void:
	if _dev_ui_root != null:
		_dev_ui_root.visible = v

func _build_fire_rate_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.anchor_left   = 0.5
	hb.anchor_right  = 0.5
	hb.anchor_top    = 1.0
	hb.anchor_bottom = 1.0
	hb.offset_left   = -160
	hb.offset_right  =  160
	hb.offset_top    =  -38
	hb.offset_bottom =  -8
	root.add_child(hb)
	_dev_ui_root = root

	var btn_minus := Button.new()
	btn_minus.text = "−"
	btn_minus.custom_minimum_size = Vector2(32, 28)
	btn_minus.pressed.connect(_fr_decrease)
	hb.add_child(btn_minus)

	_fr_label = Label.new()
	_fr_label.custom_minimum_size = Vector2(260, 28)
	_fr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fr_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_fr_label)

	var btn_plus := Button.new()
	btn_plus.text = "+"
	btn_plus.custom_minimum_size = Vector2(32, 28)
	btn_plus.pressed.connect(_fr_increase)
	hb.add_child(btn_plus)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(16, 0)
	hb.add_child(sep)

	var btn_lvl := Button.new()
	btn_lvl.text = "+ Level"
	btn_lvl.custom_minimum_size = Vector2(72, 28)
	btn_lvl.pressed.connect(_add_level)
	hb.add_child(btn_lvl)

func _add_level() -> void:
	if GameManager.has_method("add_xp"):
		var level: int = GameManager.player_level if "player_level" in GameManager else 1
		var xp_needed: int = GameManager.xp_to_next(level) if GameManager.has_method("xp_to_next") else 100
		GameManager.add_xp(xp_needed)

func _fr_increase() -> void:
	if GameManager.has_method("add_fire_rate"):
		GameManager.add_fire_rate(FR_STEP)

func _fr_decrease() -> void:
	if GameManager.has_method("add_fire_rate") and GameManager.upg_fire_rate_mult - FR_STEP >= FR_MULT_MIN:
		GameManager.add_fire_rate(-FR_STEP)

func _process(_delta: float) -> void:
	if _fr_label == null or not GameManager.has_method("get_fire_rate_mult"):
		return
	var mult: float = GameManager.get_fire_rate_mult()
	var shots_per_sec: float = mult / GAT_INTERVAL
	var barrels: int = maxi(1, floori(shots_per_sec / 10.0))
	_fr_label.text = "Fire: %.1f/s  |  %d barrel%s  |  ×%.2f" % [
		shots_per_sec, barrels, "s" if barrels > 1 else " ", mult
	]

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_F5:
			if key.shift_pressed: _clear("arena_asteroids")
			else: _spawn_asteroids()
			get_viewport().set_input_as_handled()
		KEY_F9:
			if key.shift_pressed: _clear("arena_comets")
			else: _spawn_comet()
			get_viewport().set_input_as_handled()
		KEY_F10:
			if key.shift_pressed: _clear_planets()
			else: _spawn_planet_with_moons()
			get_viewport().set_input_as_handled()
		KEY_F11:
			if key.shift_pressed: _clear("arena_structures")
			else: _spawn_structure_cycle()
			get_viewport().set_input_as_handled()
		KEY_F12:
			if key.shift_pressed: _clear_weapon_pickups()
			else: _spawn_lasgun_pickup()
			get_viewport().set_input_as_handled()

func _near_player() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	var base := cam.global_position if cam != null else Vector2.ZERO
	return base + Vector2(_rng.randf_range(-180.0, 180.0), _rng.randf_range(-120.0, 120.0))

func _spawn_asteroids() -> void:
	var layer := get_tree().get_first_node_in_group("arena_asteroids")
	if layer == null:
		return
	var n: int = layer.spawn_field_near(_near_player())
	print("[debug] F5 asteroid field spawned (%d rocks)" % n)

func _spawn_comet() -> void:
	var layer := get_tree().get_first_node_in_group("arena_comets")
	if layer == null:
		return
	layer.spawn_comet_near(_near_player())
	print("[debug] F9 comet spawned")

func _spawn_planet_with_moons() -> void:
	var layer := get_tree().get_first_node_in_group("arena_planets")
	if layer == null:
		return
	var pl: Node2D = layer.spawn_planet_with_moons(_near_player(), _rng)
	print("[debug] F10 planet+moons spawned: %d moon(s)" % pl._moons.size())

func _spawn_structure_cycle() -> void:
	var layer := get_tree().get_first_node_in_group("arena_structures")
	if layer == null:
		return
	var t: int = _struct_cycle % 3   # pillars (type 3) disabled for now → set 4 to re-enable
	_struct_cycle += 1
	layer.spawn_structure_near(_near_player(), t, _rng)
	print("[debug] F11 structure spawned: %s" % ArenaStructure.TYPE_NAMES[t])

func _clear(group: String) -> void:
	var layer := get_tree().get_first_node_in_group(group)
	if layer != null and layer.has_method("clear_debug"):
		layer.clear_debug()
	print("[debug] cleared ", group)

func _spawn_lasgun_pickup() -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons == null or not weapons.has_method("spawn_lasgun_pickup_near"):
		return
	weapons.spawn_lasgun_pickup_near(_near_player())
	print("[debug] F12 Lasgun pickup spawned")

func _clear_weapon_pickups() -> void:
	for n in get_tree().get_nodes_in_group("debug_weapon_pickup"):
		if is_instance_valid(n):
			n.queue_free()
	print("[debug] cleared weapon pickups")

func _clear_planets() -> void:
	for n in get_tree().get_nodes_in_group("debug_planet"):
		if is_instance_valid(n):
			n.queue_free()
	print("[debug] cleared debug planets")
