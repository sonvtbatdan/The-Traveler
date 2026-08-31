extends Node
## Background warm-up for the level-up board's 3D weapon models — fixes the hitch on every level-up.
##
## Why (2026-08-24, user report "mỗi lần lên level thì bị giật lag — có phải do load model 3D không?"): yes.
## The level-up board swaps a live-rendered `item_3d_icon.gd` in wherever a weapon has a sibling .glb (3 small
## choice cards + 1 big WeaponDisplay preview, all built in the same frame the board opens). A COLD load of one
## of those glbs measures 280–345ms each — see the per-file timings in the trace log for this change — so
## opening the board stalled the main thread for most of a second. Worse, it recurred: Godot's resource cache
## keeps only WEAK references, so once the board closes and its icons free, the PackedScene is released and the
## NEXT level-up pays the identical cost again.
##
## What this does: walks every weapon/fusion the board can possibly offer, resolves each one's .glb exactly the
## way arena_levelup_ui._weapon_icon_glb() does (including its 5-weapon high-poly override), plus the arena
## pickup's own separately-curated model table, and loads them all through ResourceLoader's THREADED path —
## off the main thread, one at a time, while the player is flying around — parking each finished PackedScene
## in item_3d_icon.gd's static warm cache (a strong reference, which is what actually keeps it resident). By
## the time the first level-up lands (or a weapon with curated arena art drops) the model is already resident.
##
## Deliberately paced, not a blocking preload at startup: one request in flight at a time, and nothing starts
## until START_DELAY has passed, so the arena's own load finishes first and the background thread never
## competes with the opening seconds of a run.

const Item3DIcon := preload("res://scripts/ui/hud/item_3d_icon.gd")
const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")
const LevelUpUI := preload("res://scripts/ui/hud/arena_levelup_ui.gd")   # HIGHPOLY_GLB values only — no instance made here

const START_DELAY := 3.0    # seconds into the run before the first request goes out
const POLL_INTERVAL := 0.1  # how often the in-flight request's status is checked (it finishes on its own thread)

var _queue: PackedStringArray = []
var _in_flight: String = ""
var _t: float = 0.0
var _poll_t: float = 0.0
var _done: bool = false
var _warmed: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE   # no need to keep warming while the game is paused
	_queue = _collect_paths()
	if _queue.is_empty():
		_done = true
		set_process(false)

## Every distinct .glb any of the FOUR curated art paths can show, in the order they're most likely to be
## needed. Each resolved the exact same way its own consumer resolves it, so the preload set can never miss
## (or mis-order) something a real screen would load cold:
##   1. The level-up board's NORMAL resolution (arena_levelup_ui._weapon_icon_glb() minus its high-poly
##      override) — every WEAPON_INFO/FUSION_DEFS kind's def_id/icon glb via InventoryManager.glb_for().
##   2. The level-up board's HIGH-POLY override (LevelUpUI.HIGHPOLY_GLB) — 5 specific def_ids, 2026-08-24.
##   3. The arena pickup's curated table (ArenaWeapons.ARENA_PICKUP_GLB) — deliberately NOT the same
##      resolution as (1): see that table's own comment for why arena art can't be auto-derived.
##   4. Ruin-drop pickups (arena_loot.gd, 2026-08-29 on request: "pre-load các model ruin drop... để tránh lag
##      khi drop") — heart/magnetic/divinity/shield + coin, the exact same 5 paths arena_loot.gd's own
##      _load_tex() resolves ("res://assets/screen/%s.glb" % type, with coin's own COIN_GLB override). Both
##      this list and that file's still keep their own copy of the "screen/" prefix rather than sharing a
##      constant — same "read-only tables that would need to import each other" tradeoff as the rest of this
##      file's per-source duplication, not worth a cross-file dependency for 5 literals.
## Anything without a model in ALL FOUR is simply absent — those slots keep using their flat PNG.
func _collect_paths() -> PackedStringArray:
	var seen: Dictionary = {}
	var out: PackedStringArray = []
	var sources: Array = [ArenaWeapons.WEAPON_INFO, ArenaWeapons.FUSION_DEFS]
	for src: Dictionary in sources:
		for kind: String in src.keys():
			var info: Dictionary = src[kind]
			var def_id := String(info.get("def_id", ""))
			var hp := String(LevelUpUI.HIGHPOLY_GLB.get(def_id, ""))
			var path := hp if hp != "" else _glb_for(def_id, String(info.get("icon", "")))
			if path == "" or seen.has(path):
				continue
			seen[path] = true
			out.append(path)
	for path2 in ArenaWeapons.ARENA_PICKUP_GLB.values():
		var p := String(path2)
		if p == "" or seen.has(p):
			continue
		seen[p] = true
		out.append(p)
	for ruin_path in [
		"res://assets/screen/heart.glb", "res://assets/screen/magnetic.glb",
		"res://assets/screen/divinity.glb", "res://assets/screen/shield.glb",
		"res://assets/hud/coin.glb",
	]:
		var rp := String(ruin_path)
		if seen.has(rp) or not ResourceLoader.exists(rp):
			continue
		seen[rp] = true
		out.append(rp)
	return out

func _glb_for(def_id: String, icon_path: String) -> String:
	return InventoryManager.glb_for(def_id, icon_path) if InventoryManager.has_method("glb_for") else ""

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < START_DELAY:
		return
	if _in_flight == "":
		_start_next()
		return
	_poll_t += delta
	if _poll_t < POLL_INTERVAL:
		return
	_poll_t = 0.0
	var status := ResourceLoader.load_threaded_get_status(_in_flight)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var res := ResourceLoader.load_threaded_get(_in_flight)
		if res is PackedScene:
			Item3DIcon.warm_store(_in_flight, res as PackedScene)
			_warmed += 1
	else:
		push_warning("arena_glb_preloader: failed to preload " + _in_flight)
	_in_flight = ""

## Issue the next request, skipping anything already parked (a board that opened before this got there has
## already warmed that entry itself — see item_3d_icon.setup()'s own first-cold-load store).
func _start_next() -> void:
	while not _queue.is_empty():
		var path := _queue[0]
		_queue.remove_at(0)
		if Item3DIcon.is_warm(path):
			continue
		if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
			push_warning("arena_glb_preloader: could not queue " + path)
			continue
		_in_flight = path
		_poll_t = 0.0
		return
	_done = true
	set_process(false)
	# One line, matching arena.gd's own [arena-startup] convention — confirms at a glance that the board's
	# models really are resident before the first level-up (and how far into the run that finished).
	print("[glb-preload] %d weapon model(s) warmed by t=%.1fs" % [_warmed, _t])

## Leaving the arena (back to the main menu / another map) releases the parked models — no reason to hold the
## whole weapon-model set resident outside a run. The next arena's own preloader warms them again in the
## background, long before that run's first level-up.
func _exit_tree() -> void:
	if _in_flight != "":
		# Finish claiming the in-flight request so its thread result isn't left dangling in ResourceLoader.
		if ResourceLoader.load_threaded_get_status(_in_flight) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(_in_flight)
		_in_flight = ""
	Item3DIcon.warm_clear()
