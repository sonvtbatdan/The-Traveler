extends Node2D
## Continuously expanding "sonar ping" rings, drawn around whatever this node is parented to — the in-world
## beacon for a landmark the player is meant to fly TO (2026-08-28, on request: "với chest hiện đang có hình
## tròn vàng làm nền, hãy thay nó bằng các vòng tròn tỏa ra liên tục, radius=100px. Tương tự, với rescue,
## dùng vòng tròn tỏa màu xanh nước biển. Landmark thì ko cần").
##
## Replaces arena_chest.gd's old static pulsing gold disc: a filled circle reads as decoration, an outward
## ripple reads as "come here", and it stays legible on the bright Electric/Atlantic ground where a 10-20%
## alpha fill mostly disappeared. Current users:
##   • arena_chest.gd            — GOLD, as a child of the chest itself.
##   • *_ruin_layer.gd (rescue)  — SEA_BLUE, as a child of the rescue landmark's arena_enemy vehicle, so it
##                                 is freed automatically the moment that landmark dies or despawns.
## Deliberately NOT used by the temple/landmark layers — "landmark thì ko cần".
##
## Parented (rather than spawned free-standing at a world position) on purpose: the ring set then inherits its
## host's lifetime with zero extra plumbing, which is why none of the three ruin layers needed changes to
## their `_active` entry dicts or their _on_ruin_gone() teardown. Set `z_index = -1` on this node when the
## host draws its own art (chest sprite / enemy vehicle) so the rings render UNDER it.

const MAX_R      := 100.0   # outermost radius a ring reaches before it dies — "radius=100px" per the request
const RING_COUNT := 3       # rings alive at once, evenly spread across the cycle
const PERIOD     := 2.0     # seconds for one ring to travel 0 → MAX_R
const WIDTH      := 3.0     # stroke width (px)
const SEGMENTS   := 48      # arc resolution — plenty at this radius, cheap
const PEAK_ALPHA := 0.75    # alpha of a freshly-born ring; fades to 0 as it expands

## Palette shortcuts for the two current callers, so the colours live in one place rather than being
## re-typed per map layer.
const GOLD     := Color(1.0, 0.85, 0.35)   # chest — matches arena_chest.gd's own GOLD exactly
const SEA_BLUE := Color(0.15, 0.6, 1.0)    # rescue landmark — "màu xanh nước biển"

var color: Color = GOLD
var max_r: float = MAX_R

var _t: float = 0.0

## Optional — a caller that just wants the default gold at the default radius can skip this entirely.
func setup(p_color: Color, p_max_r: float = MAX_R) -> void:
	color = p_color
	max_r = p_max_r
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	for i in RING_COUNT:
		# Each ring runs the same 0→1 cycle, offset by an even fraction of the period, so the ripple is
		# continuous instead of pulsing all rings at once. fposmod (not fmod) so this stays correct if _t is
		# ever driven negative.
		var phase := fposmod(_t / PERIOD + float(i) / float(RING_COUNT), 1.0)
		var r := max_r * phase
		if r < 1.0:
			continue   # a sub-pixel ring just renders as a dot at the centre
		# Fade faster than linearly: a ring should read as "already gone" well before it reaches max_r,
		# otherwise the outermost ring visually competes with the freshly-born one.
		var a := PEAK_ALPHA * pow(1.0 - phase, 1.5)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, SEGMENTS, Color(color.r, color.g, color.b, a), WIDTH, true)
