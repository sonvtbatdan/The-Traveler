extends Node2D
## Draw node for one Gauss explosion. A dumb visual: arena_weapons.gd drives the (non-uniform) animation
## + lifetime + DoT and just feeds it the current frame each tick. Draws via draw_texture_rect so the full
## frame scales into draw_rect (NO EXPAND_IGNORE_SIZE clip → no square cutoff). Uses NORMAL (MIX) blend —
## same as arena_explosion.gd and the Gauss orb: these frames are glow-baked smoky art, so additive would
## wash the gray smoke across the whole quad into a boxy halo.
##
## FALLBACK ART (see GAUSS_USE_SPRITE_VFX in arena_weapons.gd) — kept side-by-side with the procedural
## gauss_orb_fx.gd/.gdshader burst, same convention as lasgun_ani_1.gd being the Lasgun's sprite fallback.

var tex: Texture2D = null
var draw_rect: Rect2 = Rect2()   # top-left = -ANCHOR*scale, size = frame_native*scale (set by spawner)

func set_frame(t: Texture2D) -> void:
	tex = t
	queue_redraw()

func _draw() -> void:
	if tex != null:
		draw_texture_rect(tex, draw_rect, false)
