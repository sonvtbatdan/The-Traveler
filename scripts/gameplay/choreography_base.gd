extends Node

## Choreography base — a named, code-defined scripted wave / set-piece. The wave_director owns ONE at a
## time and drives it explicitly:  start(mgr) → tick(delta) every frame → is_done() to advance →
## cleanup() at the end. A choreography spawns specific enemies (via the EnemyManager), can script their
## movement / inter-enemy events over time, and reports when it is finished.
##
## A new set-piece = one small script that  extends "res://scripts/gameplay/choreography_base.gd"  (by
## PATH — no class_name, to dodge the headless class-cache pitfalls this repo has hit) and overrides
## start/tick/is_done (and optionally max_time/cleanup). Then add it to choreography_registry.gd.
##
## NOTE: the director drives tick() — do NOT override _process in a subclass.

const DEFAULT_MAX_TIME := 90.0   # backstop: the director force-advances if a choreography runs this long

var _mgr: Node = null            # EnemyManager (spawn_type / spawn_* + ship position), group "enemy_manager"

## Called once when this wave begins. Subclasses override and call super(mgr), then start their spawns.
func start(mgr: Node) -> void:
	_mgr = mgr

## Per-frame update: spawn timing, scripted movement, inter-enemy events. Default: nothing.
func tick(_delta: float) -> void:
	pass

## Report completion. Default: never done on its own (the director's max_time() backstop still ends it).
func is_done() -> bool:
	return false

## Per-choreography backstop in seconds — override for long set-pieces.
func max_time() -> float:
	return DEFAULT_MAX_TIME

## Teardown when the wave ends or the director stops. Default: nothing (enemies are left to the director).
func cleanup() -> void:
	pass

## Shared helper: how many normal enemies are alive right now — the usual "screen cleared" completion test.
func _living_enemies() -> int:
	if not is_inside_tree():
		return 0
	return get_tree().get_nodes_in_group("normal_enemy").size()

## Shared helper: centimetres → pixels via the screen DPI (mirrors enemy_base.cm_to_px), for set-pieces
## whose distances are specced in cm.
func _cm_to_px(cm: float) -> float:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	return cm / 2.54 * float(dpi)
