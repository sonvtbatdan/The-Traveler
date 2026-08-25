extends SceneTree
## DEV TOOL (2026-08-24) — the Dev → Creep → Boss tab's cells actually spawn their boss WHEN THE FIELD IS
## FULL. That is the case that was broken: _spawn_enemy_at passed a hardcoded `is_boss = false`, and the
## director's cap gate only bypasses MAX_ALIVE for boss/elite defs, so a boss click was silently rejected on
## any busy field — which during real play is nearly always. Floods the arena to the cap first, deliberately,
## because a click on an EMPTY field would have passed even with the bug.
##
## Presses the real Button (`emit_signal("pressed")`) rather than calling the spawn helper, so the whole
## path is exercised: cell -> _spawn_quick_enemy -> _spawn_enemy_at -> director.
##
## Run NON-headless:  godot --path . --script tools/check_boss_quickspawn.gd

var _f := 0
var _fails := 0

func _initialize() -> void:
	var packed := load("res://scenes/arena.tscn") as PackedScene
	get_root().add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _on_post_draw() -> void:
	_f += 1
	if _f == 60:
		_flood()
	elif _f == 120:
		_press_boss_cells()
	elif _f == 160:
		var img := get_root().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		print("screenshot: err=", img.save_png("user://boss_tab.png"))
	elif _f == 200:
		_report()
		quit(1 if _fails > 0 else 0)

## Fill the arena past the director's own alive cap.
func _flood() -> void:
	var dbg: Node = get_first_node_in_group("arena_debug_spawn")
	var wd: Node = get_first_node_in_group("wave_director")
	var pl := get_first_node_in_group("player") as Node2D
	var cap := 0
	if wd.has_method("_effective_cap"):
		cap = int(wd.call("_effective_cap"))
	for i in 400:
		dbg.call("_spawn_enemy_at", "fly", pl.global_position + Vector2(randf_range(-600, 600), randf_range(-400, 400)))
	var alive := get_node_count_in_group("arena_enemy")
	print("flooded: %d alive, director cap = %d  (at/over cap: %s)" % [alive, cap, str(alive >= cap)])
	if cap > 0 and alive < cap:
		print("  !! could not reach the cap — this run does not test what it claims to")
		_fails += 1

func _press_boss_cells() -> void:
	var dbg: Node = get_first_node_in_group("arena_debug_spawn")
	dbg.call("set_dev_ui_visible", true)
	dbg.call("toggle_creep_panel")
	dbg.call("_select_creep_tab", "boss")
	var scroll := dbg.get("_creep_boss_content") as Control
	if scroll == null or scroll.get_child_count() == 0:
		print("boss tab content missing")
		_fails += 1
		return
	var grid := scroll.get_child(0)
	print("boss tab cells: ", grid.get_child_count())
	var ids: Array[String] = dbg.get("QUICK_BOSS_IDS")
	for i in grid.get_child_count():
		var btn := grid.get_child(i) as Button
		var id: String = ids[i] if i < ids.size() else "?"
		var before := _count_of(id)
		btn.emit_signal("pressed")
		var after := _count_of(id)
		var ok := after > before
		print("  press '%s': %d -> %d  %s" % [id, before, after, "OK" if ok else "FAILED (nothing spawned)"])
		if not ok:
			_fails += 1

## Live enemies of `type_id`, counted by the def's own "icon" path (arena_enemy.gd keeps it as
## `_original_icon`). arena_enemy has NO `type_id` member — an earlier version of this tool read one, always
## got null, and reported every press as a failure even when the spawn had worked.
func _count_of(type_id: String) -> int:
	var wd: Node = get_first_node_in_group("wave_director")
	var defs: Dictionary = wd.get("ENEMY_DEFS")
	var icon := String((defs.get(type_id, {}) as Dictionary).get("icon", ""))
	if icon == "":
		return -1
	var n := 0
	for e: Node in get_nodes_in_group("arena_enemy"):
		if String(e.get("_original_icon")) == icon:
			n += 1
	return n

func _report() -> void:
	# The metalfly that just spawned must be in its cocoon phase with the cocoon body up.
	for e: Node in get_nodes_in_group("arena_enemy"):
		if String(e.get("_boss_move")) == "metalfly":
			print("spawned metalfly: phase=%s  hp=%s/%s  cocoon body=%s"
				% [e.get("_mf_phase"), e.get("hp"), e.get("hp_max"), e.get("_mf_cocoon") != null])
			break
	print("── ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails, " ──")
