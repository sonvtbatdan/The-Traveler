extends CanvasLayer
## Debug spawner for the non-planet celestial bodies. Keys (all confirmed unbound elsewhere):
##   F5  = asteroid field near the player      Shift+F5  = clear debug asteroid fields
##   F9  = comet near the player               Shift+F9  = clear debug comets
##   F10 = planet WITH moons near the player    Shift+F10 = clear debug planets (incl. their moons)
##   F11 = next gas/dust structure near player  Shift+F11 = clear debug structures
##         (cycles ring nebula → reflection → dark → pillars each press)
##   F12 = Lasgun weapon pickup near the player  Shift+F12 = clear uncollected weapon pickups
## (F6 = planet menu, F7 = wave editor — left alone.) Moons also spawn automatically with F6/streamed planets.

var _rng := RandomNumberGenerator.new()
var _struct_cycle: int = 0   # F11 steps through the four structure types

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()

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
