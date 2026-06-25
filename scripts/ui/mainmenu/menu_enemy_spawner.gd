extends Node
## Decorative flying-enemy backdrop for the Main Menu.
##
## Reuses the REAL arena enemy AI (arena_enemy.gd + arena_enemy_manager.gd) so attackers
## (shooter / beamer / bomber / missile …) fire exactly as they do in game. Enemies enter
## from the top and descend toward an off-screen dummy "player" target, then are culled at
## the bottom. NO bosses (behavior "boss_stub") and no test dummy are spawned.
##
## Damage to GameManager is neutralised via activate_shield() (re-armed each frame) so this
## cosmetic backdrop can never dent the next run's HP — arena.gd's reset_run() clears the
## flag the instant a real run starts, so it can't leak in.
##
## Enemy nodes are added straight into the menu's object container (the F4 edit
## ObjectsContainer) at z=ENEMY_Z — above the starfield, below the Logo / buttons — and are
## PAUSABLE so they freeze while the F4 editor has the tree paused. Brightness/contrast is
## graded per-item via a canvas_item shader on COLOR (NOT a CanvasGroup — that ignored the
## sibling z-order and drew over the whole menu).

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const MgrScript   := preload("res://scripts/gameplay/arena_enemy_manager.gd")
const WaveDir     := preload("res://scripts/gameplay/arena_wave_director.gd")

const ENEMY_Z        := 3        # over space (z=1), under Logo (z=5) / buttons (z=10)
const BULLET_Z       := 2
const ENEMY_SCALE    := 0.5      # menu-only: enemies drawn at 50%
const FX_BRIGHTNESS  := -0.12    # menu-only: dim the enemy layer a touch
const FX_CONTRAST    := 1.40     # menu-only: punch up contrast

# Per-CanvasItem brightness/contrast grade. Operates on the built-in COLOR (already
# texture×modulate) so it works for textured sprites AND for the manager's draw_circle/
# draw_line bullets, and — unlike a CanvasGroup — keeps each item's own z-index.
const GRADE_SHADER := """
shader_type canvas_item;
uniform float brightness = -0.12;
uniform float contrast = 1.4;
void fragment() {
	COLOR.rgb = clamp((COLOR.rgb - 0.5) * contrast + 0.5 + brightness, 0.0, 1.0);
}
"""
# Same grade but additive — for the missile volley, which relies on additive blending.
const GRADE_ADD_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform float brightness = -0.12;
uniform float contrast = 1.4;
void fragment() {
	COLOR.rgb = clamp((COLOR.rgb - 0.5) * contrast + 0.5 + brightness, 0.0, 1.0);
}
"""

# Menu-only audio bus: enemy sounds are rerouted here and treated to read as a faint,
# far-off echo — low-pass (high freq cut), reverb (distance/echo), and lower volume.
const MENU_BUS       := "MenuEnemySFX"
const BUS_VOLUME_DB  := -17.0
const LP_CUTOFF_HZ   := 1500.0   # cut highs → muffled/distant
const RV_ROOM        := 0.85
const RV_WET         := 0.55
const RV_DRY         := 0.5
const RV_PREDELAY_MS := 110.0

const SPAWN_INTERVAL := 0.8
const MAX_ALIVE      := 10    # total enemies on the menu never exceeds this
const PER_TYPE_MAX   := 2     # at most this many of any one enemy type alive at once
const PRESPAWN       := 4
const CULL_MARGIN    := 180.0
const MAX_LIFETIME   := 24.0
const TARGET_DROP    := 3000.0   # how far below the screen the aim target sits

# Spider is rationed: at most ONE on screen, it despawns after SPIDER_TTL, then no spider may
# spawn again for SPIDER_COOLDOWN.
const SPIDER_ID       := "spider"
const SPIDER_TTL      := 5.0
const SPIDER_COOLDOWN := 5.0

var _container: Control = null
var _mgr: Node2D  = null
var _target: Node2D = null
var _grade_mat: ShaderMaterial = null       # mix-blend grade (enemies + bullets)
var _grade_add_mat: ShaderMaterial = null   # additive grade (missile volley)
var _types: Array = []
var _enemies: Array = []   # [{node, type, age, ttl, off}]
var _acc: float = 0.0
var _vp: Vector2 = Vector2(1440, 780)
var _spider: Node = null       # the single live spider (null when none)
var _spider_cd: float = 0.0    # >0 → spider spawning blocked

func setup(container: Control) -> void:
	_container = container

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_vp = get_viewport().get_visible_rect().size
	if _container == null:
		return
	_arm_shield()
	_setup_audio_bus()
	_grade_mat     = _make_grade(GRADE_SHADER)
	_grade_add_mat = _make_grade(GRADE_ADD_SHADER)
	# Dummy aim target far below center → enemies descend across the screen; shooters fire down.
	_target = Node2D.new()
	_target.add_to_group("player")
	_target.position = Vector2(_vp.x * 0.5, _vp.y + TARGET_DROP)
	_container.add_child(_target)
	# Enemy services (bullet/explosion pool). Pausable so it freezes with the F4 editor.
	_mgr = MgrScript.new()
	_mgr.process_mode = Node.PROCESS_MODE_PAUSABLE
	_container.add_child(_mgr)
	_mgr.z_index = BULLET_Z
	_mgr.material = _grade_mat   # grade the enemy bullets the manager draws
	# Spawnable set = every enemy that is not a boss stub and not the test dummy.
	for id: String in WaveDir.ENEMY_DEFS.keys():
		var d: Dictionary = WaveDir.ENEMY_DEFS[id]
		if String(d.get("behavior", "")) == "boss_stub" or id == "dummy":
			continue
		_types.append(id)
	# Populate immediately so the menu isn't empty on first paint.
	for i in PRESPAWN:
		_spawn_one(randf_range(-40.0, _vp.y * 0.55))

## Create the menu's "distant echo" audio bus once (idempotent — survives menu re-entry).
## Routes to the SFX bus (so the SFX volume slider still applies) or Master as a fallback.
func _setup_audio_bus() -> void:
	if AudioServer.get_bus_index(MENU_BUS) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, MENU_BUS)
	AudioServer.set_bus_send(idx, "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master")
	AudioServer.set_bus_volume_db(idx, BUS_VOLUME_DB)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = LP_CUTOFF_HZ
	AudioServer.add_bus_effect(idx, lp)
	var rv := AudioEffectReverb.new()
	rv.room_size    = RV_ROOM
	rv.wet          = RV_WET
	rv.dry          = RV_DRY
	rv.predelay_msec = RV_PREDELAY_MS
	rv.spread       = 1.0
	AudioServer.add_bus_effect(idx, rv)

func _make_grade(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("brightness", FX_BRIGHTNESS)
	mat.set_shader_parameter("contrast", FX_CONTRAST)
	return mat

func _process(delta: float) -> void:
	_arm_shield()
	if _spider_cd > 0.0:
		_spider_cd = maxf(0.0, _spider_cd - delta)
	# Cull off-screen / aged-out enemies.
	var i := _enemies.size() - 1
	while i >= 0:
		var e: Dictionary = _enemies[i]
		var n = e["node"]
		if not is_instance_valid(n):
			if n == _spider:
				_spider = null
				_spider_cd = SPIDER_COOLDOWN
			_enemies.remove_at(i)
		else:
			e["age"] = float(e["age"]) + delta
			var gp: Vector2 = (n as Node2D).global_position
			var off: bool = bool(e["off"]) and (gp.y > _vp.y + CULL_MARGIN or gp.x < -CULL_MARGIN or gp.x > _vp.x + CULL_MARGIN)
			if off or float(e["age"]) >= float(e["ttl"]):
				if n == _spider:
					_spider = null
					_spider_cd = SPIDER_COOLDOWN
				n.queue_free()
				_enemies.remove_at(i)
		i -= 1
	# Spawn.
	_acc += delta
	if _acc >= SPAWN_INTERVAL and _enemies.size() < MAX_ALIVE:
		_acc = 0.0
		_spawn_one(-60.0)
	_fix_projectiles()

## Pin enemy projectiles to the menu enemy layer (z) and grade them. Missile volleys (Node2D
## children of the manager) and thrown bombs otherwise float above the Logo / buttons and
## render ungraded.
func _fix_projectiles() -> void:
	if _mgr != null and is_instance_valid(_mgr):
		for c in _mgr.get_children():
			if c is Node2D:
				var n2 := c as Node2D
				if n2.z_as_relative or n2.z_index != ENEMY_Z:
					n2.z_as_relative = false
					n2.z_index = ENEMY_Z
				if n2.material != _grade_add_mat:
					n2.material = _grade_add_mat   # missile volley (additive)
	for en in get_tree().get_nodes_in_group("arena_enemy"):
		if en is Node2D:
			var n3 := en as Node2D
			if n3.z_index != ENEMY_Z:
				n3.z_index = ENEMY_Z
			if n3.material != _grade_mat:
				n3.material = _grade_mat   # covers thrown bombs the manager spawns
			if "sfx_bus" in n3 and n3.get("sfx_bus") != MENU_BUS:
				n3.set("sfx_bus", MENU_BUS)   # route their boom SFX to the echo bus too

func _arm_shield() -> void:
	# Keep the (nonexistent) menu ship immune; short duration so it lapses right after we leave.
	if GameManager.has_method("activate_shield"):
		GameManager.activate_shield(2.0)

func _spider_allowed() -> bool:
	return (_spider == null or not is_instance_valid(_spider)) and _spider_cd <= 0.0

func _spawn_one(y: float) -> void:
	if _types.is_empty() or _container == null or _mgr == null:
		return
	# Pool = types under PER_TYPE_MAX alive; spider is additionally rationed (≤1 + cooldown).
	var counts: Dictionary = {}
	for en: Dictionary in _enemies:
		var t: String = en.get("type", "")
		counts[t] = int(counts.get(t, 0)) + 1
	var pool: Array = []
	for t: String in _types:
		if t == SPIDER_ID:
			if _spider_allowed():
				pool.append(t)
		elif int(counts.get(t, 0)) < PER_TYPE_MAX:
			pool.append(t)
	if pool.is_empty():
		return
	var id: String = pool[randi() % pool.size()]
	var def: Dictionary = (WaveDir.ENEMY_DEFS[id] as Dictionary).duplicate()
	def["xp"] = 0    # no XP orbs cluttering the menu (enemies never die here anyway)
	var e := EnemyScript.new()
	e.process_mode = Node.PROCESS_MODE_PAUSABLE
	e.configure(id, _mgr, def)
	e.sfx_bus = MENU_BUS   # route its attack sounds to the faint, far-off echo bus
	e.position = Vector2(randf_range(60.0, _vp.x - 60.0), y)
	_container.add_child(e)
	e.z_index = ENEMY_Z
	e.scale = Vector2(ENEMY_SCALE, ENEMY_SCALE)   # menu-only 50% (movement uses global_position, unaffected)
	e.material = _grade_mat                        # brightness/contrast grade (overrides the unused hit-flash mat)
	var is_spider := id == SPIDER_ID
	if is_spider:
		_spider = e
	# Spider: fixed 5s life, never culled early off-screen. Others: long life + off-screen cull.
	_enemies.append({"node": e, "type": id, "age": 0.0,
		"ttl": SPIDER_TTL if is_spider else float(MAX_LIFETIME),
		"off": not is_spider})
