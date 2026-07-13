extends BoardBinder
class_name ChooseWeaponBinder
## RUNTIME index for the authored CHOOSE WEAPON board. `arena_weapon_chest_ui.gd` keeps ALL its weapon-roll /
## pick logic; it only asks this binder for the "screen" item nodes (the 3 little console-monitor sprites
## the artist places anywhere, in any group) and renders each choice's icon + name onto them itself. The
## "CHOOSE YOUR WEAPON" title and any frame/bezel art are ordinary authored text/item layers — they render on
## their own once the board is live, no role lookup needed.
##
## Role: any item child with file == "screen", resolved BY FILENAME across every group (same idiom as the HUD
## board's bar-band resolution) — not a fixed group name, so the artist is free to organize groups as they like.
## Sorted left-to-right (x position) so slot order matches the 3 rolled weapons deterministically.

func has_layout() -> bool:
	return screen_nodes().size() >= 3

## The "screen" item nodes, sorted left-to-right — each is a weapon slot's center-anchor.
func screen_nodes() -> Array:
	if _ed == null:
		return []
	var out: Array = []
	for g: Dictionary in (_ed._groups as Array):
		for ch: Dictionary in (g.get("children", []) as Array):
			if String(ch.get("type", "")) == "item" and String(ch.get("file", "")) == "screen":
				var n = _ed._nodes.get(int(ch.get("id", -1)))
				if n != null and is_instance_valid(n):
					out.append(n)
	out.sort_custom(func(a, b): return (a as Control).position.x < (b as Control).position.x)
	return out

## z_index of the "background" bezel item (the console-frame art meant to sit over the screens), or -1 if
## not authored. Lets the per-slot scan VFX draw itself just under this layer instead of guessing off its
## own screen sprite's z (screens can each end up at a different z, which made the VFX inconsistently poke
## above the bezel on whichever screen happened to tie/out-rank it).
func background_z() -> int:
	if _ed == null:
		return -1
	for g: Dictionary in (_ed._groups as Array):
		for ch: Dictionary in (g.get("children", []) as Array):
			if String(ch.get("type", "")) == "item" and String(ch.get("file", "")) == "background":
				var n = _ed._nodes.get(int(ch.get("id", -1)))
				if n != null and is_instance_valid(n):
					return (n as CanvasItem).z_index
	return -1
