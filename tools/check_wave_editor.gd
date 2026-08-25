extends SceneTree
## DEV TOOL (2026-08-24) — the three Wave Edit (F7) changes:
##   1. `test_chaser` is gone from the roster and `fly` is still there.
##   2. Gen and Gen All save the timeline to disk by themselves.
##   3. A two-digit Total HP is read as thousands (13 -> 13,000) when Gen is pressed.
##
## WRITES PROJECT FILES: res://levels/arena/<map file>.json and res://spawn_mode_2_wave_<map>.cfg — saving
## is the thing being tested, so it cannot be avoided. Back up levels/arena/ AND every
## spawn_mode_2_wave*.cfg before running, and restore both afterwards. (`levels/arena/elecforest.json`
## carries real authored content; clobbering it loses work.)
##
## Run NON-headless:  godot --path . --script tools/check_wave_editor.gd

var _f := 0
var _ed: Node = null
var _fails := 0

func _initialize() -> void:
	var packed := load("res://scenes/arena.tscn") as PackedScene
	get_root().add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _fail(msg: String) -> void:
	print("  FAIL: ", msg)
	_fails += 1

func _on_post_draw() -> void:
	_f += 1
	match _f:
		60:  _open()
		90:  _check_roster()
		120: _check_gen_row()
		160: _check_gen_all()
		200:
			print("── ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails, " ──")
			quit(1 if _fails > 0 else 0)

func _open() -> void:
	_ed = get_first_node_in_group("wave_editor")
	if _ed == null:
		_fail("wave_editor node not found")
		return
	_ed.call("_toggle")

func _check_roster() -> void:
	if _ed == null:
		return
	var types: Array = _ed.get("_types")
	print("── 1. roster ──")
	print("  roster size=%d  has 'test_chaser'=%s  has 'fly'=%s"
		% [types.size(), str(types.has("test_chaser")), str(types.has("fly"))])
	if types.has("test_chaser"):
		_fail("test_chaser is still in the editor roster")
	if not types.has("fly"):
		_fail("'fly' is missing — the entry test_chaser was hidden in favour of")
	# The director must still know it: only the EDITOR hides it, spawn_mode_2 still spawns it.
	var wd: Node = get_first_node_in_group("wave_director")
	var known: bool = (wd.get("ENEMY_DEFS") as Dictionary).has("test_chaser")
	print("  director still knows test_chaser: ", known, "  (must be true — hidden in the UI only)")
	if not known:
		_fail("test_chaser was removed from the director, not just the editor")

func _check_gen_row() -> void:
	if _ed == null:
		return
	print("── 2+3. per-row Gen: shorthand + autosave ──")
	var rows: Array = _ed.get("_rows")
	if rows.is_empty():
		_fail("no rows in the editor")
		return
	var row: Dictionary = rows[0]
	var sp := row.get("hp_spin") as SpinBox
	sp.value = 13.0                     # two digits, as typed
	print("  typed 13 -> spinbox holds %.1f  (a step of 100 used to snap this straight to 0)" % sp.value)
	if not is_equal_approx(sp.value, 13.0):
		_fail("the field cannot hold a two-digit value")
	var before := _contents()
	_ed.call("_on_gen_row", row)
	print("  after Gen: target_hp=%.0f  field=%.0f  actual row HP=%.0f"
		% [float(row.get("target_hp", 0.0)), sp.value, float(_ed.call("_row_total_hp", row))])
	if not is_equal_approx(float(row.get("target_hp", 0.0)), 13000.0):
		_fail("13 was not expanded to 13000")
	if not is_equal_approx(sp.value, 13000.0):
		_fail("the expansion was not written back into the field")
	var got: float = float(_ed.call("_row_total_hp", row))
	if absf(got / 13000.0 - 1.0) > 0.25:
		_fail("generated HP %.0f is nowhere near the 13000 target" % got)
	var after := _contents()
	print("  timeline file %d -> %d bytes  (rewritten: %s)" % [before.length(), after.length(), str(after != before)])
	if after == before:
		_fail("Gen did not save the file")

func _check_gen_all() -> void:
	if _ed == null:
		return
	print("── 2+3. Gen All ──")
	var rows: Array = _ed.get("_rows")
	if rows.size() < 3:
		_fail("need 3 rows for the Gen All check")
		return
	(rows[1].get("hp_spin") as SpinBox).value = 25.0
	(rows[2].get("hp_spin") as SpinBox).value = 7.0
	var before := _contents()
	_ed.call("_on_gen_all")
	print("  row1 target=%.0f (typed 25)   row2 target=%.0f (typed 7)"
		% [float(rows[1].get("target_hp", 0.0)), float(rows[2].get("target_hp", 0.0))])
	if not is_equal_approx(float(rows[1].get("target_hp", 0.0)), 25000.0):
		_fail("25 was not expanded to 25000")
	if not is_equal_approx(float(rows[2].get("target_hp", 0.0)), 7000.0):
		_fail("7 was not expanded to 7000")
	var after := _contents()
	print("  timeline file %d -> %d bytes  (rewritten: %s)" % [before.length(), after.length(), str(after != before)])
	if after == before:
		_fail("Gen All did not save the file")
	# The saved file must actually contain what Gen All just produced, not merely differ.
	var parsed: Variant = JSON.parse_string(after)
	var n_entries: int = (parsed.get("timeline", []) as Array).size() if parsed is Dictionary else -1
	print("  saved timeline holds %d entries" % n_entries)
	if n_entries <= 0:
		_fail("the saved file has no timeline entries")

## CONTENT of the timeline file this map saves to. Used instead of the modification time, which has
## one-SECOND resolution: the two Gen presses in this tool land ~0.25 s apart, so mtime reported "not
## saved" for a file that had in fact just been rewritten.
func _contents() -> String:
	var p := _timeline_path()
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _timeline_path() -> String:
	var fixed: String = _ed.call("_fixed_file_for_map")
	var fname: String = fixed if fixed != "" else (_ed.call("_sanitize", (_ed.get("_name_edit") as LineEdit).text) + ".json")
	return "res://levels/arena/" + fname
