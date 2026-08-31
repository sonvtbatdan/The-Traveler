extends Node
class_name ArenaAlwaysPump
## Tiny reusable helper: calls `tick` every frame regardless of SceneTree.paused.
##
## Godot only keeps a node ticking during pause if its OWN process_mode is PROCESS_MODE_ALWAYS (or
## WHEN_PAUSED) — the default is to freeze along with everything else. Flipping a big owner node
## (arena.gd's Arena, arena_weapons.gd's weapon instance) to ALWAYS would keep its ENTIRE _process() running
## during Dev Mode's pause (movement, aim, combat, chain steering...), which is very much not the goal.
##
## This is a standalone, disposable node whose only job is to keep exactly ONE cosmetic per-frame callback
## alive — a key light's rotation (arena.gd's ship, arena_weapons.gd's VIPER), tracking a Light Edit change
## the tester needs to see move immediately while the panel is open and paused, not just after they close it.
##
## 2026-08-28 bug report ("sao tôi chỉnh light height và các slider khác, bóng đổ lên terrain của player vẫn
## ko thay đổi nhỉ" — filed against an earlier drop-shadow feature since removed outright, but the underlying
## pause bug applies equally to the key-light rotation this pump now exists for): Dev Mode (arena_hud_buttons.
## gd's set_dev_mode()) sets get_tree().paused = true, and Light Edit is a Dev Mode-only panel — the terrain's
## own shading updates instantly regardless (it's a raw shader parameter, not gated by any node's _process()),
## but the lighting code that read it lived inside each owner's own big, now-paused _process(), so it visibly
## did nothing until the panel was closed.
##
## Usage: var pump := ArenaAlwaysPump.new(); pump.tick = Callable(self, "_my_update_fn"); add_child(pump)

var tick: Callable = Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if tick.is_valid():
		tick.call(delta)
