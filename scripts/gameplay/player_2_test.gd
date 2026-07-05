extends Node2D
## Standalone sandbox to test the Player 2 companion (scenes/player_2_test.tscn).
##  • WASD / arrows move your ship; it faces the mouse.
##  • Press F12 for the DEV WEAPON PALETTE — click any weapon; it becomes the main ship's weapon and Player 2
##    re-spawns copying it at 25%. (The test keeps exactly one weapon so P2 always copies what you just picked.)
##  • A ring of respawning target dummies gives both ships something to shoot.
## This is a test harness, not the real arena; it builds everything in _ready().

const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")
const PaletteScript      := preload("res://scripts/gameplay/arena_weapon_palette.gd")
const SHIP_SPRITE := "res://assets/screen/Spaceship.png"
const MOVE_SPEED  := 260.0

var _player: Node2D = null
var _weapons: Node = null
var _hud: Label = null
var _last_kind: String = ""

func _ready() -> void:
	position = Vector2.ZERO
	_build_player()
	_build_hud()
	# Main weapon system (NOT companion).
	_weapons = ArenaWeaponsScript.new()
	(_weapons as Node2D).position = Vector2.ZERO
	add_child(_weapons)
	# Dev weapon palette (F12 toggles it). Picking a weapon spawns a pickup the ship collects → acquire_weapon().
	add_child(PaletteScript.new())
	_spawn_targets(6, 300.0)
	# Start with a Gatling so something fires on boot; _sync_from_loadout() turns it into the test weapon + spawns P2.
	_weapons.call_deferred("acquire_weapon", "gatling")

func _build_player() -> void:
	_player = Node2D.new()
	_player.add_to_group("player")
	_player.global_position = Vector2.ZERO
	var spr := Sprite2D.new()
	var tex := load(SHIP_SPRITE) as Texture2D
	spr.texture = tex
	var longest := maxf(float(tex.get_width()), float(tex.get_height())) if tex != null else 1.0
	spr.scale = Vector2.ONE * (48.0 / maxf(1.0, longest))
	spr.z_index = 60
	_player.add_child(spr)
	var cam := Camera2D.new()
	cam.enabled = true
	_player.add_child(cam)
	add_child(_player)
	cam.make_current()

func _spawn_targets(n: int, radius: float) -> void:
	for i in n:
		var a := TAU * float(i) / float(n)
		var t := TargetDummy.new()
		t.global_position = Vector2(cos(a), sin(a)) * radius
		add_child(t)

func _process(delta: float) -> void:
	if _player == null:
		return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  v.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1.0
	if v.length() > 0.0:
		_player.global_position += v.normalized() * MOVE_SPEED * delta
	var to_mouse := get_global_mouse_position() - _player.global_position
	if to_mouse.length() > 1.0:
		_player.rotation = to_mouse.angle() + PI * 0.5   # sprite up (-Y) = forward
	_sync_from_loadout()

## When a NEW weapon is acquired (via the palette), make it the sole test weapon and re-spawn Player 2 copying it.
func _sync_from_loadout() -> void:
	if _weapons == null:
		return
	var owned: Array = _weapons.call("acquired_weapons")
	var picked := ""
	for k in owned:
		if String(k) != "player_2" and String(k) != _last_kind:
			picked = String(k)   # take the newest kind that isn't already the test weapon
	if picked != "":
		_set_test_weapon(picked)

func _set_test_weapon(kind: String) -> void:
	_last_kind = kind
	if _weapons.has_method("despawn_player2"):
		_weapons.call("despawn_player2")
	if _weapons.has_method("clear_all_weapons"):
		_weapons.call("clear_all_weapons")   # keep exactly one weapon so P2 copies THIS pick
	_weapons.call("acquire_weapon", kind)
	if _weapons.has_method("force_spawn_player2"):
		_weapons.call_deferred("force_spawn_player2")
	if _hud != null:
		_hud.text = "F12 = dev weapon palette — pick a weapon; Player 2 copies it\nCurrent: %s   ·   WASD move · mouse aim\nPlayer 2 = negative ship, fires a 25%% copy" % kind

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.text = "F12 = dev weapon palette\nWASD move · mouse aim"
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)

## Minimal target: a respawning-HP circle in the "arena_enemy" group so the weapon systems can acquire + hit it.
class TargetDummy extends Node2D:
	var hit_radius: float = 18.0
	var _hp: float = 300.0
	var _flash: float = 0.0

	func _ready() -> void:
		add_to_group("arena_enemy")

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - delta)
			queue_redraw()

	func is_dead() -> bool:
		return false

	func take_damage(amount: float, _stagger: float = 0.0, _knock: float = 0.0, _ignore_armor: bool = false, _bleeds: bool = false, _was_crit: bool = false, _kind: String = "") -> void:
		_hp -= amount
		_flash = 0.12
		if _hp <= 0.0:
			_hp = 300.0   # never die — keep the targets around for testing
		queue_redraw()

	func _draw() -> void:
		var c := Color(1.0, 0.5, 0.3) if _flash > 0.0 else Color(0.8, 0.3, 0.3)
		draw_circle(Vector2.ZERO, hit_radius, Color(c.r, c.g, c.b, 0.85))
		draw_arc(Vector2.ZERO, hit_radius, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 2.0, true)
