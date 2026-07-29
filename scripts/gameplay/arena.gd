extends Node2D
## Arena — world-space foundation for the survival pivot (Phase 1). Builds, in code: a Player
## (CharacterBody2D) with the ship sprite + a follow Camera2D, WASD movement, mouse auto-aim, placeholder
## auto-fire, and an infinite multi-layer parallax starfield. NOTHING is ported from the old game yet
## (inventory/weapons/bosses/enemies/affixes come later). All knobs are in the TUNABLES block below.

const HudHpDisplayScript := preload("res://scripts/ui/hud/hud_hp_display.gd")
const VitalsBarScript    := preload("res://scripts/ui/hud/arena_vitals_bar.gd")  # player + boss vitals bars
const HudFrameScript     := preload("res://scripts/ui/hud/arena_hud_frame.gd")   # procedural cockpit bezels
const ScreenFxScript     := preload("res://scripts/gameplay/arena_screen_fx.gd") # edge vignette + player hit flash
const ArenaStatsHudScript := preload("res://scripts/ui/hud/arena_stats_hud.gd")
const ArenaEnemyMgrScript := preload("res://scripts/gameplay/arena_enemy_manager.gd")
const XpOrbMgrScript      := preload("res://scripts/gameplay/arena_xp_orb_manager.gd")
const PlumeMgrScript      := preload("res://scripts/gameplay/arena_plume_manager.gd")
const WaveDirectorScript := preload("res://scripts/gameplay/arena_wave_director.gd")
const TestTemplateScript := preload("res://scripts/gameplay/test_template.gd")
const WaveEditorScript   := preload("res://scripts/ui/hud/arena_wave_editor.gd")
const USE_TEST_SPAWNER   := false   # true → use test_template.gd (spawn one enemy every 5s) instead of the timeline
const ArenaWeaponsScript := preload("res://scripts/gameplay/arena_weapons.gd")
const ArenaAuxScript     := preload("res://scripts/gameplay/arena_aux.gd")           # auxiliary (passive) item data layer
const CamShakeScript     := preload("res://scripts/gameplay/arena_camera_shake.gd")  # follow camera + screen-shake
const ChestScript        := preload("res://scripts/gameplay/arena_chest.gd")          # far reward chest (level-up reward, no level)
const ChestPointerScript := preload("res://scripts/ui/hud/arena_chest_pointer.gd")    # edge-of-screen spinning arrow + distance
const ArenaNebulaScript  := preload("res://scripts/gameplay/arena_nebula.gd")
const ArenaDustScript    := preload("res://scripts/gameplay/arena_dust.gd")
const ArenaPlanetsScript := preload("res://scripts/gameplay/arena_planets.gd")
const ArenaAsteroidsScript := preload("res://scripts/gameplay/arena_asteroids.gd")
const ArenaCometsScript    := preload("res://scripts/gameplay/arena_comets.gd")
const ArenaStructuresScript := preload("res://scripts/gameplay/arena_structures.gd")
const ArenaSolarSystemScript := preload("res://scripts/gameplay/arena_solar_system.gd")
const ArenaDofScript     := preload("res://scripts/gameplay/arena_dof.gd")
const PlanetMenuScript   := preload("res://scripts/ui/hud/arena_planet_menu.gd")
const DebugSpawnScript   := preload("res://scripts/gameplay/arena_debug_spawn.gd")
const PerfOverlayScript  := preload("res://scripts/ui/hud/perf_overlay.gd")
const RunClockScript     := preload("res://scripts/ui/hud/arena_run_clock.gd")   # top-right run timer (pauses with the tree)
const LevelUpUIScript    := preload("res://scripts/ui/hud/arena_levelup_ui.gd")
const FusionCutsceneScript := preload("res://scripts/gameplay/arena_fusion_cutscene.gd")  # weapon-fusion cutscene
const InventoryUIScript  := preload("res://scripts/ui/inventory/inventory_ui.gd")   # equip screen (I key)
const DropUIScript       := preload("res://scripts/ui/hud/arena_drop_ui.gd")          # boss-defeated salvage choice
const WeaponChestScript  := preload("res://scripts/ui/hud/arena_weapon_chest_ui.gd")  # start-of-run pick-1-of-3 chest
const WeaponSlotsScript  := preload("res://scripts/ui/hud/arena_weapon_slots.gd")     # 5-slot weapon HUD + cooldown pies
const AuxSlotsScript     := preload("res://scripts/ui/hud/arena_aux_slots.gd")         # 5-slot aux-item HUD (row below weapons)
const ArenaRuinLayerScript := preload("res://scripts/gameplay/arena_ruin_layer.gd")
const ArenaHudButtonsScript := preload("res://scripts/ui/hud/arena_hud_buttons.gd")
const BossEditScript        := preload("res://scripts/ui/boss_edit/boss_edit_mode.gd")
const CreepEditScript       := preload("res://scripts/ui/boss_edit/creep_edit_mode.gd")
const WeaponEditScript      := preload("res://scripts/ui/boss_edit/weapon_edit_mode.gd")
const FleetEditScript       := preload("res://scripts/ui/boss_edit/fleet_edit_mode.gd")
const HudEditScript         := preload("res://scripts/ui/boss_edit/hud_edit_mode.gd")   # authored playerhud (the active HUD)
const SettingsScript        := preload("res://scripts/ui/settings/settings_panel.gd")
const RESET_RUN_ON_START := true   # each arena run starts a fresh VS climb (level 1, no upgrades). Flip off to keep saved level.
const WEAPON_TEST_MODE := true     # TEST: skip the hub launch page + start-of-run weapon-pick chest; boot straight into
								   # the arena, then auto-pause and open the F12 weapon palette. Flip off to restore normal flow.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const SHIP_SPRITE     := "res://assets/screen/Spaceship.png"   # legacy 2D art (unused now; 3D model replaces it)
const SHIP_MODEL         := "res://assets/defense/Ship_model_1.glb"   # 3D ship rendered into a SubViewport
const VP_SIZE            := 256               # SubViewport render resolution for the ship
const SHIP_DISPLAY_GAIN  := 3.5               # size fudge so the framed model fills ~PLAYER_SIZE_PX (tune to taste)
const SHIP_ISO_DEG       := 30.0             # camera tilt from top-down (0 = flat top-down, ~30 = isometric)
const SHIP_LEAN_MAX_DEG  := 18.0             # gentle bank into turns (0 = never lean)
const SHIP_YAW_SIGN      := 1.0              # flip to -1.0 if the ship turns opposite the mouse
const SHIP_INVERT_SIDES  := -1.0             # lean direction — flip to +1.0 if it leans the wrong way
const MUZZLE_CFG         := "res://ship_muzzles.cfg"   # muzzle anchor points placed in ship_rotation_test
const CAM_ZOOM        := Vector2(1.0, 1.0)   # >1 zooms in, <1 zooms out
const PLAYER_SIZE_PX  := 48.0                 # ship drawn this many px on its longest side (scaled from the texture)
const PLAYER_RADIUS   := 16.0                 # collision circle radius (for later)
const SHIP_Z          := 100                  # ship draws ABOVE all world effects (weapon FX ≤6, explosions, enemies) so it's never hidden
const MOVE_SPEED      := 320.0                # px/s
const SQUID_CLING_SLOW_FLOOR := 0.10          # clinging squids can't drag move speed below this (keeps the ship mobile)
const TURN_INSTANT    := false               # true = snap to face mouse; false = eased turn
const TURN_SPEED      := 12.0                 # eased turn rate (higher = snappier)
const FIRE_INTERVAL   := 0.25                 # s between auto-fire shots
const PROJ_SPEED      := 700.0               # px/s
const PROJ_LIFETIME   := 1.5                  # s before a projectile despawns
const PROJ_MAX_DIST   := 1400.0              # px travelled before despawn (whichever first)
const PROJ_COLOR      := Color(1.0, 0.95, 0.55)
const PROJ_DAMAGE     := 10.0               # damage each projectile deals to an enemy on hit
const PROJ_HIT_RADIUS := 22.0               # projectile↔enemy hit distance (px)
const USE_PLACEHOLDER_FIRE := false         # Phase-3: real weapons (arena_weapons.gd) replace the throwaway dart
# Parallax star layers (far → near): [parallax factor, tile size, star count, dot size, brightness]
const STAR_LAYERS := [
	[0.03, 1024, 130, 1.0, 0.55],   # far, faint, sparse  (deep parallax — slow drift)
	[0.06, 1024, 90,  1.5, 0.8],    # mid
	[0.10, 1024, 55,  2.0, 1.0],    # near, bright (still deep; nothing at surface but ship/enemies)
]
# Solar-system start + soft boundary (world space; the player flies the world, the system orbits origin).
const PLAYER_START   := Vector2(0.0, -1100.0)   # offset from origin so the player doesn't spawn on the sun
const SOFT_BOUNDARY  := 9000.0                   # past Neptune's reach; gentle inward drift begins here
const HARD_BOUNDARY  := 10500.0                  # absolute clamp (player can't pass) — IGNORED when LIMITLESS
const LIMITLESS      := true                     # true = no map edge (fly forever); false = bounded disc (soft drift + hard clamp)
const CHEST_DIST     := 10000.0                  # reward chest spawns this far from the player's start
const BOUNDARY_PULL  := 2.2                      # inward drift past the soft edge (per second × overshoot px)
const VIGNETTE_FADE  := 2200.0                   # distance the edge vignette fades in over, before SOFT
const BOUNDARY_VIGNETTE_SHADER := "res://assets/shaders/boundary_vignette.gdshader"

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player: CharacterBody2D = null
var _ship_spr: Sprite2D = null            # now displays the 3D ship SubViewport texture (rotates to aim)
var _ship_vp: SubViewport = null          # renders the 3D model top-down
var _ship_pivot: Node3D = null            # model parent — rolled each frame to bank the ship
var _ship_cam: Camera3D = null
var _muzzle_anchors: Dictionary = {}      # slot:int -> Node3D on the model (rides the ship's 3D orientation)
var _player_shape: CircleShape2D = null   # collision circle (Juggernaut scales its radius)
var _applied_size_mult: float = 1.0       # last ship-size mult applied (Juggernaut nerf)
var _tex_normal: Texture2D = null
var _tex_lean: Texture2D = null
var _fire_acc: float = 0.0
var _projectiles: Array = []   # {node, vel, life, start}
var _edge_vignette_mat: ShaderMaterial = null   # boundary "edge of system" cue
var _enemy_mgr: Node = null   # arena_enemy_manager (smart/defend thruster bullet queries)
var _boss_edit:  Node = null
var _creep_edit: Node = null
var _weapon_edit: Node = null
var _hud_edit:   Node = null     # authored playerhud (live HUD when closed; F-button opens the editor)
var _weapon_chest: Node = null   # start-of-run weapon chest UI
var _ui_layer: CanvasLayer = null      # HP / weapon / aux / XP HUD layer (hidden while a full-screen editor is open)
var _hud_buttons: Node = null          # bottom-right + left dev button clusters

func _ready() -> void:
	add_to_group("arena")                # editors find the arena to hide the HUD while editing
	randomize()                          # fresh RNG each launch → random spawn spot (below)
	if MetaManager.has_method("purge_run_temp"):
		MetaManager.purge_run_temp()     # clear last run's temporary boss-drop loot
	if RESET_RUN_ON_START and GameManager.has_method("reset_run"):
		GameManager.reset_run()          # fresh VS climb: level 1, no upgrades, full HP
		if typeof(MetaManager) != TYPE_NIL and MetaManager.has_method("apply_run_start"):
			MetaManager.apply_run_start()   # fold permanent passives into this run
	# Run ends → back to the hub (death; rebirth charges are consumed first).
	if GameManager.has_signal("ship_destroyed"):
		GameManager.ship_destroyed.connect(_on_run_ended)
	# Depth-of-field: all non-gameplay layers render into the DoF SubViewport (blurred/dimmed/desaturated
	# behind the sharp gameplay plane). bg is that SubViewport; parallax/streaming are unchanged because its
	# camera is synced to the main camera each frame.
	var dof := ArenaDofScript.new()
	add_child(dof)
	var bg: Node = dof.background_parent()   # DoF SubViewport, or the arena itself when the mask is disabled
	add_child(ArenaNebulaScript.new())      # procedural nebula — EXCLUDED from the blur (stays sharp in the
											# main viewport at CL -10, behind the DoF composite at CL -5)
	bg.add_child(ArenaDustScript.new())     # dark space dust, lit by ship/weapon lights
	var planets := ArenaPlanetsScript.new()      # sparse mid-parallax procedural planets (z -50)
	var comets := ArenaCometsScript.new()        # rare mid-parallax comets (z -48)
	var structures := ArenaStructuresScript.new() # rare huge gas/dust structures (z -60, slow far parallax)
	var asteroids := ArenaAsteroidsScript.new()  # fast near-parallax asteroid fields (z -10, sells speed)
	# Authored solar system (replaces random planet scatter): planets/belt on the blurred 0.40 layer; its sun
	# is hosted in the MAIN viewport (sharp, excluded from the blur).
	var solar := ArenaSolarSystemScript.new()
	solar.sun_host = self
	if ArenaDofScript.ENABLED:               # per-layer depth dim only when the mask is on
		planets.modulate = ArenaDofScript.MID_MODULATE
		comets.modulate = ArenaDofScript.MID_MODULATE
		structures.modulate = ArenaDofScript.FAR_MODULATE
		asteroids.modulate = ArenaDofScript.MID_MODULATE
		solar.modulate = ArenaDofScript.MID_MODULATE
	bg.add_child(planets)                    # streaming OFF (helpers/F10 only); solar system provides planets
	bg.add_child(comets)
	bg.add_child(structures)
	bg.add_child(asteroids)
	bg.add_child(solar)
	add_child(PlanetMenuScript.new())    # F6 menu: inspect/drag-spawn planets (input stays in the main viewport)
	add_child(DebugSpawnScript.new())    # F5 asteroids / F9 comet / F10 planet+moons (Shift = clear)
	_hud_buttons = ArenaHudButtonsScript.new()  # bottom-right HUD: Setting / Devon / Quit
	add_child(_hud_buttons)
	_build_parallax(bg)
	_build_player()
	_build_ui()
	_build_boundary_vignette()
	_spawn_reward_chest()                # far reward chest + edge-of-screen pointer
	add_child(_make_glow_world_env())    # screen glow/bloom (HDR-2D): makes the >1 fire (M2, Red X) bloom
	add_child(PerfOverlayScript.new())   # FPS/frame-ms readout (top-right); off by default, Settings' FPS switch shows it
	add_child(RunClockScript.new())      # top-right run timer (freezes while paused: menu / level-up)
	add_child(LevelUpUIScript.new())     # VS choose-1-of-3 on level-up (pauses the game)
	add_child(FusionCutsceneScript.new())  # weapon-fusion cutscene (group "arena_fusion_cutscene"; awaited by level-up UI)
	add_child(InventoryUIScript.new())   # equip/loadout screen (toggle with the I key)
	add_child(DropUIScript.new())        # boss-defeated salvage: equip (run) vs disassemble (blueprint)
	_weapon_chest = WeaponChestScript.new()   # start-of-run pick-1-of-3 weapon chest (opened deferred below)
	add_child(_weapon_chest)
	add_child(ArenaEnemyMgrScript.new())  # world-space enemy services (bullets, explosions, ship pos)
	add_child(XpOrbMgrScript.new())       # single MultiMesh node that renders+updates ALL xp orbs (group "arena_xp_orb_mgr")
	add_child(PlumeMgrScript.new())       # single MultiMesh node that renders ALL enemy plumes (group "arena_plume_mgr")
	if USE_TEST_SPAWNER:
		add_child(TestTemplateScript.new())   # quick test: one enemy every 5s
	else:
		add_child(WaveDirectorScript.new())   # authored-timeline wave spawner
		add_child(WaveEditorScript.new())     # F7 in-game wave editor (add/edit/remove waves live)
	add_child(ArenaWeaponsScript.new())   # bespoke 5-slot weapons (chest + F12 pickups) — the ONLY arena combat path
	add_child(ArenaAuxScript.new())       # auxiliary passive-item store (level-up offers; group "arena_aux")
	# arena_loadout (fires EQUIPPED inventory weapons) is intentionally NOT instantiated: combat is driven solely by
	# the bespoke 5-slot system, so equipped starter/inventory weapons no longer auto-fire in the arena.
	add_child(ArenaRuinLayerScript.new()) # 2 giant dead-ship wrecks at run start (drop orb of light)
	call_deferred("_setup_boss_edit")
	call_deferred("_setup_creep_edit")
	call_deferred("_setup_weapon_edit")
	call_deferred("_setup_fleet_edit")
	call_deferred("_setup_hud_edit")     # authored playerhud = the live HUD (replaces the hidden cockpit HUD)
	call_deferred("_grant_default_weapon")   # fresh run → skip the weapon-pick chest; start with the Gatling Gun

## Canvas glow/bloom for the arena. With hdr_2d on (project.godot) + glow_hdr_threshold 1.0, only HDR (>1)
## pixels bloom — i.e. the DynamicFire effects that set glow>0 (Elephant M2, Red X). LDR content is untouched.
func _make_glow_world_env() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# (bicubic upscale is the project setting rendering/environment/glow/upscale_mode in Godot 4, not an Env property)
	env.glow_hdr_threshold = 1.0    # only pixels brighter than 1.0 (HDR fire) bloom
	env.glow_intensity = 1.0
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	# Perf: cap the glow mip chain at level 2 (was 4). Each extra level is another downsample+blur+upsample pass;
	# stopping at 2 gives a tighter but much cheaper bloom on the HDR fire.
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.0)
	env.set_glow_level(4, 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	return we

## Present the start-of-run weapon chest. Deferred from _ready so the HUD/player exist first. (No longer called
## at boot — kept for reference; the ship now auto-equips the Gatling via _grant_default_weapon.)
func _open_start_chest() -> void:
	if _weapon_chest != null and is_instance_valid(_weapon_chest) and _weapon_chest.has_method("show_chest"):
		_weapon_chest.show_chest()

## Fresh run → no weapon selection: auto-equip the Gatling Gun. Deferred from _ready so the arena_weapons node
## (added this same frame) has run its _ready and joined group "arena_weapons".
func _grant_default_weapon() -> void:
	var weapons := get_tree().get_first_node_in_group("arena_weapons")
	if weapons != null and weapons.has_method("acquire_weapon"):
		weapons.call("acquire_weapon", "gatling_gun")

## WEAPON_TEST_MODE boot: no weapon-pick chest — auto-pause and open the F12 weapon palette instead.
func _open_weapon_test() -> void:
	var palette := get_tree().get_first_node_in_group("arena_weapon_palette")
	if palette != null and palette.has_method("open"):
		palette.open()

## Full-screen "edge of system" vignette; its intensity is driven by player→boundary proximity each frame.
func _build_boundary_vignette() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 90   # above gameplay, below the perf overlay (99) / settings (100)
	add_child(cl)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(BOUNDARY_VIGNETTE_SHADER)
	m.set_shader_parameter("intensity", 0.0)
	rect.material = m
	cl.add_child(rect)
	_edge_vignette_mat = m

## Screen-space HUD: host the sprite HP/shield display (reads GameManager; self-pins top-left in the arena).
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10   # explicit (was default 1): keep the HP/weapon/aux HUD ABOVE the mortar/fatboy shockwave (layer 8) so the blast distortion never ripples the HUD; still below buttons (11) / crit (12)
	add_child(ui)
	_ui_layer = ui
	add_child(ScreenFxScript.new())   # edge vignette + player hit flash (own CanvasLayer at layer 9, under the HUD)
	# Legacy Cockpit HUD — REPLACED by the authored playerhud (hud_edit_mode.gd / playerhud_layout.cfg,
	# wired by _setup_hud_edit). Kept in the tree but HIDDEN so any group lookups still resolve.
	var _frame := HudFrameScript.new(); _frame.visible = false; ui.add_child(_frame)
	var player_vitals := VitalsBarScript.new()
	player_vitals.mode = "player"
	player_vitals.visible = false
	ui.add_child(player_vitals)
	var boss_vitals := VitalsBarScript.new()
	boss_vitals.mode = "boss"
	boss_vitals.visible = false
	ui.add_child(boss_vitals)
	var _wslots := WeaponSlotsScript.new(); _wslots.visible = false; ui.add_child(_wslots)
	var _aslots := AuxSlotsScript.new();    _aslots.visible = false; ui.add_child(_aslots)
	var _stats  := ArenaStatsHudScript.new(); _stats.visible = false; ui.add_child(_stats)

# ── Setup ─────────────────────────────────────────────────────────────────────
func _build_player() -> void:
	add_to_group("arena")   # so arena_weapons can resolve muzzle_world() anchors
	_player = CharacterBody2D.new()
	_player.name = "Player"
	_player.position = PLAYER_START   # offset from the sun at origin (solar system orbits world origin)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = PLAYER_RADIUS
	col.shape = shape
	_player_shape = shape
	_player.add_child(col)

	var cam := CamShakeScript.new()   # Camera2D + screen-shake (group "camera_shake")
	cam.zoom = CAM_ZOOM
	cam.enabled = true
	_player.add_child(cam)

	# _player must be in the tree before we build the SubViewport so the 3D model's transforms resolve.
	add_child(_player)
	_player.add_to_group("player")   # enemies/spawner find the player via this group
	cam.make_current()

	# 3D ship: render the model top-down into a SubViewport, shown on a Sprite2D that rotates to aim
	# exactly like the old sprite. The model also banks (rolls) with the aim heading so its flanks show
	# when aiming sideways — see _update_ship_3d(). Weapons still read _player.rotation (unchanged 2D aim).
	_build_ship_viewport()
	var spr := Sprite2D.new()
	spr.texture = _ship_vp.get_texture()
	spr.z_index = SHIP_Z   # keep the ship on top of every weapon/explosion effect — always visible
	var s := PLAYER_SIZE_PX * SHIP_DISPLAY_GAIN / float(VP_SIZE) * GameManager.upg_ship_size_mult
	spr.scale = Vector2(s, s)
	_ship_spr = spr
	_player.add_child(spr)
	_update_ship_3d()

## Build the SubViewport that renders the 3D ship model top-down (transparent bg, two directional lights).
func _build_ship_viewport() -> void:
	_ship_vp = SubViewport.new()
	_ship_vp.size = Vector2i(VP_SIZE, VP_SIZE)
	_ship_vp.transparent_bg = true
	_ship_vp.own_world_3d = true
	_ship_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_ship_vp.msaa_3d = Viewport.MSAA_4X
	_player.add_child(_ship_vp)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.3
	_ship_vp.add_child(key)
	var fill := DirectionalLight3D.new()   # opposite-side fill so the far side isn't pure black when banked
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.5
	_ship_vp.add_child(fill)

	_ship_cam = Camera3D.new()
	_ship_vp.add_child(_ship_cam)

	_ship_pivot = Node3D.new()
	_ship_vp.add_child(_ship_pivot)

	var packed := load(SHIP_MODEL) as PackedScene
	var model: Node3D = (packed.instantiate() as Node3D) if packed != null else null
	if model != null:
		_ship_pivot.add_child(model)
		_frame_ship_cam(model)
		_load_muzzle_anchors(model)
	else:
		push_warning("arena: could not load ship model at " + SHIP_MODEL)
		_ship_cam.position = Vector3(0.0, 0.0, 5.0)
		_ship_cam.look_at(Vector3.ZERO, Vector3.UP)

## Frame the camera straight-on to fit the model, and recenter the model so it rolls about its own middle.
func _frame_ship_cam(model: Node3D) -> void:
	var aabb := _model_aabb(model)
	var center := aabb.position + aabb.size * 0.5
	model.position -= center
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var half_fov := deg_to_rad(_ship_cam.fov * 0.5)
	var dist := radius / tan(half_fov) + radius
	# Iso: raise the camera SHIP_ISO_DEG off straight-down so we view the ship at a fixed tilt.
	var iso := deg_to_rad(SHIP_ISO_DEG)
	_ship_cam.position = Vector3(0.0, cos(iso), sin(iso)) * dist
	_ship_cam.look_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_ship_cam.near = maxf(0.05, dist - radius * 2.0)
	_ship_cam.far  = dist + radius * 2.0

func _model_aabb(root: Node) -> AABB:
	var acc := AABB()
	var has := false
	var inv := _ship_pivot.global_transform.affine_inverse()
	for mi: MeshInstance3D in _model_meshes(root):
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if not has:
			acc = box
			has = true
		else:
			acc = acc.merge(box)
	return acc if has else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

func _model_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c: Node in node.get_children():
		out.append_array(_model_meshes(c))
	return out

## Roll the model about its nose axis by 90°·sin(aim heading): aiming up/down → top view,
## aiming left/right → full side view. The Sprite2D itself inherits _player.rotation for the heading.
func _update_ship_3d() -> void:
	if _ship_pivot == null or _player == null:
		return
	# Isometric: the ship yaws in 3D to aim (so the camera tilt stays fixed), with a gentle bank.
	var yaw := -_player.rotation * SHIP_YAW_SIGN
	var lean := deg_to_rad(SHIP_LEAN_MAX_DEG) * sin(_player.rotation) * SHIP_INVERT_SIDES
	var base := Basis(Vector3(0, 1, 0), deg_to_rad(-90.0))   # dorsal +Y up, nose → -Z at yaw 0
	var lean_b := Basis(Vector3(1, 0, 0), lean)              # roll about the model's nose axis (local X)
	var heading := Basis(Vector3(0, 1, 0), yaw)              # yaw about world up
	_ship_pivot.transform = Transform3D(heading * base * lean_b, Vector3.ZERO)
	# Heading now lives in 3D, so the display sprite must stay screen-fixed (cancel _player's rotation).
	if _ship_spr != null:
		_ship_spr.rotation = -_player.rotation

## Load the muzzle anchor points (placed in ship_rotation_test) as Node3D children of the model, so they
## ride the ship's roll. Weapons resolve their world muzzle via muzzle_world(slot).
func _load_muzzle_anchors(model: Node3D) -> void:
	_muzzle_anchors.clear()
	var cfg := ConfigFile.new()
	if cfg.load(MUZZLE_CFG) != OK or not cfg.has_section("muzzles"):
		return
	for key: String in cfg.get_section_keys("muzzles"):
		var anchor := Node3D.new()
		anchor.position = cfg.get_value("muzzles", key)
		model.add_child(anchor)
		_muzzle_anchors[int(key)] = anchor

## World-space 2D position of muzzle point `slot`. Projects the placed 3D anchor through the ship
## camera → exactly where that point lands on the rendered (tilted) ship, then maps it to the on-screen
## ship. The anchor rides the ship's 3D orientation, so no axis/scale guessing. Ship centre if undefined.
func muzzle_world(slot: int) -> Vector2:
	if _player == null:
		return Vector2.ZERO
	var anchor: Node3D = _muzzle_anchors.get(slot, null)
	if anchor == null or _ship_cam == null or _ship_spr == null:
		return _player.global_position
	var pix := _ship_cam.unproject_position(anchor.global_position)
	var off := (pix - Vector2(VP_SIZE, VP_SIZE) * 0.5) * _ship_spr.scale.x
	# Display sprite is screen-fixed (heading is in the 3D render), so no extra 2D rotation.
	return _player.global_position + off

## True once at least one muzzle anchor is loaded (weapons fall back to legacy offsets otherwise).
func has_muzzle_anchors() -> bool:
	return not _muzzle_anchors.is_empty()

## Spawn one reward chest ~CHEST_DIST from the player's start (random direction, clamped inside the playable
## disc so it's reachable), plus the edge-of-screen pointer arrow that guides the player to it.
func _spawn_reward_chest() -> void:
	var ang := randf() * TAU
	var pos := PLAYER_START + Vector2(cos(ang), sin(ang)) * CHEST_DIST
	if not LIMITLESS:
		var max_r := HARD_BOUNDARY - 250.0
		if pos.length() > max_r:
			pos = pos.normalized() * max_r   # bounded map: keep the chest reachable inside the edge
	var chest := ChestScript.new()
	add_child(chest)
	chest.global_position = pos
	var ptr_layer := CanvasLayer.new()
	ptr_layer.layer = 55             # above gameplay, below settings/overlays
	add_child(ptr_layer)
	ptr_layer.add_child(ChestPointerScript.new())

func _build_parallax(parent: Node) -> void:
	var i := 0
	for layer in STAR_LAYERS:
		var factor: float = layer[0]
		var tile: int = int(layer[1])
		var count: int = int(layer[2])
		var dot: float = layer[3]
		var bright: float = layer[4]
		var px := Parallax2D.new()
		px.scroll_scale = Vector2(factor, factor)
		px.repeat_size = Vector2(float(tile), float(tile))
		px.repeat_times = 3
		px.z_index = -100 + i   # well behind the player/projectiles
		if ArenaDofScript.ENABLED:
			px.modulate = ArenaDofScript.FAR_MODULATE   # deepest layer → recede most (only when the mask is on)
		var spr := Sprite2D.new()
		spr.texture = _make_star_tex(tile, count, dot, bright)
		spr.centered = false
		px.add_child(spr)
		parent.add_child(px)   # into the DoF SubViewport (blurred background)
		i += 1

## Build a seamless tiling star texture: random faint dots on a transparent tile (dots kept inside the
## tile so the repeated edges stay transparent → no seams).
func _make_star_tex(tile: int, count: int, dot: float, bright: float) -> Texture2D:
	var img := Image.create(tile, tile, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := int(ceil(dot))
	for _k in count:
		var cx := randi_range(r, tile - 1 - r)
		var cy := randi_range(r, tile - 1 - r)
		var b := bright * randf_range(0.5, 1.0)
		var tint := randf()   # slight blue/white variety
		var col := Color(0.8 + 0.2 * tint, 0.85 + 0.15 * tint, 1.0, b)
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if Vector2(ox, oy).length() <= dot:
					img.set_pixel(cx + ox, cy + oy, col)
	return ImageTexture.create_from_image(img)

# ── Per-frame ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed_mult: float = GameManager.get_move_speed_mult() if GameManager.has_method("get_move_speed_mult") else 1.0
	var spd := MOVE_SPEED * speed_mult
	# Each clinging squid drags the ship: −20% move speed, stacking (2 squids = −40%, …).
	var cling := get_tree().get_nodes_in_group("squid_clinging").size()
	if cling > 0:
		spd *= maxf(1.0 - 0.20 * float(cling), SQUID_CLING_SLOW_FLOOR)
	# Equipped thruster behaviour (Phase 5): strong=raw speed, reverse=faster backpedal,
	# smart=auto-dodge incoming fire, defend=shove enemy fire away from the hull.
	var tstats: Dictionary = _thruster_def().get("stats", {})
	var ttype := String(tstats.get("thruster_type", ""))
	var fwd := Vector2.UP.rotated(_player.rotation)
	if ttype == "strong":
		spd *= float(tstats.get("speed_mult", 1.0))
	elif ttype == "reverse" and dir.dot(fwd) < -0.1:
		spd *= float(tstats.get("reverse_mult", 1.0))   # boost only while backpedalling
	var vel := dir * spd
	if ttype == "smart":
		vel += _smart_dodge(tstats)
	elif ttype == "defend":
		_defend_push(tstats)
	# Soft enemy-crowd shove: enemies you're overlapping push the ship (a current, not a wall — see
	# GameManager.take_player_push / arena_enemy._check_contact). This is what makes a mob hard to escape.
	if GameManager.has_method("take_player_push"):
		vel += GameManager.take_player_push()
	_player.velocity = vel
	_update_ship_lean(dir)
	_player.move_and_slide()
	_apply_boundary(delta)

## Soft outer edge: past SOFT_BOUNDARY the player drifts gently back inward (stronger the further out), and is
## hard-clamped at HARD_BOUNDARY. A screen vignette fades in as the edge nears. Not a wall — a current.
func _apply_boundary(delta: float) -> void:
	if LIMITLESS:
		if _edge_vignette_mat != null:
			_edge_vignette_mat.set_shader_parameter("intensity", 0.0)
		return   # no edge — the world is unbounded
	var pos := _player.global_position
	var d := pos.length()
	if d > SOFT_BOUNDARY and d > 0.0:
		var inward := -pos / d
		_player.global_position += inward * (d - SOFT_BOUNDARY) * BOUNDARY_PULL * delta
		if d > HARD_BOUNDARY:
			_player.global_position = (pos / d) * HARD_BOUNDARY
	if _edge_vignette_mat != null:
		var f := clampf((d - (SOFT_BOUNDARY - VIGNETTE_FADE)) / VIGNETTE_FADE, 0.0, 1.0)
		_edge_vignette_mat.set_shader_parameter("intensity", f)

## The equipped thruster's def ({} if none) — read each physics frame for its behaviour.
func _thruster_def() -> Dictionary:
	var uid: int = InventoryManager.equipped_uid("thruster")
	if uid == -1:
		return {}
	return InventoryManager.get_def(String(InventoryManager.get_item(uid).get("def", "")))

func _arena_enemy_mgr() -> Node:
	if _enemy_mgr == null or not is_instance_valid(_enemy_mgr):
		_enemy_mgr = get_tree().get_first_node_in_group("enemy_manager")
	return _enemy_mgr

## Smart thruster: a velocity kick away from the nearest incoming enemy bullet (Vector2.ZERO if clear).
func _smart_dodge(stats: Dictionary) -> Vector2:
	var mgr := _arena_enemy_mgr()
	if mgr == null or not mgr.has_method("nearest_bullet_offset"):
		return Vector2.ZERO
	var off: Vector2 = mgr.nearest_bullet_offset(_player.global_position, float(stats.get("dodge_radius", 130.0)))
	if off == Vector2.ZERO:
		return Vector2.ZERO
	return -off.normalized() * float(stats.get("dodge_force", 680.0))

## Bulwark thruster: shove enemy fire near the ship outward.
func _defend_push(stats: Dictionary) -> void:
	var mgr := _arena_enemy_mgr()
	if mgr != null and mgr.has_method("push_bullets_away"):
		mgr.push_bullets_away(_player.global_position, float(stats.get("push_radius", 170.0)), float(stats.get("push_force", 560.0)))

func _update_ship_lean(_dir: Vector2) -> void:
	# Legacy texture-swap lean is superseded by the 3D bank in _update_ship_3d().
	# (A subtle strafe-tilt could be re-added here later by nudging _ship_pivot's roll.)
	pass

func _process(delta: float) -> void:
	if _player == null:
		return
	# Juggernaut nerf: apply the ship-size multiplier to the sprite + collision radius when it changes.
	var sm: float = GameManager.upg_ship_size_mult
	if not is_equal_approx(sm, _applied_size_mult):
		_applied_size_mult = sm
		if _player_shape != null:
			_player_shape.radius = PLAYER_RADIUS * sm
		if _ship_spr != null:
			_ship_spr.scale = Vector2.ONE * (PLAYER_SIZE_PX * SHIP_DISPLAY_GAIN / float(VP_SIZE) * sm)
	_aim(delta)
	_update_ship_3d()
	if USE_PLACEHOLDER_FIRE:
		_fire_acc += delta
		while _fire_acc >= FIRE_INTERVAL:
			_fire_acc -= FIRE_INTERVAL
			_spawn_projectile()
		_tick_projectiles(delta)

## Smoothly rotate the ship to face the mouse (sprite forward = −Y → +PI/2 offset).
func _aim(delta: float) -> void:
	var target := (get_global_mouse_position() - _player.global_position).angle() + PI * 0.5
	if TURN_INSTANT:
		_player.rotation = target
	else:
		_player.rotation = lerp_angle(_player.rotation, target, clampf(TURN_SPEED * delta, 0.0, 1.0))

## Placeholder projectile: a little dart Polygon2D flying along the ship's current facing.
func _spawn_projectile() -> void:
	var fwd := Vector2.UP.rotated(_player.rotation)
	var proj := Polygon2D.new()
	proj.polygon = PackedVector2Array([Vector2(0, -7), Vector2(4, 5), Vector2(-4, 5)])
	proj.color = PROJ_COLOR
	proj.position = _player.global_position + fwd * 20.0
	proj.rotation = _player.rotation
	add_child(proj)
	_projectiles.append({"node": proj, "vel": fwd * PROJ_SPEED, "life": 0.0, "start": proj.position})

func _tick_projectiles(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("arena_enemy")
	var i := _projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = _projectiles[i]
		var n := p["node"] as Node2D
		if n == null or not is_instance_valid(n):
			_projectiles.remove_at(i)
			i -= 1
			continue
		n.position += (p["vel"] as Vector2) * delta
		p["life"] = float(p["life"]) + delta
		var dead := float(p["life"]) >= PROJ_LIFETIME or n.position.distance_to(p["start"]) >= PROJ_MAX_DIST
		# Hit test vs enemies (the new take_damage contract proves aim → fire → kill).
		if not dead:
			for en in enemies:
				if is_instance_valid(en) and n.global_position.distance_to((en as Node2D).global_position) <= PROJ_HIT_RADIUS:
					if en.has_method("take_damage"):
						en.take_damage(PROJ_DAMAGE)
					dead = true
					break
		if dead:
			n.queue_free()
			_projectiles.remove_at(i)
		i -= 1

# ── Boss Edit (F3) ────────────────────────────────────────────────────────────
func _setup_boss_edit() -> void:
	# Provide a full-screen Control as ObjectsContainer so boss_edit_mode can place
	# boss sprites in screen space (same role as edit_mode's ObjectsContainer in main.gd).
	var cl := CanvasLayer.new()
	cl.layer = 9
	add_child(cl)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(oc)
	var bem := BossEditScript.new()
	add_child(bem)
	_boss_edit = bem
	bem.setup(oc)

func _setup_creep_edit() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 9
	add_child(cl)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(oc)
	var cem := CreepEditScript.new()
	add_child(cem)
	_creep_edit = cem
	cem.setup(oc)

func _setup_weapon_edit() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 9
	add_child(cl)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(oc)
	var wem := WeaponEditScript.new()
	add_child(wem)
	_weapon_edit = wem
	wem.setup(oc)

## Authored playerhud: a CanvasLayer(9) + full-screen ObjectsContainer that hud_edit_mode.gd fills. When
## the editor is closed those placed nodes ARE the live HUD (wired to game state via its runtime bindings),
## replacing the hidden cockpit HUD in _build_ui.
func _setup_hud_edit() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 9
	add_child(cl)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(oc)
	var hem := HudEditScript.new()
	add_child(hem)
	_hud_edit = hem
	var hud_version := String(SettingsScript.load_cfg().get("hud_version", "hud"))
	hem.setup(oc, hud_version)

## Hide the gameplay + all HUD (HP/XP, weapon/aux slots, button clusters, debug panels, player, live enemies)
## while a full-screen editor (Creep / Fleet) is open, so only the editor panels + its edit objects show.
## Restored when the editor closes. Background/parallax is left in place.
func set_edit_focus(on: bool) -> void:
	var vis := not on
	if _ui_layer != null and is_instance_valid(_ui_layer):
		_ui_layer.visible = vis
	if _hud_buttons != null and is_instance_valid(_hud_buttons):
		_hud_buttons.visible = vis            # CanvasLayer — hides both button clusters
	if _player != null and is_instance_valid(_player):
		_player.visible = vis
	var ds := get_tree().get_first_node_in_group("arena_debug_spawn")
	if ds != null:
		ds.visible = vis                      # CanvasLayer — fire-rate / +level / quick-spawn UI
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if e is CanvasItem:
			(e as CanvasItem).visible = vis

func _setup_fleet_edit() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 9
	add_child(cl)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(oc)
	var fem := FleetEditScript.new()
	add_child(fem)
	fem.setup(oc)

# ── Run end (death → hub) ───────────────────────────────────────────────────────
var _run_over_shown: bool = false

func _on_run_ended() -> void:
	# Phoenix Core passive: spend a revive charge and keep playing instead of ending the run.
	if GameManager.has_method("try_rebirth") and GameManager.try_rebirth():
		return
	# Project Phoenix (Player 2 evolve): revive to full HP + shut Player 2 down for 10 minutes.
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	if aw != null and aw.has_method("player2_phoenix_try") and bool(aw.call("player2_phoenix_try")):
		return
	if _run_over_shown:
		return
	_run_over_shown = true
	call_deferred("_show_run_over")   # ship_destroyed can fire inside a boss tick → defer

func _show_run_over() -> void:
	get_tree().paused = true
	var cl := CanvasLayer.new()
	cl.layer = 200
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	cl.add_child(box)
	var title := Label.new()
	title.text = "RUN OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tf := load("res://assets/fonts/Good Old DOS.ttf") as Font
	if tf != null:
		title.add_theme_font_override("font", tf)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("#E5792A"))
	box.add_child(title)
	var sub := Label.new()
	var lvl: int = GameManager.player_level if "player_level" in GameManager else 1
	sub.text = "Reached level %d" % lvl
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	box.add_child(sub)
	var btn := Button.new()
	btn.text = "RETURN TO DOCK"
	btn.custom_minimum_size = Vector2(260, 56)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	box.add_child(btn)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_boss_edit_mode"):
		if _boss_edit != null:
			_boss_edit.toggle()
		get_viewport().set_input_as_handled()
