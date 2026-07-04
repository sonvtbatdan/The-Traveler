extends Node
class_name BoardBinder
## Base class for a board's RUNTIME behaviour. The generic board editor/surface
## (`board_edit_mode.gd`) authors an ordered list of GROUPS of sprite items + text layers and, while it
## is NOT in editing mode, the placed nodes ARE the live surface. A BoardBinder makes those placed nodes
## dynamic: it resolves "role" nodes from the authored layout (by group name / filename / sentinel text),
## spawns any runtime-only extras it needs, and updates them from live game state every frame.
##
## The binder reaches into the surface via `_ed` (the board_edit_mode instance). The surface exposes its
## authored data + node helpers with public `_`-prefixed members (underscore is convention only, not access
## control), so a binder can read `_ed._groups`, `_ed._nodes`, `_ed._objects_container`,
## `_ed._load_tex(...)`, `_ed._item_path(...)`, `_ed._find_child(...)`, `_ed._child_visible(...)`.
##
## Lifecycle (driven by the surface):
##   setup(surface)  — once, right after the binder is created.
##   build()         — resolve roles + create runtime extras. Called on first setup and whenever the editor
##                     closes (editing may have rebuilt the design nodes). Torn down by clear().
##   update(delta)   — per frame while the surface is live (editor not open).
##   clear()         — free everything build() created (called before editing + before rebuild).

## A BoardBinder is a Node added as a child of the surface, so get_tree()/get_viewport()/create_tween()
## work natively; it reads the surface's authored data + node helpers through `_ed`.
var _ed = null   # the board_edit_mode surface (duck-typed to avoid a hard cyclic dependency)

func setup(surface) -> void:
	_ed = surface

## Resolve roles + spawn runtime extras. Override in a subclass.
func build() -> void:
	pass

## Per-frame live update while the surface is showing (not being edited). Override in a subclass.
func update(_delta: float) -> void:
	pass

## Free every node/tween this binder created. Override in a subclass.
func clear() -> void:
	pass

# ── Editor-facing capability hooks (let the generic editor stay board-agnostic) ──────────────────────
## A "bar band" sprite: the editor shows the GROW-direction dropdown for it and treats it as an edit-only
## indicator (hidden in gameplay; its masked fill is the visible bar). Non-bar boards return false.
func is_band_file(_file: String) -> bool:
	return false
