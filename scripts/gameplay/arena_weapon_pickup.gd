extends Node2D
## A collectible weapon pickup (Gatling / Gauss / Lasgun / Arc). Floats in place with a bob + pulsing glow so
## it reads as "grab me". Collected when the player flies within COLLECT_RANGE (its OWN fixed range — a weapon
## shouldn't magnetize across the screen like an XP orb). On collection it auto-equips the weapon by telling
## arena_weapons to activate it (activate_<kind>), pops, and frees. Gameplay plane (sharp, not blurred).

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SIZE          := 14.0                       # icon radius px
const GLOW          := 1.0                        # glow intensity
const COLLECT_RANGE := 46.0                        # fly within this to grab it
const BOB_AMP       := 4.0
const BOB_SPEED     := 2.2

# Per-kind look: crate/ring colour + an emblem style drawn across the crate. emblem: "beam" | "bolt" | "orb" | "tracer".
const KIND_STYLE := {
	"death_beam":  {"color": Color(1.0, 0.55, 0.22), "ring": Color(1.0, 0.8, 0.4),  "emblem": "beam"},
	"arc":     {"color": Color(0.55, 0.8, 1.0),  "ring": Color(0.7, 0.9, 1.0),  "emblem": "bolt"},
	"gauss":   {"color": Color(0.4, 0.7, 1.0),   "ring": Color(0.7, 0.9, 1.0),  "emblem": "orb"},
	"gatling": {"color": Color(1.0, 0.82, 0.25), "ring": Color(1.0, 0.9, 0.5),  "emblem": "tracer"},
	"orbital": {"color": Color(0.65, 0.78, 0.95), "ring": Color(0.8, 0.9, 1.0), "emblem": "orb"},
	"striker": {"color": Color(1.0, 0.45, 0.15),  "ring": Color(1.0, 0.68, 0.45), "emblem": "orb"},
	"shooter": {"color": Color(1.0, 0.66, 0.22),  "ring": Color(1.0, 0.82, 0.45), "emblem": "orb"},
	"void":    {"color": Color(0.7, 0.4, 1.0),    "ring": Color(0.85, 0.7, 1.0), "emblem": "orb"},
	"red_x":   {"color": Color(1.0, 0.35, 0.3),   "ring": Color(1.0, 0.6, 0.5),  "emblem": "bolt"},
	"chemtrail": {"color": Color(0.6, 0.95, 0.45),"ring": Color(0.8, 1.0, 0.6),  "emblem": "orb"},
	"little_man":    {"color": Color(1.0, 0.75, 0.35),  "ring": Color(1.0, 0.9, 0.6),  "emblem": "orb"},
	"ultrasonicator":   {"color": Color(0.55, 0.85, 1.0),  "ring": Color(0.75, 0.95, 1.0),"emblem": "orb"},
	"z_sword":  {"color": Color(0.7, 1.0, 0.85),   "ring": Color(0.85, 1.0, 0.95),"emblem": "beam"},
	"ionizing_field":  {"color": Color(0.6, 0.9, 1.0),    "ring": Color(0.8, 0.97, 1.0), "emblem": "bolt"},
	"aliwa": {"color": Color(0.95, 0.85, 0.5),"ring": Color(1.0, 0.95, 0.7), "emblem": "tracer"},
	"venomancer":  {"color": Color(0.6, 0.95, 0.45),"ring": Color(0.8, 1.0, 0.6),  "emblem": "orb"},
	"yari":   {"color": Color(0.8, 0.7, 1.0),  "ring": Color(0.9, 0.85, 1.0), "emblem": "orb"},
	"yari_jaeger": {"color": Color(0.9, 0.65, 1.0), "ring": Color(0.95, 0.8, 1.0), "emblem": "beam"},
	"swarm":       {"color": Color(0.95, 0.6, 0.85), "ring": Color(1.0, 0.8, 0.95), "emblem": "tracer"},
	"viper":       {"color": Color(1.0, 0.6, 0.3),   "ring": Color(1.0, 0.8, 0.5),  "emblem": "beam"},
}
const DEFAULT_STYLE := {"color": Color(0.8, 0.8, 0.8), "ring": Color(0.95, 0.95, 0.95), "emblem": "beam"}

var _kind: String = "death_beam"
var _t := 0.0
var _player: Node2D = null
var _popping := false
var _pop_t := 0.0

func setup(world_pos: Vector2, kind: String) -> void:
	global_position = world_pos
	_kind = kind
	_t = randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	if _popping:
		_pop_t += delta
		queue_redraw()
		if _pop_t >= 0.25:
			queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and global_position.distance_to(_player.global_position) <= COLLECT_RANGE:
		_collect()
	queue_redraw()

func _style() -> Dictionary:
	return KIND_STYLE.get(_kind, DEFAULT_STYLE)

func _collect() -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons != null and weapons.has_method("acquire_weapon"):
		weapons.call("acquire_weapon", _kind)   # fills a slot (cap-respecting) + activates the weapon
	elif weapons != null and weapons.has_method("activate_" + _kind):
		weapons.call("activate_" + _kind)        # fallback
	_popping = true
	_pop_t = 0.0

func _draw() -> void:
	var st := _style()
	var col: Color = st["color"]
	var ring: Color = st["ring"]
	if _popping:
		var pt := clampf(_pop_t / 0.25, 0.0, 1.0)
		var r := SIZE * (1.0 + pt * 3.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(ring.r, ring.g, ring.b, (1.0 - pt) * 0.8), 3.0)
		return
	var bob := sin(_t * BOB_SPEED) * BOB_AMP
	var c := Vector2(0.0, bob)
	var pulse := 0.8 + 0.2 * sin(_t * BOB_SPEED * 1.6)
	# Glow halo.
	draw_circle(c, SIZE * 2.0 * pulse, Color(col.r, col.g, col.b, 0.12 * GLOW))
	draw_circle(c, SIZE * 1.35 * pulse, Color(col.r, col.g, col.b, 0.25 * GLOW))
	# Crate diamond.
	var d := SIZE
	var pts := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
	draw_colored_polygon(pts, Color(0.12, 0.10, 0.14, 0.9))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), ring, 2.0)
	_draw_emblem(c, d, col, pulse, String(st["emblem"]))

## Weapon-flavoured glyph across the crate face.
func _draw_emblem(c: Vector2, d: float, col: Color, pulse: float, emblem: String) -> void:
	var bright := Color(col.r, col.g, col.b, 0.9)
	match emblem:
		"bolt":
			# Zig-zag lightning bolt (Arc).
			var pp := PackedVector2Array([
				c + Vector2(-d * 0.35, -d * 0.55), c + Vector2(d * 0.1, -d * 0.1),
				c + Vector2(-d * 0.1, d * 0.1),    c + Vector2(d * 0.35, d * 0.55)])
			draw_polyline(pp, bright, 3.0 * pulse)
			draw_polyline(pp, Color(1, 1, 1, 0.9), 1.0)
		"orb":
			# Filled plasma ball (Gauss).
			draw_circle(c, d * 0.45 * pulse, bright)
			draw_circle(c, d * 0.22 * pulse, Color(1, 1, 1, 0.9))
		"tracer":
			# Twin vertical tracer streaks (Gatling).
			for sx: float in [-0.3, 0.3]:
				draw_line(c + Vector2(d * sx, -d * 0.55), c + Vector2(d * sx, d * 0.55), bright, 3.0 * pulse)
		_:
			# "beam": a short bright horizontal streak (Lasgun).
			draw_line(c + Vector2(-d * 0.6, 0), c + Vector2(d * 0.6, 0), bright, 3.0 * pulse)
			draw_line(c + Vector2(-d * 0.6, 0), c + Vector2(d * 0.6, 0), Color(1, 1, 1, 0.9), 1.0)
