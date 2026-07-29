extends SceneTree
## Lightweight custom test runner — no addon dependency. Run from the project root:
##   "C:\Program Files\Godot\Godot.exe" --headless --script res://tests/run_tests.gd
##
## Discovers every res://tests/test_*.gd file, instantiates it (must `extends
## "res://tests/test_case.gd"`), calls every test_*() method found via reflection, prints
## PASS/FAIL per test, then a summary. Exits 0 if everything passed, 1 if anything failed —
## usable as a rough pass/fail gate even without real CI.
##
## Caveat: GDScript has no try/catch, so a test that hits a genuine runtime error (null deref,
## etc.) will print a Godot engine error above its PASS/FAIL line instead of being caught as a
## clean failure — read the console, not just the summary count, when something looks wrong.

const TEST_DIR := "res://tests/"

func _initialize() -> void:
	# _initialize() runs before the engine's own tree bootstrap finishes in --script mode: root.add_child()
	# calls made here don't take effect synchronously (get_tree()/is_inside_tree() on the child stay
	# null/false until the next frame). Awaiting one process_frame first lets tests freely add real nodes
	# under `tree.root` and have get_tree() work immediately, like it would in a normal running game.
	await process_frame
	var files := _find_test_files(TEST_DIR)
	files.sort()
	var total := 0
	var failed := 0
	for path: String in files:
		var script := load(path) as GDScript
		if script == null:
			print("[SKIP] %s -- failed to load as GDScript" % path)
			continue
		var inst: Object = script.new()
		if not (inst.has_method("setup") and inst.has_method("teardown")):
			continue   # not a test_case.gd subclass
		for method_info: Dictionary in inst.get_method_list():
			var mname: String = method_info["name"]
			if not mname.begins_with("test_"):
				continue
			total += 1
			inst.set("tree", self)
			inst.set("_failed", false)
			inst.set("_fail_msg", "")
			inst.call("setup")
			inst.call(mname)
			var ok: bool = not bool(inst.get("_failed"))
			var err: String = String(inst.get("_fail_msg"))
			inst.call("teardown")
			if not ok:
				failed += 1
			print("[%s] %s :: %s%s" % ["PASS" if ok else "FAIL", path.get_file(), mname, ("  -- " + err) if err != "" else ""])
	print("")
	print("=== %d tests, %d failed ===" % [total, failed])
	quit(1 if failed > 0 else 0)

func _find_test_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out
