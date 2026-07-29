extends "res://tests/test_case.gd"
## Smoke test: every ENEMY_DEFS entry's "icon" must resolve to a real, loadable asset.
## Catches typo'd/missing paths in the 60+ entry data table without needing to spawn anything —
## cheap, high value, and exactly the kind of regression #1 (batch rewrite) could silently cause
## if an entry's icon field gets dropped/renamed during the refactor.

const WaveDirectorScript := preload("res://scripts/gameplay/arena_wave_director.gd")
const ArenaEnemyScript   := preload("res://scripts/gameplay/arena_enemy.gd")

func test_all_enemy_def_icons_resolve() -> void:
	var defs: Dictionary = WaveDirectorScript.ENEMY_DEFS
	assert_true(defs.size() > 0, "ENEMY_DEFS should not be empty")
	var missing: Array[String] = []
	for id: String in defs.keys():
		var def: Dictionary = defs[id]
		var icon: String = String(def.get("icon", ""))
		if icon == "":
			continue   # some defs (e.g. shape-only placeholders) have no icon — not an error
		var resolved: String = ArenaEnemyScript._resolve_sprite(icon)
		if not (ResourceLoader.exists(resolved) or FileAccess.file_exists(resolved)):
			missing.append("%s -> %s (resolved: %s)" % [id, icon, resolved])
	assert_true(missing.is_empty(), "unresolved icons: " + ", ".join(missing))

func test_all_enemy_defs_have_required_fields() -> void:
	var defs: Dictionary = WaveDirectorScript.ENEMY_DEFS
	var bad: Array[String] = []
	for id: String in defs.keys():
		var def: Dictionary = defs[id]
		if not def.has("behavior") or String(def.get("behavior", "")) == "":
			bad.append(id)
	assert_true(bad.is_empty(), "defs missing a behavior: " + ", ".join(bad))
