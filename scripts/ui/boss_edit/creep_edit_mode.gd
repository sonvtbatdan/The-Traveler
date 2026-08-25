extends CanvasLayer
## Creep Edit Mode — place enemy sprites, mark Fire Points and Thrust Points.
## Opened via the Creep_edit button (Devon dev panel). Saves to res://creep_layout.cfg.

const EditableObject  := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const GifLoader       := preload("res://scripts/ui/edit_mode/gif_loader.gd")
const GridOverlay     := preload("res://scripts/ui/boss_edit/grid_overlay.gd")
const EnergyVortex    := preload("res://scripts/gameplay/fx/energy_vortex.gd")
const LedLight        := preload("res://scripts/gameplay/fx/led_light.gd")
const ArenaEnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")   # to invalidate its cached layout cfg on save; also owns the Metalfly layer names (MF_* below)
const MetalflyRigScript := preload("res://scripts/gameplay/fx/metalfly_rig.gd")   # owns the winged body's glb path
const WaveDirScript    := preload("res://scripts/gameplay/arena_wave_director.gd")   # ENEMY_DEFS, for the CHAIN section's defaults/live-apply
const LAYOUT_PATH       := "res://creep_layout.cfg"
const PLUME_STYLES_PATH := "res://plume_styles.cfg"
const CHAIN_CFG_PATH    := "res://creep_chain_overrides.cfg"   # CHAIN section saves here — see apply_chain_overrides()
## Sprite basenames that make up a chain/multi-node enemy → the ENEMY_DEFS id whose "centi_*" fields they
## share. Only centipede exists today (mirrors arena_enemy.gd's _load_centipede() hardcoded 3 filenames);
## a future chain-type enemy just adds its own {part_name: id} entries here — the CHAIN section itself
## (segments/spacing/bend) is already generic, nothing else about it is centipede-specific.
const CHAIN_PARTS: Dictionary = {
	"centipedehead": "centipede", "centipedebody": "centipede", "centipedetail": "centipede",
	# 2026-08-13 — Atlantic sea-creature chain reskins (arena_enemy.gd's generalized chain runtime).
	"cent head": "atlantic_centipede", "cent body": "atlantic_centipede", "cent tail": "atlantic_centipede",
	"hammerhead head": "hammerhead", "hammerhead body1": "hammerhead", "hammerhead body2": "hammerhead", "hammerhead tail": "hammerhead",
	"killerwhale head": "killerwhale", "killerwhale body1": "killerwhale", "killerwhale body2": "killerwhale", "killerwhale tail": "killerwhale",
	"shark elite head": "shark_elite", "shark elite body1": "shark_elite", "shark elite body2": "shark_elite", "shark elite tail": "shark_elite",
	"spermwhale2 head": "spermwhale2", "spermwhale2 body": "spermwhale2", "spermwhale2 tail": "spermwhale2",
}
const ENEMIES_FOLDER    := "res://assets/enemiesHD/"
## Map registry for the ENEMIES palette's "Map:" dropdown (2026-08-13). `id` matches meta_manager.gd's
## MAP_DEFS / arena.gd's map_id strings exactly; `name` matches hub_screen.gd's MAP_LIST display name
## (electric's is "Electric" — the folder is assets/map/electric/, per the 2026-08-13 rename). Selecting an
## entry filters the palette down to ONLY that map's own enemy folder — "Space" (default) shows whatever's
## left in ENEMIES_FOLDER after the other 3 maps' exclusive sprites were carved out (2026-08-12 reorg).
## 2026-08-17: mechanic/arctic/cosmic/mystic added — the user moved every enemiesHD sprite still in
## active use into its own new assets/map/<name>/enemies/ folder (matching the 4-map naming convention
## from the 8-map plan; see hub_screen.gd's LAUNCH_CARDS), so those sprites need a Map: entry here too or
## they'd be invisible to Creep Edit (they used to show under "Space" via enemiesHD). These 4 have no
## MAP_DEFS/arena.gd map_id yet (not real, launchable maps — still name-only placeholders) — that's fine,
## this dropdown is purely a Creep Edit authoring convenience, not tied to MetaManager.selected_map_id.
const MAP_REGISTRY: Array[Dictionary] = [
	{"id": "default",  "name": "Space",    "folder": ENEMIES_FOLDER},
	{"id": "electric",  "name": "Electric", "folder": "res://assets/map/electric/enemies/"},
	{"id": "volcanic", "name": "Volcanic", "folder": "res://assets/map/volcanic/enemies/"},
	{"id": "atlantic", "name": "Atlantic", "folder": "res://assets/map/atlantic/enemies/"},
	{"id": "mechanic", "name": "Mechanic", "folder": "res://assets/map/mechanic/enemies/"},
	{"id": "arctic",   "name": "Arctic",   "folder": "res://assets/map/arctic/enemies/"},
	{"id": "cosmic",   "name": "Cosmic",   "folder": "res://assets/map/cosmic/enemies/"},
	{"id": "mystic",   "name": "Mystic",   "folder": "res://assets/map/mystic/enemies/"},
]
const ASSET_PANEL_W     := 210.0
const CTRL_PANEL_W      := 224.0
const SCREEN_ORIGIN     := Vector2(15.0, 8.0)

# ── Metalfly boss, as 3D LAYERS (2026-08-24) ────────────────────────────────────────────────────────────
# The arena Metalfly is a two-phase boss whose bodies are BOTH live 3D models (arena_enemy.gd's
# `boss_move: "metalfly"`): a spinning Cocoon.glb for Phase 1, then the code-posed metalfly.glb rig for
# Phase 2. Neither is a sprite, so neither could ever appear in the folder scan — they are declared here the
# same way weapon_edit_mode.gd declares Jeager's animation layers, and they get the same treatment for the
# same reason: a 3D body needs its mount angle dialled in by eye, which is what the Rotate X/Y/Z sliders and
# the FRONT arrow exist for.
#
# Declared in the BASE (this file) rather than a subclass because Creep Edit *is* the base. It cannot leak
# into the other editors: weapon_edit_mode.gd overrides every hook below, and hud_edit_mode.gd/
# fleet_edit_mode.gd extend CanvasLayer, not this file. It is further gated to the Electric map's own
# palette (MF_MAP), matching the "Map:" dropdown convention — this is Electric's boss.
## Layer names and asset paths are NOT restated here — every one of them is read off the runtime that
## consumes them (arena_enemy.gd owns the cfg keys, metalfly_rig.gd owns the winged glb path). A layer whose
## editor name drifted from its runtime name would look completely fine and simply never apply, which is the
## worst kind of bug to leave available.
## TWO bodies, and exactly two rows: the group's ROOT is the winged body itself (it is both the boss's
## palette entry and its Phase 2 model — a separate "… Wings" row would place a second, identical model
## stacked precisely on the root's), with the cocoon hanging under it as the one child layer.
const MF_MAP           := "electric"
const MF_ROOT          := ArenaEnemyScript.MF_LAYER_WINGS    # Phase 2 body (metalfly_rig.gd) + the group row
const MF_COCOON        := ArenaEnemyScript.MF_LAYER_COCOON   # Phase 1 body (glb_spin_body.gd)
const MF_LAYERS: Array[String] = [MF_COCOON]
const MF_GLB := {
	MF_ROOT:   MetalflyRigScript.GLB_PATH,
	MF_COCOON: ArenaEnemyScript.MF_COCOON_GLB,
}
## Where the FRONT arrow points for these layers — DOWN the canvas (+PI/2), not up like the weapons.
## That is not a style choice: metalfly.glb is authored with its head at +Z, and the shared top-down framing
## (glb_topdown_rig.gd) maps +Z to screen-DOWN, so at zero calibration the model's nose genuinely points
## down. Pointing the arrow up instead would invite a 180° "correction" that the runtime would then apply
## on top of an orientation which is already right — the boss would fly backwards, which is exactly the bug
## the arrow was added to Jeager to fix. Arrow aligned with the nose at rot 0 keeps `rot` a pure correction:
## 0 means "what ships today", verified in the arena.
const MF_FRONT_ANGLE   := PI * 0.5
const MF_LAYER_PX      := 170.0               # preview size — near the arena's own DISPLAY_PX (180)
const MF_COCOON_POS    := Vector2(300.0, 210.0)
const MF_WINGS_POS     := Vector2(560.0, 210.0)

# ── State ──────────────────────────────────────────────────────────────────────
var _is_open:          bool   = false
var _dirty:            bool   = false
var _active_creep:     String = ""
var _group_selected:   bool   = false  # true = the synthetic "whole creep" LAYERS row is selected instead of one part — see _make_group_layer_row()
var _all_creep_names:  Array[String] = []
var _placed:           Dictionary = {}  # creep_name -> EditableObjectNode (one per creep)
var _selected_obj:     EditableObjectNode = null
var _creep_buttons:    Dictionary = {}  # creep_name -> Button
var _creep_parents:    Dictionary = {}  # child_name -> parent_name (empty string = root/no parent)
var _chain_group_order: Dictionary = {} # root_name -> Array[String] children in head/body1/body2/.../tail order — see _auto_group_chain_names()
var _chain_last_segs:   Dictionary = {} # root_name -> last Segments value a rebuild ran with; see the tail branch in _rebuild_chain_preview()
var _chain_name_re:     RegEx = null    # lazy-compiled — see _chain_name_regex()
var _objects_container: Control = null

# Point state — Fire Points (FP), Thrust Points (TP), Tentacle Points (TenP)
var _adding_firepoint:    bool = false
var _adding_thrustpoint:  bool = false
var _adding_tentaclepoint: bool = false
var _fire_points:        Dictionary = {}  # creep_name -> Array[{pos, id, dir_angle}]
var _thrust_points:      Dictionary = {}  # creep_name -> Array[{pos, id, dir_angle}]
var _tentacle_points:    Dictionary = {}  # creep_name -> Array[{pos, id, dir_angle}] — each spawns a tentacle
var _fp_id_counter:      Dictionary = {}  # creep_name -> int
var _tp_id_counter:      Dictionary = {}  # creep_name -> int
var _tenp_id_counter:    Dictionary = {}  # creep_name -> int
var _selected_fp_idx:     int        = -1
var _selected_tp_idx:     int        = -1   # primary (last clicked) — used for angle UI + plume editor
var _selected_tp_indices: Array[int] = []   # full multi-selection set
var _tp_range_anchor:     int        = -1   # 2026-08-15 — fixed start of a Shift-click range, set by every plain (non-Shift) select
var _selected_tenp_idx:   int        = -1
# Vortex Points (VX) — a directionless point that anchors a spinning energy-vortex VFX (EnergyVortex).
var _adding_vortexpoint:  bool       = false
var _vortex_points:       Dictionary = {}     # creep_name -> Array[{pos, id}]
var _vortex_id_counter:   Dictionary = {}     # creep_name -> int
var _selected_vortex_idx: int        = -1   # primary (last clicked) — used for the param editor + copy
var _selected_vortex_indices: Array[int] = []   # full multi-selection set (paste/edit apply to all)
var _vortex_range_anchor: int        = -1   # 2026-08-15 — fixed start of a Shift-click range
var _vortex_styles:       Dictionary = {}     # cname -> {"vx_N": style_dict}
var _updating_vortex:     bool       = false
var _vortex_clipboard:    Dictionary = {}     # last Copy'd vortex style; empty = nothing to Paste
var _preview_vortexes:    Array      = []     # live EnergyVortex preview nodes on the EO
# Led Points (LED) — a directionless point that anchors a small glowing/blinking light (LedLight VFX).
# Mirrors Vortex Points exactly (same directionless point + separate per-point style dict pattern).
var _adding_ledpoint:     bool       = false
var _led_points:          Dictionary = {}     # creep_name -> Array[{pos, id}]
var _led_id_counter:      Dictionary = {}     # creep_name -> int
var _selected_led_idx:    int        = -1   # primary (last clicked) — used for the param editor + copy
var _selected_led_indices: Array[int] = []   # full multi-selection set (paste/edit apply to all)
var _led_range_anchor:    int        = -1   # 2026-08-15 — fixed start of a Shift-click range
var _led_styles:          Dictionary = {}     # cname -> {"led_N": style_dict}
var _updating_led:        bool       = false
var _led_clipboard:       Dictionary = {}     # last Copy'd LED style; empty = nothing to Paste
var _preview_leds:        Array      = []     # live LedLight preview nodes on the EO
var _layers_collapsed:    bool       = true   # LAYERS panel: hide child rows by default (declutter once placed)
## Per-layer visibility (2026-08-23, "hiện tại đang có nhiều layer cũng hiển thị, khó set plume"): creep name
## -> true when the eye is closed. A pure VIEW toggle — the part keeps its position, TPs and rotation, it just
## stops being drawn (both its flat EO and its model in the 3D group overlay) so the one being worked on is
## unobstructed. Persisted per creep in the layout cfg, since which parts you want out of the way while
## authoring is worth surviving a restart.
var _layer_hidden: Dictionary = {}
var _prev_paused:         bool       = false  # pause state before opening → restored on close (dev:on stays paused)

# ── UI ─────────────────────────────────────────────────────────────────────────
var _dim_overlay:    ColorRect     = null
var _asset_panel:    Panel         = null
var _asset_vbox:     VBoxContainer = null
var _fp_vbox:        VBoxContainer = null
var _tp_vbox:        VBoxContainer = null
var _ctrl_panel:     Panel         = null
# ── VIEW CUBE (2026-08-22) — the 3Ds-Max/Blender-style navigation gizmo. Drag it to orbit the angle every
# .glb PREVIEW is rendered from. It deliberately does NOT touch the plume overlay's camera: that one is
# top-down on purpose because its world coords ARE canvas coords (1 unit = 1 px, see _refresh_plume3d_
# preview) — tilting it would break TP placement and the whole 2D editing plane with it.
var _viewcube_vp:   SubViewport   = null
var _viewcube_pivot: Node3D       = null
var _viewcube_rect: TextureRect   = null
var _viewcube_btn:  Button        = null
var _viewcube_drag: bool          = false
var _view_yaw:   float = 0.0                      # radians, orbit around the vertical axis
# Starts at the in-game angle (straight down) so the editor OPENS in the familiar flat 2D mode: canvas and
# 3D scene coincide there, thumbnails show what the weapon actually looks like in play, and every 2D
# interaction behaves exactly as before. Orbiting the cube away from it is an explicit "let me inspect this
# in 3D" action; right-clicking the cube parks at the 3/4 authoring angle instead.
var _view_pitch: float = PI * 0.5
const VIEWCUBE_PX := 96.0
var _creep_btn_vbox: Container     = null   # ENEMIES palette grid (icon cells, fleet-edit style)
var _map_option:     OptionButton  = null   # "Map:" dropdown above the ENEMIES grid — see MAP_REGISTRY
var _selected_map_id: String       = "default"   # which MAP_REGISTRY entry's folder _folders() returns
var _sz_w_spin:      SpinBox       = null
var _sz_h_spin:      SpinBox       = null
var _z_spin:         SpinBox       = null
var _zoom_slider:    HSlider       = null
var _zoom_pct_lbl:   Label         = null
var _delete_btn:     Button        = null
var _grid_btn:       Button        = null
var _add_fp_btn:     Button        = null
var _add_tp_btn:     Button        = null
var _add_tenp_btn:   Button        = null
var _add_vortex_btn: Button        = null
var _add_led_btn:    Button        = null
var _toast_label:    Label         = null
var _grid_overlay:   Control       = null
var _fp_angle_row:   Control       = null
var _fp_angle_spin:  SpinBox       = null
var _tp_angle_row:   Control       = null
var _tp_angle_spin:  SpinBox       = null
## Bone picker for the selected TP (2026-08-23). Shown only for a creep whose model has a skeleton — bind a
## thrust point to a bone and its plume rides that bone through every animation instead of holding a fixed
## offset from the model centre. Stored as `tp["bone"]`; "" (the first entry) means unbound, i.e. exactly
## how every TP behaved before this existed.
var _tp_bone_row:    HBoxContainer = null
var _tp_bone_option: OptionButton  = null
var _tp_pos3_row:    HBoxContainer = null   # 2026-08-21 — TP X/Y/Z (relative to object center), glb TPs only,
var _tp_x3_spin:     SpinBox       = null   # lives in the TRANSFORM panel — see _build_ui's "TP POS" comment
var _tp_y3_spin:     SpinBox       = null   # and _refresh_tp_pos3_ui / _tp_xyz_get / _tp_xyz_set.
var _tp_z3_spin:     SpinBox       = null
var _tenp_vbox:      VBoxContainer = null
var _tenp_angle_row: Control       = null
var _tenp_angle_spin: SpinBox      = null
# Tentacle Points section widgets (hidden by design — replaced by the Vortex Points section)
var _tenp_section_nodes: Array     = []
# Vortex Points section widgets + param editor
var _vortex_vbox:      VBoxContainer = null
var _vortex_lbl:       Label         = null
var _vx_radius_spin:   SpinBox       = null
var _vx_spin_spin:     SpinBox       = null
var _vx_arms_spin:     SpinBox       = null
var _vx_col_core_btn:  ColorPickerButton = null
var _vx_col_mid_btn:   ColorPickerButton = null
var _vx_col_outer_btn: ColorPickerButton = null
# Led Points section widgets + param editor
var _led_vbox:      VBoxContainer     = null
var _led_lbl:       Label             = null
var _led_w_spin:    SpinBox           = null
var _led_h_spin:    SpinBox           = null
var _led_col_btn:   ColorPickerButton = null
var _led_intensity_spin: SpinBox      = null
var _led_blink_slider:   HSlider      = null
var _led_blink_lbl:      Label        = null
var _led_phase_spin:     SpinBox      = null
var _led_rotate_spin:    SpinBox      = null
var _led_wave_step_spin: SpinBox      = null
# Sections whose visibility now depends on whether the ACTIVE creep actually has that point type —
# see _refresh_dynamic_panels().
var _fp_section_nodes:     Array = []
var _tp_section_nodes:     Array = []
var _vortex_section_nodes: Array = []
var _led_section_nodes:    Array = []
# ── 3D VIEW section (2026-08-20) — Yaw/Pitch orbit sliders, shown only when the active creep is a .glb.
# See _load_glb_topdown_tex's header for the full design; _refresh_glb_view_ui shows/hides this section.
var _glb_view_section_nodes: Array = []
var _glb_rot_x_slider: HSlider = null   # 2026-08-20 (3rd pass) — replaces the old Yaw/Pitch pair with a
var _glb_rot_y_slider: HSlider = null   # full 3-axis object-rotation calibration (Rotate X/Y/Z), all saved —
var _glb_rot_z_slider: HSlider = null   # see _load_glb_topdown_tex's header.
# 2026-08-21 ("thanh slider không hiện giá trị nên không biết được giá trị hiện tại"): a numeric "<deg>°"
# readout per axis, kept in sync with the slider any time its value changes — by drag (_on_glb_rotation_
# changed) OR programmatically via set_value_no_signal (_refresh_glb_view_ui/_on_glb_reset_rotation), which
# don't fire `value_changed` on their own. See _sync_glb_rot_labels().
# Slider positions from the previous frame, in radians — the 3 rotate sliders are RELATIVE jog controls, so
# each change is applied as the DIFFERENCE from here. See _on_glb_rotation_changed's own header.
var _glb_slider_last: Vector3 = Vector3.ZERO
# Which mode the three Rotate handles are currently parked for — true = a TP is focused (absolute handles),
# false = an object (relative jog). Only used to detect a mode CHANGE, see _apply_tp_focus_transform_lock.
var _glb_handles_tp_mode: bool = false
var _glb_rot_x_lbl: Label = null
var _glb_rot_y_lbl: Label = null
var _glb_rot_z_lbl: Label = null
var _active_glb_path:  String  = ""   # cache key into _glb_preview_cache for whichever creep is active now
var _save_confirm_dlg: ConfirmationDialog = null
var _pos_x_spin:       SpinBox           = null
var _pos_y_spin:       SpinBox           = null

# CHAIN section (multi-node enemy tuning — segments/spacing/bend-lock/taper; see CHAIN_PARTS above)
var _chain_section:      VBoxContainer = null
var _chain_seg_spin:     SpinBox       = null
var _chain_spacing_spin: SpinBox       = null
var _chain_bend_spin:    SpinBox       = null
var _chain_taper_slider: HSlider       = null
var _chain_taper_lbl:    Label         = null   # "NN%" readout next to the slider, mirrors the Zoom slider's own label
var _chain_status:       Label         = null
var _chain_active_id:    String        = ""   # ENEMY_DEFS id the section is currently showing ("" = hidden)

# Plume editor UI
var _plume_vel_min_spin:  SpinBox           = null
var _plume_vel_max_spin:  SpinBox           = null
var _plume_life_spin:     SpinBox           = null
var _plume_spread_spin:   SpinBox           = null
var _plume_sc_min_spin:   SpinBox           = null
var _plume_sc_max_spin:   SpinBox           = null
var _plume_col_core_btn:  ColorPickerButton = null
var _plume_col_flame_btn: ColorPickerButton = null
var _plume_col_cool_btn:  ColorPickerButton = null
var _plume_styles:        Dictionary        = {}  # cname → {"tp_N": style_dict}
var _plume_tp_label:      Label             = null
var _updating_plume:      bool              = false
var _plume_clipboard:     Dictionary        = {}  # last Copy'd plume style; empty = nothing to Paste

# Plume preview nodes (shown in edit mode so TPs can be verified visually)
var _preview_plumes:    Array[CPUParticles2D] = []
## 2026-08-22 ("Plume của object weapon 3D phải là Plume 3D và xoay được với 3 thanh trượt slider"):
## `tp_id -> {vp: SubViewport, pivot: Node3D, layer: TextureRect, half: float}` — one standalone 3D plume
## preview per 3D TP (`dir_rot` present), rendered AT THE CLICK POINT on the edit canvas. Replaces the flat
## `CPUParticles2D` that `_refresh_plume_preview()` used to spawn there (see that function): the 2D one read
## `dir_angle`, a field the Rotate X/Y/Z sliders NEVER write (they only ever write `dir_rot`), so it was
## permanently frozen no matter how much you dragged — the "plume 2D tại điểm click, xoay không được" bug.
## Architecture is a deliberate copy of arena_weapons.gd's TEST PLUME (the one rotation approach proven to
## work end-to-end): SubViewport + top-down Camera3D + a `pivot` Node3D whose `.rotation` IS the TP's
## `dir_rot`, with a FIXED-direction CPUParticles3D child — so rotating = one `pivot.rotation` write, which
## re-orients every particle including ones already in flight (see glb_topdown_rig.gd's `tp_rotation()`
## header for why a pivot, not `CPUParticles3D.direction`, is what makes that work).
var _preview_plumes3d: Dictionary = {}
# Overlay framing (2026-08-23). MARGIN is the room left around the group's bounding sphere for plumes and
# for a part swinging out as the view orbits; SUPERSAMPLE is how many texture pixels per canvas pixel the
# overlay renders at, capped so the texture never exceeds MAX_TEX on a side (a big group falls back toward
# 1x rather than allocating an enormous render target).
const PLUME3D_FRAME_MARGIN := 220.0
const PLUME3D_SUPERSAMPLE  := 4.0
const PLUME3D_MAX_TEX      := 2048

# Panel drag state
var _dragging_asset:    bool    = false
var _drag_asset_off:    Vector2 = Vector2.ZERO
var _dragging_ctrl:     bool    = false
var _drag_ctrl_off:     Vector2 = Vector2.ZERO
var _eo_drag_undo_pushed: bool  = false
var _updating_spin:    bool    = false
var _grid_mode:        bool    = false
var _undo_stack: Array[Dictionary] = []

# Zoom state
var _zoom:     float = 1.0
const ZOOM_MIN := 0.4
const ZOOM_MAX := 5.0
const ZOOM_RATIO := 1.15

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(_edit_group())
	# _scan_creeps()/_build_ui()/_build_creep_buttons() moved to _ensure_built(), lazily run on first
	# toggle() instead of here — this editor is opened rarely (dev-only), but was previously paying its
	# full folder-scan + one-thumbnail-per-creep-sprite cost on every single arena boot for every player.

func setup(objects_container: Control) -> void:
	_objects_container = objects_container
	# _load_layout()/_load_plume_styles()/_load_vortex_styles()/_update_gameplay_visibility() moved to
	# _ensure_built() — see the note in _ready().

## First-open lazy init: the folder scan + thumbnail loads + saved-layout restore, deferred from
## _ready()/setup() to the moment a developer actually opens this editor (see toggle()).
var _lazy_built := false
func _ensure_built() -> void:
	if _lazy_built:
		return
	_lazy_built = true
	_scan_creeps()
	_auto_group_chain_names()
	_build_ui()
	_build_creep_buttons()
	_set_ui_visible(false)
	_load_layout()
	_load_plume_styles()
	_load_vortex_styles()
	_load_led_styles()
	_update_gameplay_visibility()

func is_open() -> bool:
	return _is_open

# ── Folder scan ────────────────────────────────────────────────────────────────

func _scan_creeps() -> void:
	_all_creep_names.clear()
	var seen: Dictionary = {}   # dedup across folders — first folder in _folders() wins
	for folder: String in _folders():
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		# --- Pass 1: collect every .glb basename in this folder ---
		# Godot's own glTF importer extracts embedded material images (base_color/normal/metallic_roughness,
		# "_Baked_BaseColor"/"_Baked_MetallicRoughness", etc.) as loose PNG/JPG files named "<glb_basename>_
		# <something>" right next to the source .glb the FIRST time the editor actually imports it (2026-08-20
		# bug report: opening Weapon Edit flooded the palette with ~15 bogus entries after VIPER's 3 glb files
		# got imported). These loose files are NOT separate weapons — the imported model's material now
		# references them, so they must NOT be deleted — just excluded from Pass 2 below by prefix-match
		# against every .glb basename actually present, instead of a fragile hardcoded suffix list (Godot's
		# extraction suffix isn't a stable/documented contract).
		var glb_names: Array = []
		dir.list_dir_begin()
		var scan_entry := dir.get_next()
		while scan_entry != "":
			if not dir.current_is_dir() and scan_entry.get_extension().to_lower() == "glb":
				glb_names.append(scan_entry.get_basename())
			scan_entry = dir.get_next()
		dir.list_dir_end()
		# --- Pass 2: build the real creep/weapon list, skipping any glb-extracted texture sibling ---
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				var ext := entry.get_extension().to_lower()
				if ext in ["png", "jpg", "jpeg", "gif", "glb"]:   # glb added 2026-08-20 (VIPER 3D swap)
					var name := entry.get_basename()
					var is_glb_texture := false
					if ext != "glb":
						for glb_name: String in glb_names:
							if name.begins_with(glb_name + "_"):
								is_glb_texture = true
								break
					if not is_glb_texture and _accept_file(name, folder) and not seen.has(name):
						seen[name] = true
						_all_creep_names.append(name)
			entry = dir.get_next()
		dir.list_dir_end()
	# Names that exist WITHOUT a file of their own on disk. Jeager's ten palette entries all render out of
	# one merged glb (see weapon_edit_mode._asset_path_for), but until 2026-08-24 they were still discovered
	# by this scan finding ten separate .glb files sitting next to it — so the nine source clips and the
	# duplicate Yari-Jeager.glb had to stay in the repo, ~260 MB, purely to keep the palette populated.
	# Declaring them instead unties the palette from the files and lets those be deleted.
	for extra: String in _extra_names():
		if not seen.has(extra):
			seen[extra] = true
			_all_creep_names.append(extra)
	_all_creep_names.sort()

## Override to add palette entries the folder scan cannot find. Base: the Metalfly boss's two 3D bodies
## (see the MF_* block) — they are glbs in assets/map/electric/boss/, not sprites in an enemies folder, so
## nothing the scan does could ever turn them up.
func _extra_names() -> Array[String]:
	if _selected_map_id != MF_MAP:
		return []
	var out: Array[String] = [MF_ROOT]
	out.append_array(MF_LAYERS)
	return out

## Multi-node auto-grouping (2026-08-13): sprite files named "<Prefix>Head" / "<Prefix>Body<N>" /
## "<Prefix>Tail" (case-insensitive suffix — e.g. "ViperHead.png"/"Viperbody1.png"/"VIPERBODY2.png"/
## "vipertail.png") are grouped together as ONE enemy, in head -> body1 -> body2 -> ... -> tail order, with
## NO manual parenting needed. Purely an editor/organizational convenience (LAYERS grouping, palette
## de-clutter, display order) — it does NOT give a newly-detected group any in-game chain BEHAVIOR; only
## "centipede" (CHAIN_PARTS, above) has that runtime wiring. Re-run after every _scan_creeps() (map dropdown
## change) since it's derived, not persisted.
func _chain_name_regex() -> RegEx:
	if _chain_name_re == null:
		_chain_name_re = RegEx.new()
		_chain_name_re.compile("(?i)^(.+?)(head|tail|body(\\d*))$")
	return _chain_name_re

## Parses one sprite basename against the Head/Body<N>/Tail convention. Returns {} if it doesn't end in one
## of those 3 suffixes, or the prefix before the suffix would be empty (a lone "Head"/"Tail" with nothing
## before it isn't part of a group — needs at least one other character to be a real enemy name).
func _parse_chain_name(cname: String) -> Dictionary:
	var m := _chain_name_regex().search(cname)
	if m == null:
		return {}
	var prefix := m.get_string(1)
	if prefix.is_empty():
		return {}
	var kind := m.get_string(2).to_lower()
	if kind.begins_with("body"):
		var digits := m.get_string(3)
		return {"prefix": prefix, "kind": "body", "n": int(digits) if digits != "" else 1}
	return {"prefix": prefix, "kind": kind, "n": 0}

func _auto_group_chain_names() -> void:
	var groups: Dictionary = {}   # lower(prefix) -> {"head": name, "tail": name, "bodies": Array[{n, name}]}
	for cname: String in _all_creep_names:
		var parsed := _parse_chain_name(cname)
		if parsed.is_empty():
			continue
		var key: String = String(parsed["prefix"]).to_lower()
		var g: Dictionary = groups.get(key, {"head": "", "tail": "", "bodies": []})
		match String(parsed["kind"]):
			"head": g["head"] = cname
			"tail": g["tail"] = cname
			"body": (g["bodies"] as Array).append({"n": int(parsed["n"]), "name": cname})
		groups[key] = g
	for key: String in groups:
		var g: Dictionary = groups[key]
		var bodies: Array = g["bodies"]
		var head: String = g["head"]
		var tail: String = g["tail"]
		# Need at least 2 parts total — a lone body/tail with no siblings isn't worth auto-parenting.
		if int(not head.is_empty()) + int(not tail.is_empty()) + bodies.size() < 2:
			continue
		bodies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) < int(b["n"]))
		var members: Array[String] = []
		for b: Dictionary in bodies:
			members.append(String(b["name"]))
		if not tail.is_empty():
			members.append(tail)
		var root := head
		if root.is_empty():
			if members.is_empty():
				continue
			root = members[0]   # no dedicated Head sprite — lowest-numbered Body leads instead
			members = members.slice(1)
		var force := _chain_force_arrange(root)
		for m: String in members:
			# Don't clobber an explicit parent already set this session (e.g. loaded from creep_layout.cfg) —
			# UNLESS this root is a force-arranged chain (2026-08-22). Those are always one assembled unit, so
			# a stale saved parent is simply wrong and silently breaks the group: VIPER's tail had
			# `parent = "VIPER body"` baked into weapon_layout.cfg from before it was a chain, which made
			# `_set_active_creep()` (it only loads children whose parent IS the root) skip the tail entirely —
			# the row rendered head + bodies and no tail at all.
			if force or not _creep_parents.has(m):
				_creep_parents[m] = root
		_chain_group_order[root] = members
	_group_metalfly_layers()

## Hangs Metalfly's two body glbs off its own root in the LAYERS list. Same shape as weapon_edit_mode.gd's
## Jeager grouping and for the same reason: these names share no Head/Body/Tail suffix, so the regex above
## could never have found them. A plain LAYERS group, not a chain — `_chain_id_for()` doesn't claim them, so
## there is no Segments/Spacing panel and no auto-arrangement; you place and rotate each one yourself.
func _group_metalfly_layers() -> void:
	if not _all_creep_names.has(MF_ROOT):
		return
	var members: Array[String] = []
	for m: String in MF_LAYERS:
		if m in _all_creep_names:
			_creep_parents[m] = MF_ROOT
			members.append(m)
	if not members.is_empty():
		_chain_group_order[MF_ROOT] = members

# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_dim_overlay = ColorRect.new()
	_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.color = Color(0.0, 0.0, 0.0, 0.35)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim_overlay)

	_toast_label = Label.new()
	_toast_label.z_index = 200
	_toast_label.modulate.a = 0.0
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_toast_label.add_theme_font_size_override("font_size", 18)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.size     = Vector2(640.0, 40.0)
	_toast_label.position = Vector2(400.0, 14.0)
	add_child(_toast_label)

	_build_asset_panel()
	_build_ctrl_panel()
	_build_view_cube()

	_grid_overlay = GridOverlay.new()
	_grid_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_overlay.z_index = 50
	add_child(_grid_overlay)

# ── LEFT panel: layers + points ────────────────────────────────────────────────

func _build_asset_panel() -> void:
	_asset_panel = Panel.new()
	# Clamp height to the screen so the panel never runs off the bottom; content below scrolls.
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_asset_panel.size     = Vector2(ASSET_PANEL_W, minf(890.0, vp_h - 56.0))
	_asset_panel.position = Vector2(20.0, 44.0)
	add_child(_asset_panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 4)
	_asset_panel.add_child(outer)

	# LAYERS title / drag handle — stays pinned above the scrollable content
	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0.0, 32.0)
	title_bar.gui_input.connect(_on_asset_title_input)
	outer.add_child(title_bar)
	var tl := Label.new()
	tl.text = "LAYERS"
	tl.add_theme_font_size_override("font_size", 12)
	tl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(tl)

	# Scrollable content area — sections taller than the panel get a vertical scrollbar.
	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(content_scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 4)
	content_scroll.add_child(root)

	var layers_scroll := ScrollContainer.new()
	layers_scroll.custom_minimum_size = Vector2(0.0, 120.0)
	layers_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(layers_scroll)
	_asset_vbox = VBoxContainer.new()
	_asset_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_vbox.add_theme_constant_override("separation", 2)
	layers_scroll.add_child(_asset_vbox)

	# FIRE POINTS section
	var fp_sep := HSeparator.new()
	root.add_child(fp_sep)
	var fp_hdr := Label.new()
	fp_hdr.text = "FIRE POINTS"
	fp_hdr.add_theme_font_size_override("font_size", 11)
	fp_hdr.modulate = Color(1.0, 0.55, 0.12)
	root.add_child(fp_hdr)

	var fp_scroll := ScrollContainer.new()
	fp_scroll.custom_minimum_size = Vector2(0.0, 80.0)
	fp_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(fp_scroll)
	_fp_vbox = VBoxContainer.new()
	_fp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fp_vbox.add_theme_constant_override("separation", 2)
	fp_scroll.add_child(_fp_vbox)

	# FP angle row
	_fp_angle_row = HBoxContainer.new()
	_fp_angle_row.visible = false
	_fp_angle_row.add_theme_constant_override("separation", 4)
	root.add_child(_fp_angle_row)
	var fpal := Label.new()
	fpal.text = "Dir:"
	fpal.add_theme_font_size_override("font_size", 10)
	fpal.custom_minimum_size = Vector2(24.0, 0.0)
	_fp_angle_row.add_child(fpal)
	_fp_angle_spin = SpinBox.new()
	_fp_angle_spin.min_value = -180.0
	_fp_angle_spin.max_value = 180.0
	_fp_angle_spin.step = 1.0
	_fp_angle_spin.suffix = "°"
	_fp_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fp_angle_spin.value_changed.connect(func(_v: float) -> void: _on_fp_angle_changed())
	_fp_angle_row.add_child(_fp_angle_spin)
	# 2026-08-15: hidden unless the active creep actually has a fire point — see _refresh_dynamic_panels().
	# _fp_angle_row is NOT included here — it already has its own dedicated show/hide tied to whether a FP is
	# currently SELECTED (_refresh_fp_angle_ui()), a separate concern from "does this creep have any at all".
	_fp_section_nodes = [fp_sep, fp_hdr, fp_scroll]

	# 3D VIEW / MOUNT ANGLE section (2026-08-20, 3rd pass) — Rotate X/Y/Z sliders directly spin the OBJECT
	# (camera is fixed, see _load_glb_topdown_tex header) and are the object's SAVED mount-angle calibration —
	# arena_weapons.gd's live gameplay rig reads them (_read_creep_rot) to orient the model. Hidden for every
	# non-glb creep via _refresh_glb_view_ui.
	var glb_sep := HSeparator.new()
	root.add_child(glb_sep)
	var glb_hdr := Label.new()
	glb_hdr.text = "3D VIEW / MOUNT ANGLE"
	glb_hdr.add_theme_font_size_override("font_size", 11)
	glb_hdr.modulate = Color(0.65, 0.75, 1.0)
	root.add_child(glb_hdr)
	# 2026-08-22 — the axis convention is invisible from the sliders alone, and getting it wrong wastes a lot
	# of dragging, so it is spelled out right where it is used. See glb_topdown_rig.gd's axis-space section.
	var glb_hint := Label.new()
	glb_hint.text = "X·Y = play plane, Z = vertical (up)"
	glb_hint.add_theme_font_size_override("font_size", 9)
	glb_hint.modulate = Color(0.6, 0.62, 0.7)
	root.add_child(glb_hint)
	var glb_axis_tips: Array = [
		"Rot X — tilt about the canvas LEFT-RIGHT axis.",
		"Rot Y — tilt about the canvas UP-DOWN axis.",
		"Rot Z — spin within the play plane, about the vertical axis.
For a thrust point this is the spray"
			+ " HEADING: the same thing the old flat 2D plume angle was.",
	]
	var glb_mode_tip := "

A thrust point selected: these are ABSOLUTE — the handle position is the angle."
	var glb_rows: Array = []
	var glb_sliders: Array = []
	var glb_val_lbls: Array = []
	for axis_i in range(3):
		var axis_name: String = ["X", "Y", "Z"][axis_i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		root.add_child(row)
		glb_rows.append(row)
		var lbl := Label.new()
		lbl.text = "Rot " + axis_name + ":"
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.custom_minimum_size = Vector2(40.0, 0.0)
		lbl.tooltip_text = glb_axis_tips[axis_i] + glb_mode_tip
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP   # a Label ignores the mouse by default -> no tooltip
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.tooltip_text = glb_axis_tips[axis_i] + glb_mode_tip
		slider.min_value = -180.0
		slider.max_value = 180.0
		slider.step = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(_v: float) -> void:
			_on_glb_rotation_changed()
			_sync_glb_rot_labels())
		# On release, re-park the handles for whatever is focused: centre for an OBJECT (jog), or the TP's
		# own stored angle for a TP (absolute, so it simply stays put) — see _sync_glb_rot_handles. Done on
		# `drag_ended` rather than inside `value_changed`, because resetting mid-drag would fight the mouse
		# (the slider re-derives its value from the pointer, so the handle would fly back and forth).
		slider.drag_ended.connect(func(_changed: bool) -> void:
			_sync_glb_rot_handles())
		row.add_child(slider)
		glb_sliders.append(slider)
		# 2026-08-21 ("slider không hiện giá trị") — numeric "<deg>°" readout, right-aligned fixed width so
		# the slider itself doesn't jitter/resize as the digit count changes (e.g. "5°" vs "-180°").
		var val_lbl := Label.new()
		val_lbl.text = "0°"
		val_lbl.add_theme_font_size_override("font_size", 10)
		val_lbl.custom_minimum_size = Vector2(34.0, 0.0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		glb_val_lbls.append(val_lbl)
	_glb_rot_x_slider = glb_sliders[0]
	_glb_rot_y_slider = glb_sliders[1]
	_glb_rot_z_slider = glb_sliders[2]
	_glb_rot_x_lbl = glb_val_lbls[0]
	_glb_rot_y_lbl = glb_val_lbls[1]
	_glb_rot_z_lbl = glb_val_lbls[2]
	var glb_reset_btn := Button.new()
	glb_reset_btn.text = "Reset Rotation"
	glb_reset_btn.add_theme_font_size_override("font_size", 10)
	glb_reset_btn.pressed.connect(_on_glb_reset_rotation)
	root.add_child(glb_reset_btn)
	# 2026-08-22 ("Reset vị trí hiện tại thành 0,0,0 rotation... sau này sẽ fine tune dựa trên tọa độ này"):
	# banks the CURRENT orientation as the new zero — the object/plume does not visibly move, the three
	# sliders just read 0/0/0 again so every later adjustment is a small readable delta from the pose you
	# just dialled in, instead of an opaque absolute. Distinct from "Reset Rotation" right above, which
	# actually rotates back to the banked zero.
	var glb_zero_btn := Button.new()
	glb_zero_btn.text = "Set 0° here"
	glb_zero_btn.add_theme_font_size_override("font_size", 10)
	glb_zero_btn.pressed.connect(_on_glb_set_zero_here)
	root.add_child(glb_zero_btn)
	_glb_view_section_nodes = [glb_sep, glb_hdr, glb_hint, glb_reset_btn, glb_zero_btn]
	_glb_view_section_nodes.append_array(glb_rows)
	for n: Control in _glb_view_section_nodes:
		n.visible = false   # shown by _refresh_glb_view_ui once an active (glb) creep is actually selected

	# THRUST POINTS section
	var tp_sep := HSeparator.new()
	root.add_child(tp_sep)
	var tp_hdr := Label.new()
	tp_hdr.text = "THRUST POINTS"
	tp_hdr.add_theme_font_size_override("font_size", 11)
	tp_hdr.modulate = Color(0.10, 0.90, 0.65)
	root.add_child(tp_hdr)

	var tp_scroll := ScrollContainer.new()
	tp_scroll.custom_minimum_size = Vector2(0.0, 150.0)
	tp_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(tp_scroll)
	_tp_vbox = VBoxContainer.new()
	_tp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_vbox.add_theme_constant_override("separation", 2)
	tp_scroll.add_child(_tp_vbox)

	# TP angle row
	_tp_angle_row = HBoxContainer.new()
	_tp_angle_row.visible = false
	_tp_angle_row.add_theme_constant_override("separation", 4)
	root.add_child(_tp_angle_row)
	var tpal := Label.new()
	tpal.text = "Dir:"
	tpal.add_theme_font_size_override("font_size", 10)
	tpal.custom_minimum_size = Vector2(24.0, 0.0)
	_tp_angle_row.add_child(tpal)
	_tp_angle_spin = SpinBox.new()
	_tp_angle_spin.min_value = -180.0
	_tp_angle_spin.max_value = 180.0
	_tp_angle_spin.step = 1.0
	_tp_angle_spin.suffix = "°"
	_tp_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_angle_spin.value_changed.connect(func(_v: float) -> void: _on_tp_angle_changed())
	_tp_angle_row.add_child(_tp_angle_spin)

	# 2026-08-21: the old single "TP Z" row that used to live here moved into the TRANSFORM panel and grew
	# into a full X/Y/Z group — see _build_ui's TRANSFORM section ("TP POS (3D, relative to object center)")
	# and _refresh_tp_pos3_ui. Left this comment as a signpost since a lot of the surrounding code predates it.
	# 2026-08-15: hidden unless the active creep actually has a thrust point — see _refresh_dynamic_panels()
	# (same "_*_angle_row excluded" reasoning as the FP section above).
	_tp_section_nodes = [tp_sep, tp_hdr, tp_scroll]

	# TENTACLE POINTS section — HIDDEN by design (replaced by the Vortex Points section below). Code kept intact
	# so existing tentacle layouts still load/save; the widgets are just collapsed via _tenp_section_nodes.
	var tn_sep := HSeparator.new()
	root.add_child(tn_sep)
	var tn_hdr := Label.new()
	tn_hdr.text = "TENTACLE POINTS"
	tn_hdr.add_theme_font_size_override("font_size", 11)
	tn_hdr.modulate = Color(0.80, 0.45, 1.0)
	root.add_child(tn_hdr)

	var tn_scroll := ScrollContainer.new()
	tn_scroll.custom_minimum_size = Vector2(0.0, 110.0)
	tn_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(tn_scroll)
	_tenp_vbox = VBoxContainer.new()
	_tenp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tenp_vbox.add_theme_constant_override("separation", 2)
	tn_scroll.add_child(_tenp_vbox)

	# TenP angle row
	_tenp_angle_row = HBoxContainer.new()
	_tenp_angle_row.visible = false
	_tenp_angle_row.add_theme_constant_override("separation", 4)
	root.add_child(_tenp_angle_row)
	var tnal := Label.new()
	tnal.text = "Dir:"
	tnal.add_theme_font_size_override("font_size", 10)
	tnal.custom_minimum_size = Vector2(24.0, 0.0)
	_tenp_angle_row.add_child(tnal)
	_tenp_angle_spin = SpinBox.new()
	_tenp_angle_spin.min_value = -180.0
	_tenp_angle_spin.max_value = 180.0
	_tenp_angle_spin.step = 1.0
	_tenp_angle_spin.suffix = "°"
	_tenp_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tenp_angle_spin.value_changed.connect(func(_v: float) -> void: _on_tenp_angle_changed())
	_tenp_angle_row.add_child(_tenp_angle_spin)
	# Collapse the whole Tentacle Points section (kept in the tree, just hidden).
	_tenp_section_nodes = [tn_sep, tn_hdr, tn_scroll]
	for n: Control in _tenp_section_nodes:
		n.visible = false

	# ── VORTEX POINTS section — each point anchors a spinning EnergyVortex VFX (no direction needed) ──
	root.add_child(HSeparator.new())
	var vx_hdr_row := HBoxContainer.new()
	vx_hdr_row.add_theme_constant_override("separation", 4)
	root.add_child(vx_hdr_row)
	var vx_hdr := Label.new()
	vx_hdr.text = "VORTEX POINTS"
	vx_hdr.add_theme_font_size_override("font_size", 11)
	vx_hdr.modulate = Color(0.55, 0.80, 1.0)
	vx_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vx_hdr_row.add_child(vx_hdr)
	var vx_copy := Button.new()
	vx_copy.text = "Copy"
	vx_copy.add_theme_font_size_override("font_size", 9)
	vx_copy.pressed.connect(_copy_vortex_style)
	vx_hdr_row.add_child(vx_copy)
	var vx_paste := Button.new()
	vx_paste.text = "Paste"
	vx_paste.add_theme_font_size_override("font_size", 9)
	vx_paste.pressed.connect(_paste_vortex_style)
	vx_hdr_row.add_child(vx_paste)

	var vx_scroll := ScrollContainer.new()
	vx_scroll.custom_minimum_size = Vector2(0.0, 96.0)
	vx_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(vx_scroll)
	_vortex_vbox = VBoxContainer.new()
	_vortex_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vortex_vbox.add_theme_constant_override("separation", 2)
	vx_scroll.add_child(_vortex_vbox)

	_vortex_lbl = Label.new()
	_vortex_lbl.text = "– select a VX –"
	_vortex_lbl.add_theme_font_size_override("font_size", 10)
	_vortex_lbl.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(_vortex_lbl)

	# Radius + Spin row
	var vxa_row := HBoxContainer.new()
	vxa_row.add_theme_constant_override("separation", 3)
	root.add_child(vxa_row)
	var vxr_lbl := Label.new()
	vxr_lbl.text = "Rad:"
	vxr_lbl.add_theme_font_size_override("font_size", 10)
	vxr_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	vxa_row.add_child(vxr_lbl)
	_vx_radius_spin = _mk_vxspin(vxa_row, 8.0, 240.0, 2.0)
	var vxs_lbl := Label.new()
	vxs_lbl.text = "Spin:"
	vxs_lbl.add_theme_font_size_override("font_size", 10)
	vxa_row.add_child(vxs_lbl)
	_vx_spin_spin = _mk_vxspin(vxa_row, -12.0, 12.0, 0.2)

	# Arms row
	var vxb_row := HBoxContainer.new()
	vxb_row.add_theme_constant_override("separation", 3)
	root.add_child(vxb_row)
	var vxn_lbl := Label.new()
	vxn_lbl.text = "Arms:"
	vxn_lbl.add_theme_font_size_override("font_size", 10)
	vxn_lbl.custom_minimum_size = Vector2(30.0, 0.0)
	vxb_row.add_child(vxn_lbl)
	_vx_arms_spin = _mk_vxspin(vxb_row, 1.0, 8.0, 1.0)

	# Gradient colors: Core → Mid → Outer
	var vxc_row := HBoxContainer.new()
	vxc_row.add_theme_constant_override("separation", 3)
	root.add_child(vxc_row)
	_vx_col_core_btn  = _mk_vxcol_vbox(vxc_row, "Core",  Color(0.75, 0.92, 1.0, 1.0))
	_vx_col_mid_btn   = _mk_vxcol_vbox(vxc_row, "Mid",   Color(0.30, 0.50, 1.0, 0.9))
	_vx_col_outer_btn = _mk_vxcol_vbox(vxc_row, "Outer", Color(0.55, 0.20, 0.95, 0.0))
	# 2026-08-15: this whole VORTEX POINTS section is now hidden unless the active creep actually has a
	# vortex point — see _refresh_dynamic_panels().
	_vortex_section_nodes = [vx_hdr_row, vx_scroll, _vortex_lbl, vxa_row, vxb_row, vxc_row]

	# ── LED POINTS section (2026-08-15) — each point anchors a small glowing/blinking light (LedLight) ──
	root.add_child(HSeparator.new())
	var led_hdr_row := HBoxContainer.new()
	led_hdr_row.add_theme_constant_override("separation", 4)
	root.add_child(led_hdr_row)
	var led_hdr := Label.new()
	led_hdr.text = "LED POINTS"
	led_hdr.add_theme_font_size_override("font_size", 11)
	led_hdr.modulate = Color(1.0, 0.85, 0.35)
	led_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	led_hdr_row.add_child(led_hdr)
	var led_copy := Button.new()
	led_copy.text = "Copy"
	led_copy.add_theme_font_size_override("font_size", 9)
	led_copy.pressed.connect(_copy_led_style)
	led_hdr_row.add_child(led_copy)
	var led_paste := Button.new()
	led_paste.text = "Paste"
	led_paste.add_theme_font_size_override("font_size", 9)
	led_paste.pressed.connect(_paste_led_style)
	led_hdr_row.add_child(led_paste)

	var led_scroll := ScrollContainer.new()
	led_scroll.custom_minimum_size = Vector2(0.0, 72.0)
	led_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(led_scroll)
	_led_vbox = VBoxContainer.new()
	_led_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_led_vbox.add_theme_constant_override("separation", 2)
	led_scroll.add_child(_led_vbox)

	_led_lbl = Label.new()
	_led_lbl.text = "– select a LED –"
	_led_lbl.add_theme_font_size_override("font_size", 10)
	_led_lbl.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(_led_lbl)

	# W / H row
	var ledwh_row := HBoxContainer.new()
	ledwh_row.add_theme_constant_override("separation", 3)
	root.add_child(ledwh_row)
	var ledw_lbl := Label.new()
	ledw_lbl.text = "W:"
	ledw_lbl.add_theme_font_size_override("font_size", 10)
	ledw_lbl.custom_minimum_size = Vector2(16.0, 0.0)
	ledwh_row.add_child(ledw_lbl)
	_led_w_spin = _mk_ledspin(ledwh_row, 1.0, 200.0, 1.0)
	var ledh_lbl := Label.new()
	ledh_lbl.text = "H:"
	ledh_lbl.add_theme_font_size_override("font_size", 10)
	ledwh_row.add_child(ledh_lbl)
	_led_h_spin = _mk_ledspin(ledwh_row, 1.0, 200.0, 1.0)

	# Color + Intensity row
	var ledci_row := HBoxContainer.new()
	ledci_row.add_theme_constant_override("separation", 3)
	root.add_child(ledci_row)
	var ledc_lbl := Label.new()
	ledc_lbl.text = "Color:"
	ledc_lbl.add_theme_font_size_override("font_size", 10)
	ledci_row.add_child(ledc_lbl)
	_led_col_btn = ColorPickerButton.new()
	_led_col_btn.color = Color(1.0, 0.85, 0.35, 1.0)
	_led_col_btn.custom_minimum_size = Vector2(0.0, 22.0)
	_led_col_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_led_col_btn.color_changed.connect(func(_c: Color) -> void: _on_led_changed())
	ledci_row.add_child(_led_col_btn)
	var ledi_lbl := Label.new()
	ledi_lbl.text = "Intensity:"
	ledi_lbl.add_theme_font_size_override("font_size", 10)
	ledci_row.add_child(ledi_lbl)
	_led_intensity_spin = _mk_ledspin(ledci_row, 0.0, 3.0, 0.1)

	# Blink (Hz) slider — 0 = steady, 60 = 60Hz flicker
	var ledb_row := HBoxContainer.new()
	ledb_row.add_theme_constant_override("separation", 4)
	root.add_child(ledb_row)
	var ledb_lbl := Label.new()
	ledb_lbl.text = "Blink:"
	ledb_lbl.add_theme_font_size_override("font_size", 10)
	ledb_lbl.custom_minimum_size = Vector2(30.0, 0.0)
	ledb_row.add_child(ledb_lbl)
	_led_blink_slider = HSlider.new()
	_led_blink_slider.min_value = 0.0
	_led_blink_slider.max_value = 60.0
	_led_blink_slider.step = 1.0
	_led_blink_slider.value = 0.0
	_led_blink_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_led_blink_slider.value_changed.connect(func(_v: float) -> void:
		_led_blink_lbl.text = "%dHz" % int(_led_blink_slider.value)
		_on_led_changed()
	)
	ledb_row.add_child(_led_blink_slider)
	_led_blink_lbl = Label.new()
	_led_blink_lbl.text = "0Hz"
	_led_blink_lbl.add_theme_font_size_override("font_size", 10)
	_led_blink_lbl.custom_minimum_size = Vector2(28.0, 0.0)
	ledb_row.add_child(_led_blink_lbl)

	# Phase + Rotate row (2026-08-15) — Phase offsets this LED's own blink cycle (stagger across a row of
	# LEDs head→tail for a running "wave" signal strip); Rotate is a plain extra spin on top of whatever the
	# anchor (body segment) orientation already applies — mainly useful once W≠H (an elongated light).
	var ledpr_row := HBoxContainer.new()
	ledpr_row.add_theme_constant_override("separation", 3)
	root.add_child(ledpr_row)
	var ledp_lbl := Label.new()
	ledp_lbl.text = "Phase:"
	ledp_lbl.add_theme_font_size_override("font_size", 10)
	ledpr_row.add_child(ledp_lbl)
	_led_phase_spin = _mk_ledspin(ledpr_row, 0.0, 360.0, 5.0)
	_led_phase_spin.suffix = "°"
	var ledr_lbl := Label.new()
	ledr_lbl.text = "Rotate:"
	ledr_lbl.add_theme_font_size_override("font_size", 10)
	ledpr_row.add_child(ledr_lbl)
	_led_rotate_spin = _mk_ledspin(ledpr_row, 0.0, 360.0, 5.0)
	_led_rotate_spin.suffix = "°"

	# 2026-08-15, per user report ("chỉnh 1 loạt led phase lệch 5 độ nhưng vẫn nháy cùng nhịp"): setting Phase
	# one LED at a time via multi-select is exactly the trap that produces this — select more than one row and
	# every field (including Phase) applies the SAME value to ALL of them at once (by design, matches how
	# Vortex's own multi-select-apply already works), so "select several, drag Phase" can never produce a
	# staggered wave — it just overwrites them all identically, which reads as "no offset at all". Added a
	# one-click alternative that can't hit that trap: assigns phase_deg = index × step to EVERY LED of this
	# creep in placement order, regardless of what's currently selected.
	var ledw_row := HBoxContainer.new()
	ledw_row.add_theme_constant_override("separation", 3)
	root.add_child(ledw_row)
	var ledws_lbl := Label.new()
	ledws_lbl.text = "Wave step:"
	ledws_lbl.add_theme_font_size_override("font_size", 10)
	ledw_row.add_child(ledws_lbl)
	_led_wave_step_spin = _mk_ledspin(ledw_row, 0.0, 180.0, 1.0)
	_led_wave_step_spin.value = 20.0
	_led_wave_step_spin.suffix = "°"
	var led_wave_btn := Button.new()
	led_wave_btn.text = "Apply Wave"
	led_wave_btn.add_theme_font_size_override("font_size", 10)
	led_wave_btn.pressed.connect(_apply_led_wave)
	ledw_row.add_child(led_wave_btn)

	# Hidden unless the active creep actually has a LED point — see _refresh_dynamic_panels().
	_led_section_nodes = [led_hdr_row, led_scroll, _led_lbl, ledwh_row, ledci_row, ledb_row, ledpr_row, ledw_row]

	# ── PLUME STYLE section ──
	root.add_child(HSeparator.new())
	var pe_hdr_row := HBoxContainer.new()
	pe_hdr_row.add_theme_constant_override("separation", 4)
	root.add_child(pe_hdr_row)
	var pe_lbl := Label.new()
	pe_lbl.text = "PLUME STYLE"
	pe_lbl.add_theme_font_size_override("font_size", 10)
	pe_lbl.modulate = Color(0.55, 0.90, 1.0)
	pe_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pe_hdr_row.add_child(pe_lbl)
	var pe_copy := Button.new()
	pe_copy.text = "Copy"
	pe_copy.add_theme_font_size_override("font_size", 9)
	pe_copy.pressed.connect(_copy_plume_style)
	pe_hdr_row.add_child(pe_copy)
	var pe_paste := Button.new()
	pe_paste.text = "Paste"
	pe_paste.add_theme_font_size_override("font_size", 9)
	pe_paste.pressed.connect(_paste_plume_style)
	pe_hdr_row.add_child(pe_paste)
	var pe_reset := Button.new()
	pe_reset.text = "Reset"
	pe_reset.add_theme_font_size_override("font_size", 9)
	pe_reset.pressed.connect(_reset_plume_style)
	pe_hdr_row.add_child(pe_reset)

	_plume_tp_label = Label.new()
	_plume_tp_label.text = "– select a TP –"
	_plume_tp_label.add_theme_font_size_override("font_size", 10)
	_plume_tp_label.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(_plume_tp_label)

	# Velocity min / max
	var vel_row := HBoxContainer.new()
	vel_row.add_theme_constant_override("separation", 3)
	root.add_child(vel_row)
	var vel_lbl := Label.new()
	vel_lbl.text = "Vel:"
	vel_lbl.add_theme_font_size_override("font_size", 10)
	vel_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	vel_row.add_child(vel_lbl)
	_plume_vel_min_spin = _mk_pspin(vel_row, 0.0, 600.0, 5.0)
	_plume_vel_max_spin = _mk_pspin(vel_row, 0.0, 600.0, 5.0)

	# Lifetime + Spread
	var ls_row := HBoxContainer.new()
	ls_row.add_theme_constant_override("separation", 3)
	root.add_child(ls_row)
	var life_lbl := Label.new()
	life_lbl.text = "Life:"
	life_lbl.add_theme_font_size_override("font_size", 10)
	life_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	ls_row.add_child(life_lbl)
	_plume_life_spin = _mk_pspin(ls_row, 0.05, 3.0, 0.05)
	var spr_lbl := Label.new()
	spr_lbl.text = "Spr:"
	spr_lbl.add_theme_font_size_override("font_size", 10)
	ls_row.add_child(spr_lbl)
	_plume_spread_spin = _mk_pspin(ls_row, 0.0, 90.0, 1.0)

	# Scale min / max
	var sc_row := HBoxContainer.new()
	sc_row.add_theme_constant_override("separation", 3)
	root.add_child(sc_row)
	var sc_lbl := Label.new()
	sc_lbl.text = "Sc:"
	sc_lbl.add_theme_font_size_override("font_size", 10)
	sc_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	sc_row.add_child(sc_lbl)
	_plume_sc_min_spin = _mk_pspin(sc_row, 0.1, 8.0, 0.1)
	_plume_sc_max_spin = _mk_pspin(sc_row, 0.1, 8.0, 0.1)

	# Gradient colors: Core → Flame → Cool
	var col_row := HBoxContainer.new()
	col_row.add_theme_constant_override("separation", 3)
	root.add_child(col_row)
	_plume_col_core_btn  = _mk_pcol_vbox(col_row, "Core",  Color(1.0, 0.95, 0.7, 1.0))
	_plume_col_flame_btn = _mk_pcol_vbox(col_row, "Flame", Color(1.0, 0.6,  0.2, 1.0))
	_plume_col_cool_btn  = _mk_pcol_vbox(col_row, "Cool",  Color(0.45, 0.6, 1.0, 0.85))

	_save_confirm_dlg = ConfirmationDialog.new()
	_save_confirm_dlg.ok_button_text = "Overwrite"
	add_child(_save_confirm_dlg)

	# HUD edit (and any editor with no firing/thrust geometry) hides every section below the
	# LAYERS list (root child 0). The widgets stay built so their refreshers never null-crash.
	if not _uses_points():
		for i: int in range(1, root.get_child_count()):
			var sec := root.get_child(i) as CanvasItem
			if sec != null:
				sec.visible = false

# ── RIGHT panel ────────────────────────────────────────────────────────────────

## Builds the VIEW CUBE gizmo — a real 3D cube in its own little SubViewport, sat top-right just left of the
## weapon-edit control panel. Dragging it orbits the angle every `.glb` preview is rendered from (yaw +
## pitch), the way the ViewCube / navigation gizmo does in 3ds Max or Blender. Right-click resets to the
## default 3/4 view. See `_view_yaw`/`_view_pitch`'s own note for why the plume overlay's camera stays
## top-down and is deliberately NOT orbited by this.
func _build_view_cube() -> void:
	var rig := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	_viewcube_vp = SubViewport.new()
	_viewcube_vp.size = Vector2i(int(VIEWCUBE_PX), int(VIEWCUBE_PX))
	_viewcube_vp.transparent_bg = true
	_viewcube_vp.own_world_3d = true
	_viewcube_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewcube_vp)
	rig.build_lighting(_viewcube_vp)

	# Fixed camera looking down -Z; the CUBE turns instead, which is what makes it read as a compass for the
	# current view rather than just another spinning object.
	var cam := Camera3D.new()
	_viewcube_vp.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.6
	cam.near = 0.05
	cam.far = 40.0
	cam.look_at_from_position(Vector3(0.0, 0.0, 8.0), Vector3.ZERO, Vector3.UP)

	_viewcube_pivot = Node3D.new()
	_viewcube_vp.add_child(_viewcube_pivot)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.70, 0.86)
	mat.roughness = 0.55
	box.material = mat
	mi.mesh = box
	_viewcube_pivot.add_child(mi)

	_viewcube_rect = TextureRect.new()
	_viewcube_rect.texture = _viewcube_vp.get_texture()
	# Same TextureRect minimum-size clamp guarded elsewhere in this file — explicit so the size sticks.
	_viewcube_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewcube_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_viewcube_rect.size = Vector2(VIEWCUBE_PX, VIEWCUBE_PX)
	# Top-right, immediately LEFT of the control panel (which sits at vp_w - CTRL_PANEL_W - 20, y 44).
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_viewcube_rect.position = Vector2(vp_w - CTRL_PANEL_W - 20.0 - VIEWCUBE_PX - 12.0, 44.0)
	_viewcube_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewcube_rect.tooltip_text = "Drag: orbit the 3D preview view
Right-click: reset to default angle"
	_viewcube_rect.z_index = 60
	_viewcube_rect.gui_input.connect(_on_viewcube_input)
	add_child(_viewcube_rect)

	# "Game view" — snaps to the EXACT angle the weapon is drawn at in play: straight top-down, which is what
	# every live rig uses (glb_topdown_rig.gd::make_camera). Right-clicking the cube is the other reset, back
	# to the 3/4 authoring view; this one is the one you check your work against.
	_viewcube_btn = Button.new()
	_viewcube_btn.text = "Game view"
	_viewcube_btn.add_theme_font_size_override("font_size", 10)
	_viewcube_btn.size = Vector2(VIEWCUBE_PX, 22.0)
	_viewcube_btn.position = _viewcube_rect.position + Vector2(0.0, VIEWCUBE_PX + 4.0)
	_viewcube_btn.tooltip_text = "Reset to the in-game camera angle (straight top-down)"
	_viewcube_btn.z_index = 60
	_viewcube_btn.pressed.connect(_on_viewcube_game_view)
	add_child(_viewcube_btn)
	_apply_view_angle()

## Snap to the in-game camera angle — see the button's own comment in _build_view_cube.
func _on_viewcube_game_view() -> void:
	_view_yaw = 0.0
	_view_pitch = PI * 0.5   # exactly straight down; _view_up() supplies the matching up-vector
	_apply_view_angle()

func _on_viewcube_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_viewcube_drag = mb.pressed
			_viewcube_rect.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_view_yaw = 0.0
			_view_pitch = deg_to_rad(GLB_DEFAULT_PITCH_DEG)
			_apply_view_angle()
			_viewcube_rect.accept_event()
	elif event is InputEventMouseMotion and _viewcube_drag:
		var mm := event as InputEventMouseMotion
		# 2026-08-22 ("kéo sang phải thì cube lại xoay sang trái"): both axes are NEGATIVE of the raw drag,
		# because `_view_yaw`/`_view_pitch` describe where the CAMERA orbits to, while the hand is grabbing
		# the CUBE. Dragging right should carry the cube's front face right, which means the camera swings
		# the other way — feeding the drag straight into the camera angle spun it backwards.
		_view_yaw = wrapf(_view_yaw - mm.relative.x * 0.012, -PI, PI)
		# Clamped just short of straight up/down: at exactly ±90° the camera's up-vector becomes parallel to
		# its own look direction and `look_at_from_position()` can't build a basis from it. The "Game view"
		# button below reaches exactly 90° a different way — see _view_up().
		_view_pitch = clampf(_view_pitch + mm.relative.y * 0.012, deg_to_rad(-88.0), deg_to_rad(88.0))
		_apply_view_angle()
		_viewcube_rect.accept_event()

## Points every built `.glb` preview camera at the current yaw/pitch, and turns the gizmo cube to match.
## Framing is untouched: the previews are fitted to the model's BOUNDING SPHERE (see _load_glb_topdown_tex),
## which is view-invariant — that is exactly why orbiting the camera can't crop anything.
func _apply_view_angle() -> void:
	if _viewcube_pivot != null and is_instance_valid(_viewcube_pivot):
		# Inverse of the camera orbit, so the cube face you are looking at is the one facing you.
		_viewcube_pivot.rotation = Vector3(_view_pitch, -_view_yaw, 0.0)
	for path: String in _glb_preview_cache:
		var rig_data: Dictionary = _glb_preview_cache[path]
		var cam: Camera3D = rig_data.get("cam")
		if cam == null or not is_instance_valid(cam):
			continue
		_fit_preview_cam(rig_data)
	# The assembled 3D scene (models + plumes) is what the cube really orbits — rebuild it at the new angle.
	# Purely a re-render: it reads EO positions but never writes them, so spinning around to check alignment
	# can't disturb the layout. See _refresh_plume3d_preview's own header.
	_refresh_plume3d_preview()   # re-renders the scene AND re-syncs the flat thumbnails, see there

## Hides the flat EO thumbnail of every part the 3D overlay is drawing, at EVERY view angle.
##
## 2026-08-22 ("có sự sai lệch giữa weapon hiển thị trên arena và trong weapon edit"): this used to keep the
## thumbnails at Game view and swap to the 3D scene only once orbited — two renderers, and the thumbnail one
## did not agree with the game. A thumbnail is its own preview camera's bounding-sphere fit plus
## GLB_FRAME_MARGIN padding, stretched to whatever the EO rect is; the overlay draws the model at the arena's
## own `target_px` at 1 unit = 1 canvas px. Same model, two different apparent sizes, and swapping between
## them at 90° of pitch made the discrepancy look like a rendering glitch rather than a scale mismatch.
## Now the overlay is the only renderer for a 3D part, so what the editor shows IS the arena's geometry.
##
## Scoped to the parts the overlay actually covers (the active group). A glb part outside it — another
## group's, or one placed while a 2D weapon is active — keeps its thumbnail, or it would vanish entirely.
## The EO NODES stay alive regardless: only the texture is hidden, so selection, outlines, dragging and
## every other 2D interaction keep working untouched.
func _sync_flat_thumbnails() -> void:
	var covered := {}
	if not _preview_plumes3d.is_empty() and not _active_creep.is_empty():
		var root_name: String = _active_creep
		var par: String = _creep_parents.get(_active_creep, "")
		if not par.is_empty():
			root_name = par
		for cname: String in _group_render_names(root_name):
			covered[cname] = true
	for cname: String in _placed:
		var eo: EditableObjectNode = _placed[cname]
		if eo == null or not is_instance_valid(eo) or eo.texture_rect == null:
			continue
		eo.texture_rect.visible = not covered.has(cname)

## True when the view cube is at the straight-down in-game angle — the one orientation where the flat 2D
## canvas and the real 3D scene coincide exactly.
func _at_game_view() -> bool:
	return absf(absf(_view_pitch) - PI * 0.5) < 0.001

## Positions `rig_data`'s camera at the current view angle and fits its ortho size TIGHTLY to the model's
## silhouette AS SEEN FROM THERE. 2026-08-22 ("object thì khá nhỏ so với khung trắng"): the previous framing
## used the model's bounding SPHERE — chosen because it is rotation-invariant, so nothing could ever be
## cropped — but a sphere also covers the model's full 3D diagonal, most of which is not in the silhouette at
## all for a flat-ish part. Measured result: the model filled only ~4% of its own texture, leaving a huge
## empty square around it (and making chain segments look far apart even at minimum Spacing, because the
## EO rects were sized to that padding rather than to the visible model). Re-fitting per view angle keeps it
## tight AND uncropped; the texture stays square so `eo._aspect_ratio` never changes underfoot.
func _fit_preview_cam(rig_data: Dictionary) -> void:
	var cam: Camera3D = rig_data.get("cam")
	var model: Node3D = rig_data.get("model")
	if cam == null or not is_instance_valid(cam) or model == null or not is_instance_valid(model):
		return
	cam.look_at_from_position(_view_dir() * float(rig_data.get("dist", 100.0)), Vector3.ZERO, _view_up())
	# Keep the headlamp on the camera. It is stored in the rig dict but was only ever aimed once, at build
	# time, so orbiting left it pointing at the old angle and the thumbnail progressively darkened. Only
	# reachable for a glb part the 3D overlay isn't covering (see _sync_flat_thumbnails), but same bug.
	var hl: DirectionalLight3D = rig_data.get("headlamp")
	if hl != null and is_instance_valid(hl):
		hl.rotation = cam.rotation
	var rig := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	# 2026-08-23 ("vũ khí bị clip trong 1 frame vuông nhỏ", ND-Aliwa-Bmr): measured WITH the object's own
	# mount rotation, not at rotation zero. The model hangs off `rot_pivot`, which `silhouette_extent()`
	# knows nothing about — so a part dialled to a big mount angle (Aliwa sits at −79/95/105°) presented a
	# far wider silhouette than the frame it was fitted to, and its ends were sliced off square. Passing the
	# pivot's transform as `pre` restores the "nothing can leave the frame" guarantee the bounding-sphere fit
	# used to give, while keeping the tight per-view fit that replaced it. `_glb_apply_rotation()` re-runs
	# this on every rotation change so the frame keeps up while a slider is being dragged.
	var pre := Transform3D.IDENTITY
	var rot_pivot: Node3D = rig_data.get("rot_pivot")
	if rot_pivot != null and is_instance_valid(rot_pivot):
		pre = rot_pivot.transform
	var ext: Vector2 = rig.silhouette_extent(model, cam.global_transform.basis.x, cam.global_transform.basis.y, pre)
	cam.size = maxf(maxf(ext.x, ext.y), 0.001) * GLB_FRAME_MARGIN

## Unit vector from the origin toward the camera for the current yaw/pitch.
func _view_dir() -> Vector3:
	var cp := cos(_view_pitch)
	return Vector3(sin(_view_yaw) * cp, sin(_view_pitch), cos(_view_yaw) * cp)

## Camera up-vector for the current pitch. Straight down (±90°) makes the usual `Vector3.UP` parallel to the
## look direction, which `look_at_from_position()` cannot resolve — so at that exact angle we switch to the
## SAME up the live gameplay rigs use (`glb_topdown_rig.gd::make_camera()`'s `(0,0,-1)`), which is what makes
## the "Game view" button land on precisely the angle the weapon is drawn at in play rather than merely near
## it. Free dragging never gets here: it is clamped to ±88°.
func _view_up() -> Vector3:
	if absf(absf(_view_pitch) - PI * 0.5) < 0.001:
		return Vector3(0.0, 0.0, -1.0)
	return Vector3.UP

func _build_ctrl_panel() -> void:
	_ctrl_panel = Panel.new()
	var _vp_w: float = get_viewport().get_visible_rect().size.x
	_ctrl_panel.size     = Vector2(CTRL_PANEL_W, 730.0)
	_ctrl_panel.position = Vector2(_vp_w - CTRL_PANEL_W - 20.0, 44.0)
	add_child(_ctrl_panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	_ctrl_panel.add_child(root)

	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0.0, 34.0)
	title_bar.gui_input.connect(_on_ctrl_title_input)
	root.add_child(title_bar)
	var tl := Label.new()
	tl.text = _title()
	tl.add_theme_font_size_override("font_size", 13)
	tl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(tl)

	_add_section(root, _palette_title())
	if _show_map_selector():
		var map_row := HBoxContainer.new()
		map_row.add_theme_constant_override("separation", 4)
		root.add_child(map_row)
		var map_lbl := Label.new()
		map_lbl.text = "Map:"
		map_lbl.add_theme_font_size_override("font_size", 10)
		map_lbl.custom_minimum_size = Vector2(30.0, 0.0)
		map_row.add_child(map_lbl)
		_map_option = OptionButton.new()
		_map_option.add_theme_font_size_override("font_size", 10)
		_map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for m: Dictionary in MAP_REGISTRY:
			_map_option.add_item(String(m["name"]))
		_map_option.selected = 0
		_map_option.item_selected.connect(_on_map_selected)
		map_row.add_child(_map_option)
	var creep_scroll := ScrollContainer.new()
	creep_scroll.custom_minimum_size = Vector2(0.0, 240.0)
	creep_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	creep_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(creep_scroll)
	# Icon grid (fleet-edit style) instead of a list of text buttons.
	var creep_grid := GridContainer.new()
	creep_grid.columns = 4
	creep_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creep_grid.add_theme_constant_override("h_separation", 4)
	creep_grid.add_theme_constant_override("v_separation", 4)
	creep_scroll.add_child(creep_grid)
	_creep_btn_vbox = creep_grid

	root.add_child(HSeparator.new())

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 3)
	root.add_child(mode_row)

	_grid_btn = Button.new()
	_grid_btn.text = "Grid"
	_grid_btn.toggle_mode = true
	_grid_btn.add_theme_font_size_override("font_size", 12)
	_grid_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_btn.pressed.connect(_toggle_grid_mode)
	mode_row.add_child(_grid_btn)

	_add_fp_btn = Button.new()
	_add_fp_btn.text = "Add FP"
	_add_fp_btn.toggle_mode = true
	_add_fp_btn.add_theme_font_size_override("font_size", 12)
	_add_fp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_fp_btn.pressed.connect(_toggle_adding_firepoint)
	mode_row.add_child(_add_fp_btn)

	_add_tp_btn = Button.new()
	_add_tp_btn.text = "Add TP"
	_add_tp_btn.toggle_mode = true
	_add_tp_btn.add_theme_font_size_override("font_size", 12)
	_add_tp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_tp_btn.pressed.connect(_toggle_adding_thrustpoint)
	mode_row.add_child(_add_tp_btn)

	_add_tenp_btn = Button.new()
	_add_tenp_btn.text = "Add TenP"
	_add_tenp_btn.toggle_mode = true
	_add_tenp_btn.add_theme_font_size_override("font_size", 12)
	_add_tenp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_tenp_btn.pressed.connect(_toggle_adding_tentaclepoint)
	mode_row.add_child(_add_tenp_btn)

	_add_vortex_btn = Button.new()
	_add_vortex_btn.text = "Add Vortex"
	_add_vortex_btn.toggle_mode = true
	_add_vortex_btn.add_theme_font_size_override("font_size", 12)
	_add_vortex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_vortex_btn.pressed.connect(_toggle_adding_vortexpoint)
	mode_row.add_child(_add_vortex_btn)

	_add_led_btn = Button.new()
	_add_led_btn.text = "Add Led"
	_add_led_btn.toggle_mode = true
	_add_led_btn.add_theme_font_size_override("font_size", 12)
	_add_led_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_led_btn.pressed.connect(_toggle_adding_ledpoint)
	mode_row.add_child(_add_led_btn)

	# Grid + TenP buttons hidden by design (code kept). Add Vortex replaces TenP in the workflow.
	_grid_btn.visible     = false
	_add_tenp_btn.visible = false
	# Editors with no point geometry (HUD edit) hide the whole Add-FP/TP/Vortex/Led row.
	if not _uses_points():
		mode_row.visible = false

	root.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 3)
	root.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.add_theme_font_size_override("font_size", 12)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_layout)
	btn_row.add_child(save_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.add_theme_font_size_override("font_size", 12)
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_btn.disabled = true
	_delete_btn.pressed.connect(_delete_selected)
	btn_row.add_child(_delete_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(_request_close)
	root.add_child(close_btn)

	# ── TRANSFORM section (X, Y, W, H, Z + zoom slider) ──
	root.add_child(HSeparator.new())
	var xf_hdr := Label.new()
	xf_hdr.text = "TRANSFORM"
	xf_hdr.add_theme_font_size_override("font_size", 10)
	xf_hdr.modulate = Color(0.60, 0.63, 0.76)
	root.add_child(xf_hdr)

	var pos_row := HBoxContainer.new()
	pos_row.add_theme_constant_override("separation", 3)
	root.add_child(pos_row)
	_pos_x_spin = _small_spin(pos_row, "X", -4000.0, 4000.0, _on_pos_spin_changed)
	_pos_y_spin = _small_spin(pos_row, "Y", -4000.0, 4000.0, _on_pos_spin_changed)

	var sz_row := HBoxContainer.new()
	sz_row.add_theme_constant_override("separation", 3)
	root.add_child(sz_row)
	_sz_w_spin = _small_spin(sz_row, "W", 1.0, 2000.0, _on_w_spin_changed)
	_sz_h_spin = _small_spin(sz_row, "H", 1.0, 2000.0, _on_h_spin_changed)

	var z_row := HBoxContainer.new()
	z_row.add_theme_constant_override("separation", 3)
	root.add_child(z_row)
	_z_spin = _small_spin(z_row, "Z", -500.0, 500.0)
	var z_spacer := Control.new()
	z_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	z_row.add_child(z_spacer)

	# TP POS (3D, relative to object center) — 2026-08-21, "khung Transform cũng vậy... XYZ di chuyển so với
	# gốc là tâm object weapon". Context-switches with the SAME panel's W/H: enabled+meaningful ONLY when a
	# TP is selected on a .glb creep (see _refresh_transform_panel's tail) — X/Y/Z here are real "px" offsets
	# from the model's own center (0,0,0 = dead center), NOT the raw SS-space `pos`/`z` fields the data is
	# still actually stored as (see _tp_xyz_get/_tp_xyz_set) — converting through the SAME frac formula every
	# other TP consumer (_glb_refresh_tp_gizmos, arena_weapons.gd's 3D plume) already uses, so this is purely
	# a friendlier VIEW of the existing data, not a new storage format.
	_tp_pos3_row = HBoxContainer.new()
	_tp_pos3_row.visible = false
	_tp_pos3_row.add_theme_constant_override("separation", 3)
	root.add_child(_tp_pos3_row)
	_tp_x3_spin = _small_spin(_tp_pos3_row, "X", -500.0, 500.0, _on_tp_xyz3_changed)
	_tp_y3_spin = _small_spin(_tp_pos3_row, "Y", -500.0, 500.0, _on_tp_xyz3_changed)
	_tp_z3_spin = _small_spin(_tp_pos3_row, "Z", -500.0, 500.0, _on_tp_xyz3_changed)

	_tp_bone_row = HBoxContainer.new()
	_tp_bone_row.visible = false
	_tp_bone_row.add_theme_constant_override("separation", 4)
	root.add_child(_tp_bone_row)
	var bone_lbl := Label.new()
	bone_lbl.text = "Bone:"
	bone_lbl.add_theme_font_size_override("font_size", 10)
	bone_lbl.custom_minimum_size = Vector2(34.0, 0.0)
	_tp_bone_row.add_child(bone_lbl)
	_tp_bone_option = OptionButton.new()
	_tp_bone_option.add_theme_font_size_override("font_size", 10)
	_tp_bone_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_bone_option.tooltip_text = "Bind this thrust point to a bone — its plume then follows that bone\nthrough every animation. \"(none)\" keeps it fixed to the model centre."
	_tp_bone_option.item_selected.connect(_on_tp_bone_selected)
	_tp_bone_row.add_child(_tp_bone_option)

	# Zoom slider 50%–200%
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	root.add_child(zoom_row)
	var zoom_lbl := Label.new()
	zoom_lbl.text = "Zoom:"
	zoom_lbl.add_theme_font_size_override("font_size", 10)
	zoom_lbl.custom_minimum_size = Vector2(34.0, 0.0)
	zoom_row.add_child(zoom_lbl)
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 50.0
	_zoom_slider.max_value = 200.0
	_zoom_slider.step      = 1.0
	_zoom_slider.value     = 100.0
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.value_changed.connect(_on_zoom_slider_changed)
	zoom_row.add_child(_zoom_slider)
	_zoom_pct_lbl = Label.new()
	_zoom_pct_lbl.text = "100%"
	_zoom_pct_lbl.add_theme_font_size_override("font_size", 10)
	_zoom_pct_lbl.custom_minimum_size = Vector2(36.0, 0.0)
	_zoom_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_row.add_child(_zoom_pct_lbl)

	# Subclass extras (e.g. HUD-edit Blend dropdown) appended below the TRANSFORM block.
	_build_extra_controls(root)
	_build_chain_controls(root)

func _add_section(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.60, 0.63, 0.76)
	parent.add_child(lbl)

func _spin(parent: HBoxContainer, prefix: String, mn: float, mx: float, cb: Callable = Callable()) -> SpinBox:
	var lbl := Label.new()
	lbl.text = prefix + ":"
	lbl.custom_minimum_size = Vector2(18.0, 0.0)
	parent.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = 1.0
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if cb.is_valid():
		sb.value_changed.connect(func(_v: float) -> void: cb.call())
	else:
		sb.value_changed.connect(func(_v: float) -> void: _on_spin_changed())
	parent.add_child(sb)
	return sb

func _small_spin(parent: HBoxContainer, prefix: String, mn: float, mx: float, cb: Callable = Callable()) -> SpinBox:
	var lbl := Label.new()
	lbl.text = prefix + ":"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.custom_minimum_size = Vector2(14.0, 0.0)
	parent.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = 1.0
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 10)
	if cb.is_valid():
		sb.value_changed.connect(func(_v: float) -> void: cb.call())
	else:
		sb.value_changed.connect(func(_v: float) -> void: _on_spin_changed())
	parent.add_child(sb)
	return sb

func _build_creep_buttons() -> void:
	for child in _creep_btn_vbox.get_children():
		child.queue_free()
	_creep_buttons.clear()
	for creep_name: String in _all_creep_names:
		# Parented parts (squid tentacles, auto-grouped Head/Body/Tail sets, …) don't get their own palette
		# cell — they're "1 enemy" together with their group root, reached via the LAYERS panel once that
		# root is active (2026-08-13, matches _refresh_layer_list()'s existing root+children split).
		if not String(_creep_parents.get(creep_name, "")).is_empty():
			continue
		# Icon cell (fleet-edit style): a 46px toggle Button with the enemy thumbnail; tooltip = name.
		var btn := Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(46.0, 46.0)
		btn.tooltip_text = creep_name
		btn.clip_contents = true
		var tex := _creep_icon_tex(creep_name)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.offset_left = 3; tr.offset_top = 3; tr.offset_right = -3; tr.offset_bottom = -3
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(tr)
		else:
			btn.text = creep_name.substr(0, 4)
			btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(_set_active_creep.bind(creep_name))
		_creep_btn_vbox.add_child(btn)
		_creep_buttons[creep_name] = btn

## Load a thumbnail texture for a creep name (first matching file in the enemies folder).
func _creep_icon_tex(creep_name: String) -> Texture2D:
	for folder: String in _folders():
		for ext: String in ["glb", "png", "gif", "jpg", "jpeg"]:   # glb first — see _load_or_create_creep
			var path := folder + creep_name + "." + ext
			if FileAccess.file_exists(path) or ResourceLoader.exists(path):
				var tex := _load_full_tex(path)
				if tex != null:
					return tex
	return null

# ── Parent / child grouping ────────────────────────────────────────────────────

# ── Layer list (left panel) ────────────────────────────────────────────────────

func _refresh_layer_list() -> void:
	for child in _asset_vbox.get_children():
		child.queue_free()
	if _active_creep.is_empty():
		return
	# Find the group root (active or its parent)
	var root_name: String = _active_creep
	var par: String = _creep_parents.get(_active_creep, "")
	if not par.is_empty():
		root_name = par
	# Does this group have children? (controls whether the collapse toggle shows)
	var has_children := false
	for cname: String in _all_creep_names:
		if _creep_parents.get(cname, "") == root_name:
			has_children = true
			break
	var root_eo: EditableObjectNode = _placed.get(root_name, null)
	if not has_children:
		# Standalone creep, no parts — unchanged single-row behavior, full name shown.
		if root_eo != null and is_instance_valid(root_eo):
			_asset_vbox.add_child(_make_layer_row(root_name, root_eo, false))
		return
	# 2026-08-15, per request: a synthetic "whole creep" row sits on top of a multi-part set — selecting it
	# (instead of any one part) lets the Transform panel resize/move EVERY part together, scaled uniformly
	# about the group's own bounding box (see _group_selected / _creep_group_bbox() / _apply_group_scale()).
	# Every real part below it — Head included, now folded into this list instead of sitting as its own
	# un-indented "root row" — is an indented child row with a SHORT label (head/body1/body2/tail via
	# _short_layer_label()) instead of the full "<prefix> head" name, since the group row above already
	# carries the shared name.
	_asset_vbox.add_child(_make_group_layer_row(root_name))
	if _layers_collapsed:
		return
	# Ordered head -> body1 -> body2 -> ... -> tail via _chain_group_order when this root was auto-grouped by
	# naming convention (2026-08-13); otherwise falls back to _all_creep_names' plain alphabetical scan (e.g.
	# squid's manually-authored tentacle parenting).
	var child_names: Array[String] = [root_name]
	if _chain_group_order.has(root_name):
		for cname: String in (_chain_group_order[root_name] as Array[String]):
			if _creep_parents.get(cname, "") == root_name:
				child_names.append(cname)
	for cname: String in _all_creep_names:
		if _creep_parents.get(cname, "") == root_name and not child_names.has(cname):
			child_names.append(cname)   # leftovers not covered by the known chain order, if any
	for cname: String in child_names:
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo != null and is_instance_valid(eo):
			_asset_vbox.add_child(_make_layer_row(cname, eo, true))

## One front-facing arrow per VISIBLE part of the active group that has a defined travel facing. Positions
## are screen-space (EO centre minus SCREEN_ORIGIN) because that is what grid_overlay's `_to_vp()` expects,
## same as every fire/thrust point it draws.
func _front_markers() -> Array:
	var out: Array = []
	if _active_creep.is_empty():
		return out
	var root_name: String = _active_creep
	var par: String = _creep_parents.get(_active_creep, "")
	if not par.is_empty():
		root_name = par
	for cname: String in _group_render_names(root_name):
		if bool(_layer_hidden.get(cname, false)):
			continue
		var a := _front_marker_angle(_chain_data_name(cname))
		if is_nan(a):
			continue
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		out.append({
			"pos": eo.position + eo.size * 0.5 - SCREEN_ORIGIN,
			"angle": a,
			"len": maxf(eo.size.x, eo.size.y) * 0.62 + 16.0,
		})
	return out

## Canvas angle "forward" points at for `creep_name`, or NAN when it has none. Sprite creeps have none — a
## flat sprite is authored facing whichever way it is drawn and the arena just rotates it. The Metalfly boss
## bodies DO: they are 3D models with a real nose, and MF_FRONT_ANGLE (see its header for why it points
## down, not up like the weapons') is where that nose sits at zero calibration.
## weapon_edit_mode.gd overrides this and forwards to arena_weapons.gd, which owns the draw paths its own
## weapons' angles are derived from.
func _front_marker_angle(creep_name: String) -> float:
	return MF_FRONT_ANGLE if MF_GLB.has(creep_name) else NAN

## Pushes `_layer_hidden` onto the placed EditableObjectNodes. The 3D group overlay reads the same dict
## directly (see _build_plume3d_preview), so both representations of a part hide together.
func _apply_layer_visibility() -> void:
	# `_update_all_creep_interactivity()` is the ONE owner of `eo.visible` — it combines the eye with the
	# active-group rule. Setting visibility here directly is what broke that (see the note there).
	_update_all_creep_interactivity()

## The eye button on a layer row. Closed eye = that part is not drawn.
func _make_layer_eye(cname: String) -> Button:
	var hidden: bool = bool(_layer_hidden.get(cname, false))
	var eye := Button.new()
	eye.text = "👁" if not hidden else "—"
	eye.tooltip_text = ("Hide this layer" if not hidden else "Show this layer") + " (view only — nothing is deleted)"
	eye.add_theme_font_size_override("font_size", 12)
	eye.custom_minimum_size = Vector2(22.0, 0.0)
	eye.focus_mode = Control.FOCUS_NONE
	eye.flat = true
	eye.modulate = Color(1, 1, 1, 1) if not hidden else Color(0.55, 0.58, 0.65)
	eye.pressed.connect(func() -> void:
		_layer_hidden[cname] = not bool(_layer_hidden.get(cname, false))
		_apply_layer_visibility()
		# `_update_grid_overlay()` rather than just the plume rebuild: it re-feeds `front_markers` too, which
		# would otherwise keep drawing an arrow over a layer that is no longer there.
		_update_grid_overlay()
		_refresh_layer_list()
		_dirty = true
	)
	return eye

## Display name for the group header row — the shared prefix every child's Head/Body/Tail name was parsed
## from (e.g. "hammerhead" for "hammerhead head"/"hammerhead body1"/…), trimmed of the separator the naming
## regex left attached. Falls back to the raw root name for manually-parented sets that don't fit the
## Head/Body<N>/Tail convention (e.g. squid's tentacles).
func _group_display_name(root_name: String) -> String:
	var parsed := _parse_chain_name(root_name)
	if parsed.is_empty():
		return root_name
	return String(parsed.get("prefix", root_name)).strip_edges()

## Short label for a child row under the group header — "head"/"tail"/"body"/"body1"/"body2"/… derived from
## the same Head/Body<N>/Tail parse the auto-grouping already uses, so it always agrees with how the group
## was formed. Falls back to the raw name when it doesn't fit that convention.
func _short_layer_label(cname: String) -> String:
	var parsed := _parse_chain_name(cname)
	if parsed.is_empty():
		return cname
	var kind := String(parsed.get("kind", ""))
	if kind == "body":
		var n := int(parsed.get("n", 0))
		return "body%d" % n if n > 1 else "body"
	return kind

## The synthetic top-of-group row — selecting it enters "whole creep" mode (_group_selected) instead of
## picking one part. Reuses the same collapse caret _make_layer_row()'s root row used to own.
func _make_group_layer_row(root_name: String) -> Control:
	var is_selected: bool = _group_selected and root_name == _active_creep
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.70, 0.55, 0.45) if is_selected else Color(1.0, 1.0, 1.0, 0.06)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 4)
	row.add_child(hbox)

	var caret := Button.new()
	caret.text = "▾" if not _layers_collapsed else "▸"
	caret.add_theme_font_size_override("font_size", 11)
	caret.custom_minimum_size = Vector2(18.0, 0.0)
	caret.focus_mode = Control.FOCUS_NONE
	caret.flat = true
	caret.pressed.connect(func() -> void:
		_layers_collapsed = not _layers_collapsed
		_refresh_layer_list()
	)
	hbox.add_child(caret)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32.0, 32.0)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	var root_eo: EditableObjectNode = _placed.get(root_name, null)
	if root_eo != null and is_instance_valid(root_eo):
		icon.texture = _get_eo_thumbnail(root_eo)
	hbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = _group_display_name(root_name)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.clip_text = true
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var cap_root := root_name
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			_set_active_creep(cap_root)   # resets _group_selected=false; re-set it right after
			_group_selected = true
			_select_obj(null)   # no single part highlighted on canvas while the whole group is selected
	)
	return row

## Every real part belonging to `root_name`'s group — the root itself plus every child parented to it.
func _creep_group_members(root_name: String) -> Array[String]:
	var members: Array[String] = [root_name]
	for cname: String in _all_creep_names:
		if _creep_parents.get(cname, "") == root_name:
			members.append(cname)
	return members

## Bounding box of every live part in `root_name`'s group, in canvas coordinates — what the group row's
## Transform panel shows and what _apply_group_scale()/_apply_group_move() operate relative to.
func _creep_group_bbox(root_name: String) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var any := false
	for cname: String in _creep_group_members(root_name):
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		mn.x = minf(mn.x, eo.position.x); mn.y = minf(mn.y, eo.position.y)
		mx.x = maxf(mx.x, eo.position.x + eo.size.x); mx.y = maxf(mx.y, eo.position.y + eo.size.y)
		any = true
	return Rect2(mn, mx - mn) if any else Rect2()

## Bounding box over everything the 3D overlay DRAWS — `_creep_group_bbox()` walks `_creep_group_members()`,
## which excludes the generated chain duplicates. Today the tail is a real member sitting at the far end so
## the two agree for VIPER, but a chain with no tail would put its duplicates outside the frame and have them
## clipped. The overlay frames and pivots on this instead.
func _group_render_bbox(root_name: String) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var any := false
	for cname: String in _group_render_names(root_name):
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		mn.x = minf(mn.x, eo.position.x); mn.y = minf(mn.y, eo.position.y)
		mx.x = maxf(mx.x, eo.position.x + eo.size.x); mx.y = maxf(mx.y, eo.position.y + eo.size.y)
		any = true
	return Rect2(mn, mx - mn) if any else Rect2()

## Brings a group back onto the canvas if its whole bounding box has ended up outside it (2026-08-23, "vị
## trí đặt object khi mở edit weapon thì bị lệch tít lên xa" — VIPER's head had drifted to y = -163 on a
## 1440x780 canvas, i.e. entirely above the top edge, and everything else is laid out relative to the head,
## so the whole weapon was invisible and unreachable). Several things could nudge a part over time — a group
## resize scales positions about the group anchor, and the group-rotation orbit used to move them outright —
## and nothing ever noticed the result was unreachable.
##
## Deliberately conservative: it only fires when the bbox does not intersect the canvas AT ALL, so a
## deliberately half-offscreen layout is left alone, and it translates the group rigidly (every part by the
## same delta) so no internal geometry changes. Runs on the group root only, on open.
func _recover_offcanvas_group(root_name: String) -> void:
	if root_name.is_empty():
		return
	var bb := _creep_group_bbox(root_name)
	if bb.size.x <= 0.01 and bb.size.y <= 0.01:
		return
	var canvas := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if canvas.size.x < 1.0 or canvas.intersects(bb):
		return
	var delta := (canvas.position + canvas.size * 0.5) - (bb.position + bb.size * 0.5)
	for cname: String in _creep_group_members(root_name):
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		eo.position += delta
		for tp: Dictionary in _thrust_points.get(cname, []):
			tp["pos"] = (tp["pos"] as Vector2) + delta
		for fp: Dictionary in _fire_points.get(cname, []):
			fp["pos"] = (fp["pos"] as Vector2) + delta
	_dirty = true
	show_toast("Weapon was off-canvas — moved back into view")

## Uniformly scale every part of `root_name`'s group (position relative to `anchor` + own size) by `s` —
## the "resize the whole creep" the group row's W/H fields drive. Mirrors hud_edit_mode.gd's own
## _scale_group() (same group-bbox-anchor pattern), ported here for creep parts. Also rescales each part's
## own fire/thrust/tentacle/vortex points so they stay put relative to their sprite, same as a normal resize.
func _apply_group_scale(root_name: String, s: float, anchor: Vector2) -> void:
	if s <= 0.0 or is_equal_approx(s, 1.0):
		return
	for cname: String in _creep_group_members(root_name):
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		_push_undo_transform(eo)
		var old_size: Vector2 = eo.size
		eo.position = anchor + (eo.position - anchor) * s
		eo.size = eo.size * s
		eo._sync_rect_size()
		_rescale_points_for_resize(cname, eo.position, old_size, eo.size)
	_dirty = true
	_follow_chain_on_resize()

## Move every part of `root_name`'s group by the same delta — the group row's X/Y fields.
func _apply_group_move(root_name: String, delta: Vector2) -> void:
	if delta == Vector2.ZERO:
		return
	for cname: String in _creep_group_members(root_name):
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		_push_undo_transform(eo)
		eo.position += delta
	_dirty = true
	_follow_chain_on_move()

## `is_child`: indented + shortened label, used for both standalone-child parts and (2026-08-15) every real
## part of a grouped creep now that the group header row (_make_group_layer_row()) owns the collapse caret.
func _make_layer_row(cname: String, eo: EditableObjectNode, is_child: bool) -> Control:
	var is_selected: bool = (cname == _active_creep) and not _group_selected
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.55, 0.95, 0.45) if is_selected else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 4)
	row.add_child(hbox)

	if is_child:
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(12.0, 0.0)
		hbox.add_child(indent)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32.0, 32.0)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = _get_eo_thumbnail(eo)
	hbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = _short_layer_label(cname) if is_child else cname
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.clip_text = true
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.modulate = Color(0.85, 0.85, 0.85) if is_child else Color(1.0, 1.0, 1.0)
	if bool(_layer_hidden.get(cname, false)):
		name_lbl.modulate = Color(0.5, 0.53, 0.6)
	hbox.add_child(name_lbl)
	hbox.add_child(_make_layer_eye(cname))

	var cap_name := cname
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			_set_active_creep(cap_name)
	)
	return row

func _get_eo_thumbnail(eo: EditableObjectNode) -> Texture2D:
	var t := eo.texture_rect.texture
	if t != null and t.has_meta("gif_frames"):
		var frames: Array = t.get_meta("gif_frames")
		if not frames.is_empty():
			return frames[0] as Texture2D
	return t

# ── Open / Close ───────────────────────────────────────────────────────────────

func toggle() -> void:
	_ensure_built()
	if not _is_open:
		_is_open = true
		_grid_overlay.is_edit_open = true
		_sweep_stray_chain_dups()
		_set_ui_visible(true)
		_arena_focus(true)
		_prev_paused = get_tree().paused
		get_tree().paused = true
		_reset_zoom()
		_update_all_creep_interactivity()
		if _active_creep.is_empty() and not _all_creep_names.is_empty():
			_set_active_creep(_all_creep_names[0])
		else:
			_set_active_creep(_active_creep)
		# The view angle survives a close/reopen, but nothing else re-runs this on open — so closing while
		# orbited and reopening used to leave the flat thumbnails hidden (or, with the overlay fix above,
		# leave both representations showing) until the cube was next touched. Cheap, and makes "which of the
		# two representations is on screen" a function of the view angle alone at every moment.
		_sync_flat_thumbnails()
	else:
		_request_close()

func _request_close() -> void:
	if _dirty:
		_save_layout()
	# CHAIN's Segments/Spacing/Bend/Taper fields (creep_chain_overrides.cfg) apply + persist immediately on
	# every edit now (see _apply_chain_fields()) — nothing left to flush here.
	_close()

func _close() -> void:
	_is_open = false
	_grid_mode = false
	_adding_firepoint  = false
	_adding_thrustpoint = false
	_adding_tentaclepoint = false
	_adding_vortexpoint = false
	_adding_ledpoint = false
	_grid_btn.button_pressed  = false
	_add_fp_btn.button_pressed = false
	_add_tp_btn.button_pressed = false
	_add_tenp_btn.button_pressed = false
	_add_vortex_btn.button_pressed = false
	_add_led_btn.button_pressed = false
	_grid_overlay.show_grid    = false
	_grid_overlay.is_edit_open = false
	_reset_zoom()
	_select_fp(-1)
	_select_tp(-1)
	_select_tenp(-1)
	_select_vortex(-1)
	_select_led(-1)
	# Clear the live vortex/led preview nodes (they live on objects_container, which persists past close).
	for v in _preview_vortexes:
		if is_instance_valid(v):
			v.queue_free()
	_preview_vortexes.clear()
	for l in _preview_leds:
		if is_instance_valid(l):
			l.queue_free()
	_preview_leds.clear()
	# CHAIN section's dynamically-instantiated duplicate body EOs — NOT in _all_creep_names, so
	# _update_gameplay_visibility() below (which only hides names it knows about) would otherwise leave them
	# visible outside the editor. Destroy them outright (they're regenerated fresh on next open anyway).
	_clear_chain_dups()
	_chain_arranged.clear()
	_set_ui_visible(false)
	_arena_focus(false)
	_select_obj(null)
	_update_all_creep_interactivity()
	_update_gameplay_visibility()
	get_tree().paused = _prev_paused   # keep dev:on paused; only the dev:on→dev:off button resumes

## Safety net for "2 miếng thừa nổi trên arena, 1 đúng vị trí 1 sai vị trí" — this editor owns the tree's
## pause while `_is_open` (see toggle()) and only its OWN _close() is supposed to ever unpause it. If
## something ELSE unpauses the tree first (e.g. the player dismisses a different overlay — ESC/settings —
## that unconditionally sets get_tree().paused = false without going through this editor's Close button),
## `_is_open` stays stuck true forever: `_close()` never runs, so `_update_gameplay_visibility()` never
## hides the placed EOs (e.g. "cent body"/"cent tail"). They stay visible+interactive at their EDITOR
## CANVAS position (a fixed screen-space CanvasLayer, layer 9 — see arena.gd._setup_creep_edit()), which
## does NOT move with the actual live enemy, so it reads as a stray duplicate sitting at "the wrong spot"
## next to the real (correctly chain-animated) one. process_mode ALWAYS (see _ready()) means this keeps
## running even while paused, so it can catch the very frame the state goes inconsistent and self-heal by
## running the normal close path (which also correctly restores _prev_paused-consistent bookkeeping).
func _process(_delta: float) -> void:
	if _is_open and not get_tree().paused:
		_close()

## Hide the arena HUD + gameplay while the CREEP editor is open (not the Weapon-edit subclass, which needs
## the ship visible). The arena exposes set_edit_focus().
func _arena_focus(on: bool) -> void:
	if _edit_group() != "creep_edit":
		return
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("set_edit_focus"):
		arena.set_edit_focus(on)

func _set_ui_visible(v: bool) -> void:
	_dim_overlay.visible = v
	_asset_panel.visible = v
	_ctrl_panel.visible  = v
	if _viewcube_rect != null and is_instance_valid(_viewcube_rect):
		_viewcube_rect.visible = v
	if _viewcube_btn != null and is_instance_valid(_viewcube_btn):
		_viewcube_btn.visible = v
	if not v:
		for p: CPUParticles2D in _preview_plumes:
			if is_instance_valid(p):
				p.queue_free()
		_preview_plumes.clear()
		# 2026-08-22 bug fix ("sau khi tôi tắt edit đi vẫn còn lại trên màn hình, cùng với đó là 1 cái plume"):
		# the 3D overlay was missing from this teardown entirely. Unlike the 2D plumes above it is a
		# full-screen TextureRect at z_index 200 parented to `_objects_container` (which deliberately outlives
		# the editor — see the vortex/LED note in _close()) plus a SubViewport parented to this node, so
		# closing the panel left the whole assembled 3D scene — all three VIPER parts and the active TP's
		# plume — painted over the running game until the editor happened to be opened again.
		_clear_plume3d_preview()
		_dragging_asset      = false
		_dragging_ctrl       = false
		_eo_drag_undo_pushed = false

# ── Active creep ───────────────────────────────────────────────────────────────

func _set_active_creep(creep_name: String) -> void:
	if creep_name.is_empty():
		return
	_group_selected = false   # selecting any single part always exits "whole creep" group mode
	# 2026-08-14, extra safety net ("tắt game mở lại lại bị mất... bạn không có file cfg hay gì đó để lưu à"):
	# creep_layout.cfg (pos/size, unlike the CHAIN fields' own file) previously only ever got written when the
	# WHOLE editor closed cleanly — quit the game any other way (alt-F4, crash, forgot to close the panel
	# first) and every resize/move since the last close was gone. Flush it on every plain creep switch too, so
	# there's no longer a single "did I close it right" moment the whole session's edits hinge on.
	if _dirty and creep_name != _active_creep:
		_save_layout()
	_active_creep = creep_name
	if not _placed.has(creep_name) or not is_instance_valid(_placed.get(creep_name, null)):
		_load_or_create_creep(creep_name)
	# Pre-load the whole group so the layer list and canvas show all members
	var group_root: String = _creep_parents.get(creep_name, "")
	if group_root.is_empty():
		group_root = creep_name  # active is the root
	else:
		_load_or_create_creep(group_root)  # ensure parent is loaded
	for cname: String in _all_creep_names:
		if _creep_parents.get(cname, "") == group_root:
			_load_or_create_creep(cname)
	_recover_offcanvas_group(group_root)
	if not _fire_points.has(creep_name):
		_fire_points[creep_name] = []
	if not _thrust_points.has(creep_name):
		_thrust_points[creep_name] = []
	if not _tentacle_points.has(creep_name):
		_tentacle_points[creep_name] = []
	if not _vortex_points.has(creep_name):
		_vortex_points[creep_name] = []
	if not _led_points.has(creep_name):
		_led_points[creep_name] = []
	_selected_fp_idx = -1
	_selected_tp_idx = -1
	_selected_tp_indices.clear()
	_selected_tenp_idx = -1
	_selected_vortex_idx = -1
	_selected_vortex_indices.clear()
	_selected_led_idx = -1
	_selected_led_indices.clear()
	_eo_drag_undo_pushed = false
	_update_all_creep_interactivity()
	_apply_layer_visibility()
	# BEFORE anything that rebuilds the 3D overlay (2026-08-23). `_refresh_glb_view_ui()` is what sets
	# `_active_glb_path`, and `_build_plume3d_preview()` bails out on an empty one — so with this call in its
	# old place, further down, the FIRST 3D weapon selected in a session got no overlay at all and fell back
	# to its flat EO thumbnail, cropped square (the ND-Aliwa-Bmr report). Every later switch happened to work
	# only because the PREVIOUS weapon's path was still sitting in the variable. Nothing between here and the
	# old call site reads `_active_glb_path`, so this is a pure ordering fix.
	_refresh_glb_view_ui()
	_refresh_tp_bone_ui()
	_update_grid_overlay()
	_refresh_fp_list()
	_refresh_tp_list()
	_refresh_tenp_list()
	_refresh_fp_angle_ui()
	_refresh_tp_angle_ui()
	_refresh_tenp_angle_ui()
	_refresh_transform_panel()   # also refreshes TP POS X/Y/Z + W/H lock via its own tail — see that function
	_refresh_plume_editor()
	_refresh_vortex_list()
	_refresh_vortex_editor()
	_refresh_led_list()
	_refresh_led_editor()
	_refresh_dynamic_panels()
	# Auto-select the active creep's sprite so it can be dragged / nudged immediately
	var active_eo: EditableObjectNode = _placed.get(creep_name, null)
	_select_obj(active_eo if is_instance_valid(active_eo) else null)
	for name: String in _creep_buttons:
		(_creep_buttons[name] as Button).button_pressed = (name == creep_name)

## 2026-08-15, per request ("chỉ các thuộc tính nào được add cho creep mới hiển thị"): FIRE/THRUST/VORTEX/LED
## POINTS are each a whole section of the properties panel below LAYERS — show a section only when the
## ACTIVE creep actually has at least one point of that type, so an empty/unused section doesn't take up
## space. TENTACLE POINTS stays permanently hidden regardless (already hidden by design, replaced by Vortex).
## Doesn't touch PLUME STYLE or CHAIN — those are driven by their own existing conditions (TP selection /
## chain-group membership), not simply "does this creep have any points".
func _refresh_dynamic_panels() -> void:
	var has_fp:  bool = not (_fire_points.get(_active_creep, []) as Array).is_empty()
	var has_tp:  bool = not (_thrust_points.get(_active_creep, []) as Array).is_empty()
	var has_vx:  bool = not (_vortex_points.get(_active_creep, []) as Array).is_empty()
	var has_led: bool = not (_led_points.get(_active_creep, []) as Array).is_empty()
	for n: Control in _fp_section_nodes:
		n.visible = has_fp
	for n: Control in _tp_section_nodes:
		n.visible = has_tp
	for n: Control in _vortex_section_nodes:
		n.visible = has_vx
	for n: Control in _led_section_nodes:
		n.visible = has_led

func _load_or_create_creep(creep_name: String) -> void:
	if _placed.has(creep_name) and is_instance_valid(_placed.get(creep_name, null)):
		return
	# Try to find the file, across every scanned folder. "glb" tried FIRST (2026-08-20, VIPER 3D swap) —
	# same "prefer the richer asset when both exist" precedent as _hd_path()'s HD-over-standard PNG pick, so
	# a creep that has both a flat PNG and a newer .glb (e.g. VIPER, mid-swap) previews/places the .glb —
	# staying WYSIWYG with arena_weapons.gd, which now renders the live .glb, not the old PNG, for VIPER.
	# An explicit override (Jeager's layers -> one merged glb) short-circuits the folder scan.
	var forced := _asset_path_for(creep_name)
	var candidates: Array[String] = []
	if not forced.is_empty():
		candidates.append(forced)
	else:
		for folder: String in _folders():
			for ext: String in ["glb", "png", "gif", "jpg", "jpeg"]:
				candidates.append(folder + creep_name + "." + ext)
	for path: String in candidates:
		var tex := _load_full_tex(path, creep_name)
		if tex == null:
			continue
		var tex_w := float(tex.get_width())
		var tex_h := float(tex.get_height())
		var aspect := tex_h / tex_w if tex_w > 0.0 else 1.0
		var rect := _default_creep_rect(creep_name, aspect)
		_place_creep_eo(creep_name, tex, path, rect.position, rect.size)
		return

func _place_creep_eo(creep_name: String, tex: Texture2D, path: String,
		pos: Vector2, sz: Vector2) -> EditableObjectNode:
	if _objects_container == null:
		return null
	var eo: EditableObjectNode = EditableObject.instantiate()
	eo.group_id    = "creep_" + creep_name
	eo.source_path = path
	_objects_container.add_child(eo)
	eo.init(tex, pos, sz)
	# 2026-08-15 bug fix ("chỉnh Taper thì node xa gốc bị dẹp/lệch phải" + tail resize looking like it "resets"):
	# editable_object.tscn's TextureRect defaults to expand_mode=EXPAND_FIT_WIDTH_PROPORTIONAL, which makes
	# Godot silently CLAMP any `.size` assignment to a texture-derived minimum WIDTH — verified with an actual
	# runtime probe (numbers in the reply): shrinking a "cent body" duplicate below ~60px wide left
	# `texture_rect.size.x` stuck at ~60 while `.y` shrank correctly, stretching/skewing the sprite and, since
	# the (correctly-shrunk) parent Control re-centers around that stuck-wide texture, reading as a rightward
	# drift the further it tapered. Root cause is scene-wide (this .tscn is shared by main menu/boss/HUD edit
	# too — a global expand_mode change there regressed main menu button/logo sizing, reverted). Scoped the
	# real fix to HERE instead: EXPAND_IGNORE_SIZE removes that clamp entirely (safe with our stretch_mode=
	# STRETCH_SCALE, which always fills `.size` regardless of expand_mode — unlike the STRETCH_KEEP+
	# EXPAND_IGNORE_SIZE combo CLAUDE.md's own "Image scaling" section warns about for a DIFFERENT rendering
	# path). `_place_creep_eo()` is the single choke point for every real creep/weapon-edit node (Head/Body/
	# Tail templates AND every plain sprite) — chain DUPLICATES (`_make_chain_dup_eo()`) are created via
	# `.duplicate()` off an already-fixed template, so they inherit this property automatically, no separate
	# fix needed there. Does NOT touch main menu ("mainmenu"), boss edit ("boss_*"), or HUD edit ("hud_item")
	# — those instantiate EditableObject through their own code paths, never through this function.
	eo.texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eo.z_index     = 115
	eo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eo.object_clicked.connect(_on_canvas_object_clicked)
	eo.transform_ended.connect(_on_transform_ended)
	eo.transform_motion.connect(_on_transform_motion)
	_placed[creep_name] = eo
	return eo

# ── Selection & transform ──────────────────────────────────────────────────────

func _select_obj(obj: EditableObjectNode) -> void:
	if is_instance_valid(_selected_obj):
		_selected_obj.selected = false
	_selected_obj = obj
	if is_instance_valid(obj):
		obj.selected = true
	_delete_btn.disabled = not is_instance_valid(obj)
	_refresh_transform_panel()
	_refresh_layer_list()

func _refresh_transform_panel() -> void:
	_updating_spin = true
	if _group_selected:
		# 2026-08-15: whole-creep group row selected — W/H/X/Y describe the group's bounding box, not a
		# single part. Z is meaningless for a group (every part keeps its own) — shown as 0 and disabled.
		var bb := _creep_group_bbox(_active_creep)
		_sz_w_spin.value  = bb.size.x
		_sz_h_spin.value  = bb.size.y
		_z_spin.value     = 0.0
		_z_spin.editable  = false
		_pos_x_spin.value = snappedf(bb.position.x, 1.0)
		_pos_y_spin.value = snappedf(bb.position.y, 1.0)
		_pos_x_spin.editable = true
		_pos_y_spin.editable = true
		_updating_spin = false
		_refresh_extra_controls()
		_refresh_chain_controls()
		_apply_tp_focus_transform_lock()
		return
	_z_spin.editable = true
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo != null and is_instance_valid(eo):
		_sz_w_spin.value = eo.size.x
		_sz_h_spin.value = eo.size.y
		_z_spin.value    = eo.z_index
		# X,Y: relative to parent if child, read-only if root
		var parent_name: String = _creep_parents.get(_active_creep, "")
		var has_parent: bool = not parent_name.is_empty()
		_pos_x_spin.editable = has_parent
		_pos_y_spin.editable = has_parent
		if has_parent:
			var peo: EditableObjectNode = _placed.get(parent_name, null)
			if peo != null and is_instance_valid(peo):
				var rel := eo.position - peo.position
				_pos_x_spin.value = snappedf(rel.x, 1.0)
				_pos_y_spin.value = snappedf(rel.y, 1.0)
		else:
			_pos_x_spin.value = snappedf(eo.position.x, 1.0)
			_pos_y_spin.value = snappedf(eo.position.y, 1.0)
	else:
		_sz_w_spin.value = 0.0
		_sz_h_spin.value = 0.0
		_z_spin.value    = 0.0
		_pos_x_spin.value = 0.0
		_pos_y_spin.value = 0.0
		_pos_x_spin.editable = false
		_pos_y_spin.editable = false
	_updating_spin = false
	_refresh_extra_controls()
	_refresh_chain_controls()
	_apply_tp_focus_transform_lock()

## Called from BOTH of _refresh_transform_panel()'s exit paths (2026-08-21, "resize được object / XYZ không
## sửa được... ngược lại khi chọn TP"): a TP being selected on a .glb creep swaps this panel's meaning —
## W/H (resize) becomes meaningless (per request: "chỉnh to nhỏ đã nằm bên bảng plume") and gets disabled,
## while TP POS X/Y/Z becomes the live thing being edited and gets shown+populated (_refresh_tp_pos3_ui).
## Selecting the object (or no TP) puts it back to normal: W/H editable, TP POS hidden+disabled. Non-glb
## creeps never show the TP POS row at all — same "_active_glb_path" gate as the rotation sliders.
func _apply_tp_focus_transform_lock() -> void:
	var tp_focused := not _selected_tp_indices.is_empty() and not _active_glb_path.is_empty()
	_sz_w_spin.editable = not tp_focused
	_sz_h_spin.editable = not tp_focused
	_tp_pos3_row.visible = tp_focused
	_tp_x3_spin.editable = tp_focused
	_tp_y3_spin.editable = tp_focused
	_tp_z3_spin.editable = tp_focused
	if tp_focused:
		_refresh_tp_pos3_ui()
	# 2026-08-22: the Rotate handles mean different things in the two modes (absolute for a TP, jog for an
	# object — see _sync_glb_rot_handles), so they have to be re-parked whenever focus crosses between them.
	# Several paths clear the TP selection without going through _refresh_glb_view_ui() (deleting a TP,
	# selecting a vortex/LED point, ...), which would otherwise leave a TP's angle sitting on the handles
	# while they act as a jog. Gated on an ACTUAL mode change: this function also runs on every arrow-key
	# nudge, and re-parking unconditionally could reset a handle out from under an in-progress drag.
	if tp_focused != _glb_handles_tp_mode:
		_sync_glb_rot_handles()

func _on_spin_changed() -> void:
	if _updating_spin or _active_creep.is_empty():
		return
	_apply_spin_to_selected()

func _on_w_spin_changed() -> void:
	if _updating_spin or _active_creep.is_empty():
		return
	if _group_selected:
		_apply_spin_to_selected()   # group branch there keeps W/H tied together via the bbox's own aspect
		return
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo != null and is_instance_valid(eo) and eo._aspect_ratio > 0.0:
		_updating_spin = true
		_sz_h_spin.value = snappedf(_sz_w_spin.value / eo._aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_selected()

func _on_h_spin_changed() -> void:
	if _updating_spin or _active_creep.is_empty():
		return
	if _group_selected:
		_apply_spin_to_selected()
		return
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo != null and is_instance_valid(eo) and eo._aspect_ratio > 0.0:
		_updating_spin = true
		_sz_w_spin.value = snappedf(_sz_h_spin.value * eo._aspect_ratio, 1.0)
		_updating_spin = false
	_apply_spin_to_selected()

func _apply_spin_to_selected() -> void:
	if _group_selected:
		# 2026-08-15: "resize the whole creep" — W/H changes uniformly scale EVERY part (position + size)
		# about the group's own bounding box top-left, same algorithm hud_edit_mode.gd's own group resize
		# uses (_scale_group()). Editing either W or H alone still scales both axes by that field's own
		# ratio (matches the per-EO aspect-lock UX above) — _refresh_transform_panel() picks up the other
		# field's new value on the next refresh.
		var bb := _creep_group_bbox(_active_creep)
		if bb.size.x <= 0.0 or bb.size.y <= 0.0:
			return
		var sw := _sz_w_spin.value / bb.size.x
		var sh := _sz_h_spin.value / bb.size.y
		var s: float = sw if not is_equal_approx(sw, 1.0) else sh
		_apply_group_scale(_active_creep, s, bb.position)
		_refresh_transform_panel()
		return
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo == null or not is_instance_valid(eo):
		return
	_push_undo_transform(eo)
	var old_size: Vector2 = eo.size
	eo.size    = Vector2(_sz_w_spin.value, _sz_h_spin.value)
	eo.z_index = int(_z_spin.value)
	eo._sync_rect_size()
	_rescale_points_for_resize(_active_creep, eo.position, old_size, eo.size)
	_dirty = true
	_follow_chain_on_resize()

## Rescales every fire/thrust/tentacle/vortex point belonging to `creep_name` so each stays at the SAME
## fractional position within the sprite's bounding box after a resize — user feedback: "khi resize unit
## trong creep edit, các thrust point cũng được tính toán lại để re-position theo". Points are stored as
## ABSOLUTE editor-canvas pixels (see _add_thrustpoint_at() etc.), not normalized, so without this a resize
## leaves every point marker frozen at its old absolute spot — visibly drifting off the sprite's new outline,
## and silently changing the fraction arena_enemy.gd's _load_tp_fracs() recomputes at spawn time (that
## fraction is (point - eo.position) / eo.size, using whatever size is CURRENTLY saved — i.e. real gameplay
## plume/tentacle/muzzle placement would drift too, not just the editor preview).
##
## `origin` (eo.position) is OC-space (canvas pixels — see the SS/OC split in _drop_data()/creep placement,
## `node.position = ss_pos + SCREEN_ORIGIN`), but every point dict stores "pos" in SS-space (`ss_pos`,
## WITHOUT SCREEN_ORIGIN — see _add_thrustpoint_at() etc: `ss_pos := (viewport_pos - oc_pos)/_zoom -
## SCREEN_ORIGIN`). An earlier version of this function used `origin` as-is against the SS-space points,
## which bakes in a SCREEN_ORIGIN-sized error scaled by (new_size/old_size) — invisible at ratio≈1, growing
## with the resize ratio (user report: "vẫn hơi lệch khi scale lên mức lớn hơn"). Converting `origin` to the
## SAME SS-space the points use (subtract SCREEN_ORIGIN once) fixes it exactly, at any scale.
func _rescale_points_for_resize(creep_name: String, origin: Vector2, old_size: Vector2, new_size: Vector2) -> void:
	if creep_name.is_empty() or old_size.x <= 0.0 or old_size.y <= 0.0 or old_size.is_equal_approx(new_size):
		return
	var ss_origin := origin - SCREEN_ORIGIN
	for points_dict: Dictionary in [_fire_points, _thrust_points, _tentacle_points, _vortex_points, _led_points]:
		var arr: Array = points_dict.get(creep_name, [])
		for pt: Dictionary in arr:
			var old_pos: Vector2 = pt.get("pos", Vector2.ZERO)
			var frac: Vector2 = (old_pos - ss_origin) / old_size
			pt["pos"] = ss_origin + frac * new_size
	_update_grid_overlay()

func _on_pos_spin_changed() -> void:
	if _updating_spin or _active_creep.is_empty():
		return
	if _group_selected:
		var bb := _creep_group_bbox(_active_creep)
		_apply_group_move(_active_creep, Vector2(_pos_x_spin.value, _pos_y_spin.value) - bb.position)
		return
	var parent_name: String = _creep_parents.get(_active_creep, "")
	if parent_name.is_empty():
		return  # root sprite: X,Y not editable
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	var peo: EditableObjectNode = _placed.get(parent_name, null)
	if eo == null or not is_instance_valid(eo) or peo == null or not is_instance_valid(peo):
		return
	_push_undo_transform(eo)
	eo.position = peo.position + Vector2(_pos_x_spin.value, _pos_y_spin.value)
	eo._sync_rect_size()
	_dirty = true
	_follow_chain_on_move()

func _on_transform_ended(_obj: Control) -> void:
	_eo_drag_undo_pushed = false
	_refresh_transform_panel()
	_dirty = true
	_follow_chain_on_move()

func _on_transform_motion(obj: EditableObjectNode) -> void:
	if not is_instance_valid(obj):
		return
	if not _eo_drag_undo_pushed:
		_eo_drag_undo_pushed = true
		_push_undo_transform(obj)
	_refresh_transform_panel()
	_dirty = true
	_follow_chain_on_move()

## 2026-08-14 rewrite — Head/Body-template(s)/Tail are 3 fully independent real nodes; moving or resizing
## ANY of them (head included) never touches another real node's position/size. The only thing that ever
## reacts is the CHAIN's DUPLICATE nodes (pure derived clones — see _rebuild_chain_preview()), which are
## always fully recomputed from whatever the real nodes currently look like. So both handlers below just
## rebuild the duplicates; nothing here can ever move/resize a template, head, or tail.
## No-ops entirely outside an active CHAIN section (_chain_active_id == "") — zero effect on normal editing.
## 2026-08-23: these two are the choke point EVERY transform edit already funnels through — mouse drag
## (_on_transform_motion/_on_transform_ended), the Transform panel's X/Y/W/H spinboxes
## (_apply_spin_to_selected), the group row's own move/scale, and the arrow keys. They used to no-op entirely
## outside an active CHAIN section, which was fine while a part's flat thumbnail moved with its own rect and
## showed the edit by itself. The 3D overlay is that part's picture now, so an edit that doesn't reach it
## leaves the rect moving under an unchanged image — which is what "phím mũi tên không di chuyển được part"
## was. Refreshing the overlay on the no-chain path costs one rebuild per edit and closes the gap for every
## caller at once, rather than per call site. (`_rebuild_chain_preview()` already ends with that refresh, so
## the chain path is not doing it twice.)
func _follow_chain_on_move() -> void:
	if _chain_active_id == "":
		_refresh_plume3d_preview()
		return
	_rebuild_chain_preview()

func _follow_chain_on_resize() -> void:
	if _chain_active_id == "":
		_refresh_plume3d_preview()
		return
	_rebuild_chain_preview()

# ── Grid mode ──────────────────────────────────────────────────────────────────

func _toggle_grid_mode() -> void:
	_grid_mode = _grid_btn.button_pressed
	if _grid_mode:
		_adding_firepoint   = false
		_adding_thrustpoint = false
		_adding_tentaclepoint = false
		_adding_vortexpoint = false
		_add_fp_btn.button_pressed = false
		_add_tp_btn.button_pressed = false
		_add_tenp_btn.button_pressed = false
		_add_vortex_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
		_select_tenp(-1)
	_update_all_creep_interactivity()
	_grid_overlay.show_grid    = _grid_mode
	_grid_overlay.is_edit_open = _is_open

func _toggle_adding_firepoint() -> void:
	_adding_firepoint = _add_fp_btn.button_pressed
	if _adding_firepoint:
		_adding_thrustpoint = false
		_adding_tentaclepoint = false
		_adding_vortexpoint = false
		_adding_ledpoint = false
		_add_tp_btn.button_pressed = false
		_add_tenp_btn.button_pressed = false
		_add_vortex_btn.button_pressed = false
		_add_led_btn.button_pressed = false
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
		_select_tenp(-1)
	_update_all_creep_interactivity()

func _toggle_adding_thrustpoint() -> void:
	_adding_thrustpoint = _add_tp_btn.button_pressed
	if _adding_thrustpoint:
		_adding_firepoint = false
		_adding_tentaclepoint = false
		_adding_vortexpoint = false
		_adding_ledpoint = false
		_add_fp_btn.button_pressed = false
		_add_tenp_btn.button_pressed = false
		_add_vortex_btn.button_pressed = false
		_add_led_btn.button_pressed = false
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
		_select_tenp(-1)
	_update_all_creep_interactivity()

# ── Fire Points ────────────────────────────────────────────────────────────────

func _add_firepoint_at(viewport_pos: Vector2) -> void:
	if _active_creep.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _fire_points.has(_active_creep):
		_fire_points[_active_creep] = []
		_fp_id_counter[_active_creep] = 1
	var fp_id: int = _fp_id_counter.get(_active_creep, 1)
	_fire_points[_active_creep].append({"pos": ss_pos, "id": fp_id, "dir_angle": 0.0})
	_fp_id_counter[_active_creep] = fp_id + 1
	_dirty = true
	_refresh_fp_list()
	_refresh_dynamic_panels()
	_update_grid_overlay()

func _select_fp(idx: int) -> void:
	_selected_fp_idx = idx
	if idx >= 0:
		_select_obj(null)
		_selected_tp_idx = -1
		_selected_tp_indices.clear()
		_refresh_plume_editor()
	_refresh_fp_list()
	_update_grid_overlay()
	_refresh_fp_angle_ui()

func _delete_selected_fp() -> void:
	var fps: Array = _fire_points.get(_active_creep, [])
	if _selected_fp_idx < 0 or _selected_fp_idx >= fps.size():
		return
	fps.remove_at(_selected_fp_idx)
	_fire_points[_active_creep] = fps
	_selected_fp_idx = -1
	_dirty = true
	_refresh_fp_list()
	_refresh_dynamic_panels()
	_update_grid_overlay()

func _refresh_fp_angle_ui() -> void:
	var show := _selected_fp_idx >= 0
	_fp_angle_row.visible = show
	if not show:
		return
	var fps: Array = _fire_points.get(_active_creep, [])
	if _selected_fp_idx >= fps.size():
		return
	_updating_spin = true
	_fp_angle_spin.value = snappedf(rad_to_deg(float(fps[_selected_fp_idx].get("dir_angle", 0.0))), 1.0)
	_updating_spin = false

func _on_fp_angle_changed() -> void:
	if _updating_spin or _selected_fp_idx < 0:
		return
	var fps: Array = _fire_points.get(_active_creep, [])
	if _selected_fp_idx >= fps.size():
		return
	fps[_selected_fp_idx]["dir_angle"] = deg_to_rad(_fp_angle_spin.value)
	_fire_points[_active_creep] = fps
	_dirty = true
	_update_grid_overlay()

func _refresh_fp_list() -> void:
	for child in _fp_vbox.get_children():
		child.queue_free()
	var fps: Array = _fire_points.get(_active_creep, [])
	for i: int in fps.size():
		_fp_vbox.add_child(_make_point_row(fps[i], i, true))

# ── Thrust Points ──────────────────────────────────────────────────────────────

func _add_thrustpoint_at(viewport_pos: Vector2) -> void:
	if _active_creep.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _thrust_points.has(_active_creep):
		_thrust_points[_active_creep] = []
		_tp_id_counter[_active_creep] = 1
	var tp_id: int = _tp_id_counter.get(_active_creep, 1)
	var new_idx: int = (_thrust_points[_active_creep] as Array).size()
	var new_tp := {"pos": ss_pos, "id": tp_id, "dir_angle": PI * 0.5, "z": 0.0}
	# Land it WHERE IT WAS CLICKED, whatever the model is rotated to (2026-08-23). `pos` is stored in the
	# part's own local frame, and the preview draws it back through the mount rotation — so on a rotated
	# model the raw click above renders somewhere else entirely. Measured on a 150px part: at Rot Z 90 a
	# click 40px to the right came out 40px UP; at Rot X -90 a click 40px DOWN collapsed onto the centre,
	# because that axis is "height" from a top-down camera and belongs in `z`, not in `pos`.
	#
	# `_tp_xyz_set()` is the exact inverse of the render path and already splits a point into `pos` + `z`
	# (it is what the TP POS X/Y/Z spinboxes write through) — so the two writers of this field agree now
	# instead of disagreeing by the mount angle.
	if not _active_glb_path.is_empty():
		_tp_xyz_set(_active_creep, new_tp, _tp_click_to_world(ss_pos))
	# 2026-08-21 ("Khi add TP, là add TP 3D"): a 3D-wired weapon/creep (WIRED_3D_CREEPS, glb resolved —
	# see _refresh_glb_view_ui) gets its "dir_rot" written IMMEDIATELY on creation instead of waiting for
	# the first Rotate X/Y/Z slider drag. Functionally a no-op — Vector3.ZERO already matches the flat
	# dir_angle=PI/2 default direction via glb_topdown_rig.gd's tp_direction() fallback — but it marks the
	# TP as an explicit 3D TP from the start (visible in the saved cfg, not just implied by the object type).
	if not _active_glb_path.is_empty():
		new_tp["dir_rot"] = Vector3.ZERO
	_thrust_points[_active_creep].append(new_tp)
	_tp_id_counter[_active_creep] = tp_id + 1
	_dirty = true
	# 2026-08-21 bug fix ("thêm plume mới thì nó sẽ là plume 3D luôn và có thể xoay được"): the new TP used to
	# stay UNselected — the Rotate X/Y/Z sliders and TP POS X/Y/Z panel kept acting on whatever was selected
	# BEFORE (the object itself, or a different TP), not the one just created, so rotating right after Add TP
	# silently edited the wrong thing. _select_tp() already does everything needed (sets _selected_tp_idx/
	# _selected_tp_indices, refreshes the TP list/angle UI/3D-view sliders/transform panel) — call it instead
	# of hand-rolling a partial refresh here.
	_select_tp(new_idx)
	_refresh_dynamic_panels()
	_update_grid_overlay()
	# 2026-08-22 bug fix ("không xoay được plume add bằng nút addTP"): a brand-new TP has no live particle
	# PIVOT in arena_weapons.gd yet — `_live_tp_particles` only gets an entry for it once `_load_*_plume_3d()`
	# actually runs with this TP included, which only happens on the NEXT save/reload. Without this, the very
	# first slider drag after Add TP silently found no pivot and did nothing. Saving immediately builds it, so
	# rotation works from the first interaction, same as for any pre-existing TP.
	_save_layout(true)


func _select_tp(idx: int) -> void:
	_selected_tp_idx = idx
	_tp_range_anchor = idx   # plain click always re-anchors a future Shift-click range here
	_selected_tp_indices.clear()
	if idx >= 0:
		_selected_tp_indices.append(idx)
	if idx >= 0:
		_select_obj(null)
		_selected_fp_idx = -1
	_refresh_tp_list()
	_update_grid_overlay()
	_refresh_tp_angle_ui()
	_refresh_glb_view_ui()       # also context-switches the Rotate X/Y/Z sliders to this TP's spray direction
	_refresh_tp_bone_ui()
	_refresh_transform_panel()   # also refreshes TP POS X/Y/Z + W/H lock via its own tail — see that function
	_refresh_plume_editor()

## 2026-08-15, per request ("giữ Shift chọn 2 layer thì toàn bộ layer nằm giữa cũng được chọn"): Shift-click
## now selects the full contiguous RANGE from the fixed anchor (set by the last plain click) through `idx`,
## inclusive — standard file-explorer/IDE range-select — instead of the old toggle-one-item-in/out behavior.
## The anchor itself never moves during a Shift-click run, so repeated Shift-clicks keep re-extending/
## shrinking the SAME range rather than drifting from wherever the last Shift-click landed.
func _select_tp_add(idx: int) -> void:
	if idx < 0:
		return
	_select_obj(null)
	_selected_fp_idx = -1
	if _tp_range_anchor < 0:
		_tp_range_anchor = idx
	var lo := mini(_tp_range_anchor, idx)
	var hi := maxi(_tp_range_anchor, idx)
	_selected_tp_indices.clear()
	for i in range(lo, hi + 1):
		_selected_tp_indices.append(i)
	_selected_tp_idx = idx
	_refresh_tp_list()
	_update_grid_overlay()
	_refresh_tp_angle_ui()
	_refresh_glb_view_ui()       # also context-switches the Rotate X/Y/Z sliders to this TP's spray direction
	_refresh_transform_panel()   # also refreshes TP POS X/Y/Z + W/H lock via its own tail — see that function
	_refresh_plume_editor()

func _delete_selected_tp() -> void:
	if _selected_tp_indices.is_empty():
		return
	var tps: Array = _thrust_points.get(_active_creep, [])
	var sorted: Array[int] = _selected_tp_indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for idx: int in sorted:
		if idx >= 0 and idx < tps.size():
			tps.remove_at(idx)
	_thrust_points[_active_creep] = tps
	_selected_tp_idx = -1
	_selected_tp_indices.clear()
	_dirty = true
	_refresh_tp_list()
	_refresh_dynamic_panels()
	_update_grid_overlay()
	_refresh_plume_editor()

## 2026-08-21: hidden for a glb creep's TP — direction there is now controlled by the "3D VIEW / MOUNT ANGLE"
## Rotate X/Y/Z sliders (dir_rot, a full 3-axis spray direction — see _refresh_glb_view_ui), which take
## priority over this flat single-axis `dir_angle` field once set (glb_topdown_rig.gd's tp_direction()) —
## leaving this visible too would silently stop doing anything the moment dir_rot gets set, confusing.
func _refresh_tp_angle_ui() -> void:
	var show := not _selected_tp_indices.is_empty() and _active_glb_path.is_empty()
	_tp_angle_row.visible = show
	if not show or _selected_tp_idx < 0:
		return
	var tps: Array = _thrust_points.get(_active_creep, [])
	if _selected_tp_idx >= tps.size():
		return
	_updating_spin = true
	_tp_angle_spin.value = snappedf(rad_to_deg(float(tps[_selected_tp_idx].get("dir_angle", 0.0))), 1.0)
	_updating_spin = false

## The rig's own `target_px` for `creep_name` (see _load_glb_topdown_tex) — the scale unit the TP X/Y/Z
## Transform-panel fields (and the plume preview gizmos) are expressed in. 32.0 generic fallback if the rig
## isn't built yet (shouldn't normally happen — the rig is built the moment the creep is first loaded/placed).
func _tp_target_px(creep_name: String) -> float:
	var eo: EditableObjectNode = _placed.get(creep_name, null)
	if eo == null or not is_instance_valid(eo):
		return 32.0
	var rig: Dictionary = _glb_preview_cache.get(_rig_key(creep_name, eo.source_path), {})
	return float(rig.get("target_px", 32.0))

## Reads `tp`'s position as an editor-space (Z-up) offset from the object's own centre: X/Y span the play
## plane (Y up-positive) and Z is the vertical axis — the same convention the whole editor uses since the
## 2026-08-22 axis pass, and unchanged here because TPs already worked this way. In real
## "px" units — a friendlier VIEW of the underlying SS-space `pos`/`z` fields (see _tp_pos3_row's own comment
## in _build_ui), via the SAME frac formula every other TP consumer already uses. Vector3.ZERO if the object
## isn't placed/sized yet.
## The part's own mount rotation as a VIEW-space Basis — what turns a TP's stored, model-local offset into
## the direction it actually points on screen. Identity for a creep with no 3D rig, which is what keeps every
## 2D creep behaving exactly as before.
func _tp_mount_basis(creep_name: String) -> Basis:
	var eo: EditableObjectNode = _placed.get(creep_name, null)
	if eo == null or not is_instance_valid(eo):
		return Basis.IDENTITY
	var rig: Dictionary = _glb_preview_cache.get(_rig_key(creep_name, eo.source_path), {})
	if rig.is_empty():
		return Basis.IDENTITY
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	return rr.view_basis(rr.compose_rot(rig.get("rot_base", Vector3.ZERO), rig.get("rot", Vector3.ZERO)))

func _tp_xyz_get(creep_name: String, tp: Dictionary) -> Vector3:
	var eo: EditableObjectNode = _placed.get(creep_name, null)
	if eo == null or not is_instance_valid(eo) or eo.size.x < 0.01 or eo.size.y < 0.01:
		return Vector3.ZERO
	var target_px := _tp_target_px(creep_name)
	var tp_oc: Vector2 = (tp["pos"] as Vector2) + SCREEN_ORIGIN
	var frac := (tp_oc - eo.position) / eo.size
	# 2026-08-22 ("Mũi tên lên: tăng giá trị Y"): Y is reported UP-POSITIVE (note the minus) — canvas y grows
	# downward, so without the flip pressing Up made the displayed Y go DOWN, the opposite of what the arrow
	# keys should read as. Purely a UI/edit convention: `tp["pos"]` is still stored in canvas space, and the
	# actual 3D placement is computed straight from `frac` elsewhere (_refresh_plume3d_preview /
	# _glb_refresh_tp_gizmos / arena_weapons.gd), so nothing about where a plume renders changes here.
	# 2026-08-23 ("pgup/pgdn là để thay đổi cao độ, không phải để di chuyển lên xuống trái phải trên mặt
	# phẳng chơi game"): reported in EDITOR WORLD space now — X right on the canvas, Y up on the canvas,
	# Z the true altitude — not in the part's own local frame. A TP pivot is a CHILD of its part node, so the
	# part's mount rotation is applied to whatever is stored; measured on the saved data, VIPER Tail's
	# rotation (~90 deg about X) swapped its two axes outright, so +1 on the stored Y moved the plume 1.00 in
	# ALTITUDE and 0.05 on the canvas, while +1 on the stored Z moved it 1.00 up the canvas. VIPER body was
	# swapped the same way. Rotating through the mount basis here — and back in _tp_xyz_set — makes the
	# spinboxes and the nudge keys mean what they say for every part, at any mount angle.
	var local_view := Vector3((frac.x - 0.5) * target_px, float(tp.get("z", 0.0)), (frac.y - 0.5) * target_px)
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var world_view: Vector3 = _tp_mount_basis(creep_name) * local_view
	return rr.axis_fix().inverse() * world_view

## Inverse of _tp_xyz_get — writes `xyz` back into `tp`'s `pos` (SS-space) and `z` fields directly (mutates
## the passed Dictionary in place, same as every other in-place TP edit in this file).
## A click on the canvas as the "editor world" XYZ `_tp_xyz_set()` expects — the same space the TP POS
## spinboxes read and write, so a click and a typed coordinate mean the same thing. Canvas X/Y map to the
## editor's X/Y (Z-up authoring space, see glb_topdown_rig.gd); a click carries no height, so Z is 0 and the
## mount rotation decides how much of the click ends up as height on the way in.
func _tp_click_to_world(ss_pos: Vector2) -> Vector3:
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo == null or not is_instance_valid(eo):
		return Vector3.ZERO
	var target_px := _tp_target_px(_active_creep)
	var ctr: Vector2 = eo.position + eo.size * 0.5 - SCREEN_ORIGIN
	var off := ss_pos - ctr
	if eo.size.x > 0.01 and eo.size.y > 0.01:
		off = Vector2(off.x / eo.size.x, off.y / eo.size.y) * target_px
	return Vector3(off.x, -off.y, 0.0)   # editor +Y is canvas UP

func _tp_xyz_set(creep_name: String, tp: Dictionary, xyz: Vector3) -> void:
	var eo: EditableObjectNode = _placed.get(creep_name, null)
	if eo == null or not is_instance_valid(eo):
		return
	var target_px := _tp_target_px(creep_name)
	if target_px <= 0.001:
		return
	# Exact inverse of _tp_xyz_get: editor world -> view -> the part's own local frame -> stored fields.
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var world_view: Vector3 = rr.axis_fix() * xyz
	var local_view: Vector3 = _tp_mount_basis(creep_name).inverse() * world_view
	var frac := Vector2(local_view.x / target_px + 0.5, local_view.z / target_px + 0.5)
	var tp_oc: Vector2 = eo.position + frac * eo.size
	tp["pos"] = tp_oc - SCREEN_ORIGIN
	tp["z"] = local_view.y

## Populates the TP POS X/Y/Z fields from the currently-selected TP — called from _refresh_transform_panel's
## tail (its own existing single choke point for "selection changed"), not a separate hook.
func _refresh_tp_pos3_ui() -> void:
	if _selected_tp_indices.is_empty() or _selected_tp_idx < 0:
		return
	var tps: Array = _thrust_points.get(_active_creep, [])
	if _selected_tp_idx >= tps.size():
		return
	var xyz := _tp_xyz_get(_active_creep, tps[_selected_tp_idx])
	_updating_spin = true
	_tp_x3_spin.value = snappedf(xyz.x, 0.1)
	_tp_y3_spin.value = snappedf(xyz.y, 0.1)
	_tp_z3_spin.value = snappedf(xyz.z, 0.1)
	_updating_spin = false

func _on_tp_xyz3_changed() -> void:
	if _updating_spin or _selected_tp_indices.is_empty():
		return
	var tps: Array = _thrust_points.get(_active_creep, [])
	var xyz := Vector3(_tp_x3_spin.value, _tp_y3_spin.value, _tp_z3_spin.value)
	for sel_idx: int in _selected_tp_indices:
		if sel_idx >= 0 and sel_idx < tps.size():
			_tp_xyz_set(_active_creep, tps[sel_idx], xyz)
	_thrust_points[_active_creep] = tps
	_dirty = true
	_glb_refresh_tp_gizmos(_active_creep)
	_update_grid_overlay()   # the object's own flat 2D dot overlay also reads `pos` — keep it in sync too

func _on_tp_angle_changed() -> void:
	if _updating_spin or _selected_tp_indices.is_empty():
		return
	var tps: Array = _thrust_points.get(_active_creep, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx >= 0 and sel_idx < tps.size():
			tps[sel_idx]["dir_angle"] = deg_to_rad(_tp_angle_spin.value)
	_thrust_points[_active_creep] = tps
	_dirty = true
	_update_grid_overlay()

func _refresh_tp_list() -> void:
	for child in _tp_vbox.get_children():
		child.queue_free()
	var tps: Array = _thrust_points.get(_active_creep, [])
	for i: int in tps.size():
		_tp_vbox.add_child(_make_point_row(tps[i], i, false))
	_glb_refresh_tp_gizmos(_active_creep)   # no-op for non-glb creeps — see that function's header

## Shows/hides the "3D VIEW / MOUNT ANGLE" sliders depending on whether the ACTIVE creep resolves to a
## `.glb`, and reflects whatever rotation the rig already has (loaded from disk or left over from earlier
## this session) — never resets it, or every creep switch would silently discard the calibration.
## 2026-08-21 ("chọn layer object: xoay object... chọn layer TP: xoay riêng TP"): these 3 sliders now
## context-switch by selection — TP focused (a TP selected on this same glb creep) → they edit THAT TP's own
## spray-direction calibration (`dir_rot`, see glb_topdown_rig.gd's `tp_direction()`); otherwise → the
## object's own mount-angle (`rot`, unchanged from the previous pass). Called on creep switch (_set_active_
## creep) AND every TP selection change (_select_tp/_select_tp_add) so the displayed values always match
## whatever is actually focused right now.
func _refresh_glb_view_ui() -> void:
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	var path := (eo.source_path if eo != null and is_instance_valid(eo) else "")
	# 2026-08-21: gated on WIRED_3D_CREEPS again — the earlier revert was because Aliwa wasn't in the list
	# yet (removing its sliders looked like a regression); ND-Aliwa-Bmr's own 3D runtime plume is now built
	# (see that const's header) so it's back in the allowlist and the gate no longer hides its controls.
	var is_glb := path.get_extension().to_lower() == "glb" and _active_creep in WIRED_3D_CREEPS
	for n: Control in _glb_view_section_nodes:
		n.visible = is_glb
	# The rig KEY, not the bare path — several layers can share one glb (see _rig_key).
	_active_glb_path = _rig_key(_active_creep, path) if is_glb else ""
	if not is_glb:
		return
	_sync_glb_rot_handles()

## Parks the three Rotate handles wherever the CURRENT focus wants them, and refreshes the readouts. One
## choke point for every place that changes focus or applies a rotation outside the drag path, because the
## two modes want opposite things (2026-08-22, "khi rotate plume 3D, thiết lập lại cơ chế xoay như của plume
## 2D"):
##
##   TP focused  -> ABSOLUTE. The handles hold the TP's own `dir_rot` and stay where you put them, exactly
##                  like the old flat 2D `dir_angle` field did: drag Rot Z and that IS the spray heading in
##                  the ground plane, readable at a glance and repeatable. This is safe here precisely
##                  BECAUSE of the axis change — with Z vertical, a plume's normal pose is flat (X/Y ≈ 0)
##                  and the Euler middle axis never approaches the ±90° that made absolute handles collapse
##                  two controls onto one axis before.
##   Object focused -> RELATIVE jog (handles spring back to centre). An object genuinely needs arbitrary
##                  3-axis poses, tilted well past 90°, so absolute Euler fields would gimbal-lock there.
func _sync_glb_rot_handles() -> void:
	if _glb_rot_x_slider == null:
		return
	_glb_handles_tp_mode = not _selected_tp_indices.is_empty()
	var v := Vector3.ZERO
	if not _selected_tp_indices.is_empty():
		var tps: Array = _thrust_points.get(_active_creep, [])
		if _selected_tp_idx >= 0 and _selected_tp_idx < tps.size():
			v = tps[_selected_tp_idx].get("dir_rot", Vector3.ZERO)
	_glb_rot_x_slider.set_value_no_signal(rad_to_deg(v.x))
	_glb_rot_y_slider.set_value_no_signal(rad_to_deg(v.y))
	_glb_rot_z_slider.set_value_no_signal(rad_to_deg(v.z))
	# Read the handles BACK rather than trusting `v` — Range snaps to `step` (1°), so the two differ by up to
	# half a degree, and seeding the jog baseline with the unsnapped value would inject that as a phantom
	# delta on the very next drag tick.
	_glb_slider_last = Vector3(deg_to_rad(_glb_rot_x_slider.value), deg_to_rad(_glb_rot_y_slider.value),
		deg_to_rad(_glb_rot_z_slider.value))
	_sync_glb_rot_labels()

## Companion to the Rotate X/Y/Z sliders — writes the current slider values into their "<deg>°" readout
## labels. Needed anywhere a slider's `.value` is set via `set_value_no_signal` (_refresh_glb_view_ui,
## _on_glb_reset_rotation), since that deliberately does NOT fire `value_changed` (would otherwise recurse
## into _on_glb_rotation_changed and stomp whatever was being restored) — so those call sites must sync the
## label text themselves. The drag path (slider.value_changed, see _build_ui's "3D VIEW" section) calls this
## too, alongside _on_glb_rotation_changed, so both sources of a value change stay in sync.
func _sync_glb_rot_labels() -> void:
	if _glb_rot_x_lbl == null:
		return
	# 2026-08-22: shows the FOCUSED TARGET's absolute angle, not the slider handle's position — the handles
	# are relative jog controls now (see _on_glb_rotation_changed) and spring back to centre, so echoing them
	# would just read 0 all the time. This keeps the absolute readout the old design had.
	var a := _glb_focused_rot()
	_glb_rot_x_lbl.text = "%d°" % roundi(rad_to_deg(a.x))
	_glb_rot_y_lbl.text = "%d°" % roundi(rad_to_deg(a.y))
	_glb_rot_z_lbl.text = "%d°" % roundi(rad_to_deg(a.z))

## Absolute orientation of whatever the rotate sliders currently steer — a selected TP's spray direction
## (base ∘ dir_rot) or otherwise the object's own mount angle (base ∘ rot). Display only.
func _glb_focused_rot() -> Vector3:
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	if not _selected_tp_indices.is_empty():
		var tps: Array = _thrust_points.get(_active_creep, [])
		if _selected_tp_idx >= 0 and _selected_tp_idx < tps.size():
			return rr.tp_rot_editor(tps[_selected_tp_idx])
		return Vector3.ZERO
	var rig: Dictionary = _glb_preview_cache.get(_active_glb_path, {})
	if rig.is_empty():
		return Vector3.ZERO
	return rr.compose_rot(rig.get("rot_base", Vector3.ZERO), rig.get("rot", Vector3.ZERO))

## 2026-08-21 ("áp dụng cơ chế xoay của plume test... nhưng thay vì bấm numpad thì kéo slider"): both branches
## now write STRAIGHT into the live game's actual particle/calibration (via arena_weapons.gd's
## `set_live_tp_direction`/`set_live_mount_cal`, group `"arena_weapons"`) the same instant the slider moves —
## the same direct-property-write model the throwaway TEST PLUME uses for its Numpad keys, just driven by
## these sliders instead. `_save_layout(true)` still runs right after (unchanged) so the value SURVIVES a
## restart — that's now its ONLY job here; it's no longer what makes the drag visible in-game.
## Every creep name belonging to `root_name`'s group, root first (2026-08-22, "Khi click layer VIPER: kéo
## thanh xoay sẽ xoay toàn bộ object"). Used by the rotation handlers when the synthetic whole-creep LAYERS
## row is selected (`_group_selected`), so one slider drag turns head + bodies + tail as a rigid unit instead
## of only whichever single part happens to be active.
func _group_member_names(root_name: String) -> Array[String]:
	var out: Array[String] = [root_name]
	for cname: String in _all_creep_names:
		if cname != root_name and _creep_parents.get(cname, "") == root_name:
			out.append(cname)
	return out

## A rig cache entry's authored VERTICAL offset in editor space (Z-up). 2026-08-22: the key is `z` now
## ("Trục Z là trục thẳng đứng của không gian 3D"); `height` is still accepted so a layout saved before the
## axis-space pass, or restored from a backup, keeps whatever lift it had. Every read goes through here so
## the fallback lives in exactly one place.
func _rig_z(rig: Dictionary) -> float:
	return float(rig.get("z", rig.get("height", 0.0)))

## One saved angle carried from the pre-axis-space (Godot Y-up / YXZ) storage into editor space (Z-up /
## ZXY). Chosen so the RENDERED orientation is bit-for-bit what it was before: the conjugation is the exact
## inverse of what `view_basis()` does on the way back out. No-op once the file is marked `axis_space=z_up`.
func _migrate_axis(rot: Vector3, legacy: bool) -> Vector3:
	if not legacy or rot.is_zero_approx():
		return rot
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	return rr.editor_rot(Basis.from_euler(rot))

## The chain/group root `creep_name` belongs to — its parent if it has one, otherwise itself.
func _group_root_of(creep_name: String) -> String:
	var par: String = _creep_parents.get(creep_name, "")
	return par if not par.is_empty() else creep_name

## Every node the 3D overlay has to DRAW for `root_name`'s group — `_group_member_names()` plus the generated
## chain duplicates (2026-08-22). The two lists must stay distinct: duplicates hold no data of their own
## (no saved rotation, no TP list, no cfg entry), so the rotation/save paths must keep using the member list,
## while the renderer has to include them or a 6-segment VIPER draws as 3 parts. Duplicates live in `_placed`
## and `_creep_parents` but never in `_all_creep_names`, which is why the member list misses them.
func _group_render_names(root_name: String) -> Array[String]:
	var out: Array[String] = _group_member_names(root_name)
	for dup_name: String in _chain_dup_names:
		if _creep_parents.get(dup_name, "") == root_name and not out.has(dup_name):
			out.append(dup_name)
	return out

## A chain duplicate's underlying template name ("VIPER body #4" -> "VIPER body"); returns `cname` unchanged
## for a real part. Duplicates carry no data of their own, so every data lookup (thrust points, plume styles)
## has to go through their template — which is also exactly what the arena does, drawing every body segment
## from the single "VIPER body" entry.
func _chain_data_name(cname: String) -> String:
	var cut := cname.rfind(" #")
	return cname.substr(0, cut) if cut > 0 else cname

## Bone names of the active creep's model, empty when it has no skeleton. Read off the live preview rig, so
## it is always the same skeleton the plume will actually be bound to at runtime.
func _active_bone_names() -> PackedStringArray:
	var rig := _rig_for_creep(_active_creep)
	var model: Node3D = rig.get("model")
	if model == null or not is_instance_valid(model):
		return PackedStringArray()
	var skel := _find_skeleton_in(model)
	if skel == null:
		return PackedStringArray()
	var out := PackedStringArray()
	for i in skel.get_bone_count():
		out.append(skel.get_bone_name(i))
	return out

func _find_skeleton_in(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c: Node in n.get_children():
		var r := _find_skeleton_in(c)
		if r != null:
			return r
	return null

## Repopulates the bone picker for whatever TP is selected. Hidden entirely when the creep has no skeleton,
## so the row only ever appears where it can do something.
func _refresh_tp_bone_ui() -> void:
	if _tp_bone_option == null:
		return
	var bones := _active_bone_names()
	var tps: Array = _thrust_points.get(_active_creep, [])
	var has_sel: bool = _selected_tp_idx >= 0 and _selected_tp_idx < tps.size()
	_tp_bone_row.visible = has_sel and not bones.is_empty()
	if not _tp_bone_row.visible:
		return
	var cur := String((tps[_selected_tp_idx] as Dictionary).get("bone", ""))
	_tp_bone_option.clear()
	_tp_bone_option.add_item("(none)")
	var pick := 0
	for i in bones.size():
		_tp_bone_option.add_item(bones[i])
		if bones[i] == cur:
			pick = i + 1
	_tp_bone_option.select(pick)

func _on_tp_bone_selected(idx: int) -> void:
	var tps: Array = _thrust_points.get(_active_creep, [])
	if _selected_tp_idx < 0 or _selected_tp_idx >= tps.size():
		return
	var tp: Dictionary = tps[_selected_tp_idx]
	if idx <= 0:
		tp.erase("bone")
	else:
		tp["bone"] = _tp_bone_option.get_item_text(idx)
	_dirty = true
	_save_layout(true)   # same live-apply path the rotation sliders use — see _on_glb_rotation_changed
	var ws := get_tree().get_first_node_in_group("weapon_system")
	if ws != null and ws.has_method("reload_3d_weapon_layout"):
		ws.reload_3d_weapon_layout()

## The `_glb_preview_cache` rig for `creep_name`, or {} if it isn't a placed glb.
func _rig_for_creep(creep_name: String) -> Dictionary:
	var eo: EditableObjectNode = _placed.get(creep_name, null)
	if eo == null or not is_instance_valid(eo):
		return {}
	return _glb_preview_cache.get(_rig_key(creep_name, eo.source_path), {})

## Rotates `root_name`'s whole group as ONE RIGID BODY about a single pivot — the centre of the assembled
## block (`_creep_group_bbox`) — instead of each part spinning about its own centre (2026-08-22, "xoay toàn
## bộ dựa trên 1 pivot duy nhất lấy trung tâm khối object làm pivot point"). Setting every part's `rot` to
## the same value (what the group branch did before) only aligned their ORIENTATIONS; their positions stayed
## put, so each part visibly pivoted in place. A real rigid rotation also has to ORBIT every part around the
## shared centre, which is what this adds.
##
## Takes the DELTA rotation directly (the sliders are relative jog controls — see _on_glb_rotation_changed),
## so a manual nudge or a resize between two drags is simply absorbed into the new offsets instead of being
## undone, and there is no baseline to seed or get out of step.
##
## 2026-08-22 (axis-space pass): the orbit is computed in EDITOR space (Z-up), the same space `delta` is
## expressed in — canvas X = editor X, canvas Y = editor -Y (canvas y grows downward, editor Y points up),
## and a part's stored `z` = editor Z. Doing it here rather than converting `delta` keeps one rule for the
## whole function: everything on this side of `view_basis()` is Z-up.
func _apply_group_rigid_delta(root_name: String, delta: Basis) -> void:
	if delta.is_equal_approx(Basis.IDENTITY):
		return
	# 2026-08-23: an arena-authored chain has no rigid body to orbit. Its parts are laid out by
	# `_rebuild_chain_preview()` from the game's own spacing every rebuild, and in game the mount rotation is
	# applied purely as an orientation (`_snake3d_world_xform` composes `cal` into the BASIS and never into
	# the origin). Orbiting the block here moved parts the game places by formula — the caller still writes
	# each member's `rot`, so the sliders keep turning every part in place, which is all `cal` does.
	if not _chain_geometry(root_name).is_empty():
		return
	var members := _group_member_names(root_name)
	var bb := _creep_group_bbox(root_name)   # whole visible assembly, duplicates included
	if bb.size.x <= 0.01 and bb.size.y <= 0.01:
		return
	var c := bb.position + bb.size * 0.5
	var zsum := 0.0
	var zn := 0
	for cname: String in members:
		var rg: Dictionary = _rig_for_creep(cname)
		if rg.is_empty():
			continue
		zsum += _rig_z(rg)
		zn += 1
	var cz: float = zsum / maxf(float(zn), 1.0)
	for cname: String in members:
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		var rg: Dictionary = _rig_for_creep(cname)
		var ctr := eo.position + eo.size * 0.5
		var pz: float = _rig_z(rg) if not rg.is_empty() else 0.0
		var rotated := delta * Vector3(ctr.x - c.x, -(ctr.y - c.y), pz - cz)
		eo.position = Vector2(c.x + rotated.x, c.y - rotated.y) - eo.size * 0.5
		if not rg.is_empty():
			rg["z"] = cz + rotated.z

## 2026-08-22 (gimbal-lock fix): the 3 sliders are RELATIVE jog controls now, not absolute Euler fields.
## Writing an absolute `Vector3(x, y, z)` meant the orientation was authored as Euler angles, and Euler's
## middle axis (X here) collapses the other two onto ONE axis as it approaches ±90° — measured on the user's
## own saved VIPER body (`rot.x = 91°`): the Rot Y and Rot Z axes came out at |dot| = 1.000, i.e. literally
## the same axis, so two of the three controls did the same thing. Now each drag applies a rotation about
## that slider's OWN WORLD AXIS, composed onto the current orientation as a Basis — Euler is only ever used
## to STORE the result, never to edit it, so no pose can lock the controls together.
## The sliders snap back to 0 when released (see `drag_ended` in _build_ui); the "NN°" readouts next to them
## show the focused target's ABSOLUTE angle, so nothing is lost by the handles being relative.
func _on_glb_rotation_changed() -> void:
	if _active_glb_path.is_empty():
		return
	var cur := Vector3(deg_to_rad(_glb_rot_x_slider.value), deg_to_rad(_glb_rot_y_slider.value),
		deg_to_rad(_glb_rot_z_slider.value))
	# TP focused -> the handles ARE the value (see _sync_glb_rot_handles for why the two modes differ).
	if not _selected_tp_indices.is_empty():
		_set_tp_rotation_absolute(cur)
		_sync_glb_rot_labels()
		return
	var d := cur - _glb_slider_last
	_glb_slider_last = cur
	if d.is_zero_approx():
		return
	# One slider moves at a time, but sum the axes anyway so a programmatic multi-axis change still works.
	var delta := Basis.IDENTITY
	if absf(d.x) > 1e-9:
		delta = Basis(Vector3.RIGHT, d.x) * delta
	if absf(d.y) > 1e-9:
		delta = Basis(Vector3.UP, d.y) * delta
	if absf(d.z) > 1e-9:
		delta = Basis(Vector3.BACK, d.z) * delta
	_apply_rotation_delta(delta)
	_sync_glb_rot_labels()

## Writes `rot` (EDITOR space, radians) straight into every selected TP's `dir_rot` — the absolute
## counterpart of `_apply_rotation_delta`'s TP branch, and the thing that restores the old 2D plume's feel:
## the slider position IS the spray angle, so Rot Z reads as a plain compass heading in the ground plane
## rather than an accumulated nudge. Everything downstream of the write (preview pivot, live in-game pivot,
## gizmos, save) is identical to the delta path — only how the new value is arrived at differs.
func _set_tp_rotation_absolute(rot: Vector3) -> void:
	var ws: Node = get_tree().get_first_node_in_group("arena_weapons")
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var tps: Array = _thrust_points.get(_active_creep, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx < 0 or sel_idx >= tps.size():
			continue
		tps[sel_idx]["dir_rot"] = rot
		var tp_id := int(tps[sel_idx].get("id", 1))
		var pivot: Node3D = (_preview_plumes3d.get("pivots", {}) as Dictionary).get(tp_id)
		if pivot != null and is_instance_valid(pivot):
			pivot.rotation = rr.tp_view_rotation(tps[sel_idx])
		if ws != null and ws.has_method("set_live_tp_direction"):
			ws.set_live_tp_direction(_active_creep, tp_id, rr.tp_rot_editor(tps[sel_idx]))
	_thrust_points[_active_creep] = tps
	_dirty = true
	_glb_refresh_tp_gizmos(_active_creep)
	_save_layout(true)

## Rotates whatever is currently focused by `delta` (a world-axis rotation), keeping each target's banked
## `*_base` intact: `base * new = delta * base * old`, so `new = base⁻¹ · delta · base · old`.
func _apply_rotation_delta(delta: Basis) -> void:
	var ws: Node = get_tree().get_first_node_in_group("arena_weapons")
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	# TP focused → sliders steer THAT TP's spray direction, not the object's own mount angle.
	if not _selected_tp_indices.is_empty():
		var tps: Array = _thrust_points.get(_active_creep, [])
		for sel_idx: int in _selected_tp_indices:
			if sel_idx < 0 or sel_idx >= tps.size():
				continue
			var base := rr.rot_basis(tps[sel_idx].get("dir_rot_base", Vector3.ZERO) as Vector3)
			var old := rr.rot_basis(tps[sel_idx].get("dir_rot", Vector3.ZERO) as Vector3)
			var new_rot: Vector3 = rr.rot_euler(base.inverse() * delta * base * old)
			tps[sel_idx]["dir_rot"] = new_rot
			var tp_id := int(tps[sel_idx].get("id", 1))
			# Direct write to the live preview pivot — same instant the slider moves, no rebuild or save
			# round-trip in the path (this is what the user actually watches).
			var pivot: Node3D = (_preview_plumes3d.get("pivots", {}) as Dictionary).get(tp_id)
			if pivot != null and is_instance_valid(pivot):
				pivot.rotation = rr.tp_view_rotation(tps[sel_idx])
			if ws != null and ws.has_method("set_live_tp_direction"):
				# COMPOSED angle — the live pivot has no access to the banked base, so sending the raw half
				# would drop it and desync the in-game plume from the preview (see that method's header).
				ws.set_live_tp_direction(_active_creep, tp_id, rr.tp_rot_editor(tps[sel_idx]))
		_thrust_points[_active_creep] = tps
		_dirty = true
		_glb_refresh_tp_gizmos(_active_creep)
		_save_layout(true)
		return
	# Whole-creep LAYERS row selected -> turn EVERY part of the group as one rigid body.
	if _group_selected:
		_apply_group_rigid_delta(_active_creep, delta)   # orbits positions/heights about the block centre
		for cname: String in _group_member_names(_active_creep):
			var mrig: Dictionary = _rig_for_creep(cname)
			if mrig.is_empty():
				continue
			var mbase := rr.rot_basis(mrig.get("rot_base", Vector3.ZERO) as Vector3)
			var mold := rr.rot_basis(mrig.get("rot", Vector3.ZERO) as Vector3)
			var mnew: Vector3 = rr.rot_euler(mbase.inverse() * delta * mbase * mold)
			mrig["rot"] = mnew
			_glb_apply_rotation(mrig)
			if ws != null and ws.has_method("set_live_mount_cal"):
				ws.set_live_mount_cal(cname, mnew)
		_dirty = true
		# Re-lay the chain so the body DUPLICATES follow the new axis too — they hold no position of their
		# own, so without this they stay on the old (pre-rotation) line while the templates swing round.
		# Order matters: the chain rebuild goes LAST because it ends with the overlay refresh, which has to
		# see the final duplicate set.
		_refresh_plume_preview()
		_rebuild_chain_preview()
		_save_layout(true)
		return
	var rig: Dictionary = _glb_preview_cache.get(_active_glb_path, {})
	if rig.is_empty():
		return
	var obase := rr.rot_basis(rig.get("rot_base", Vector3.ZERO) as Vector3)
	var oold := rr.rot_basis(rig.get("rot", Vector3.ZERO) as Vector3)
	var onew: Vector3 = rr.rot_euler(obase.inverse() * delta * obase * oold)
	rig["rot"] = onew
	_dirty = true
	_glb_apply_rotation(rig)
	if ws != null and ws.has_method("set_live_mount_cal"):
		ws.set_live_mount_cal(_active_creep, onew)
	_save_layout(true)

## "Set 0° here" — see the button's own comment in _build_ui. Folds the currently-focused rotation into its
## `*_base` companion and zeroes the editable half, leaving the rendered orientation untouched. Follows the
## exact same object-vs-TP context switch as the sliders themselves (_on_glb_rotation_changed).
func _on_glb_set_zero_here() -> void:
	if _active_glb_path.is_empty():
		return
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	if not _selected_tp_indices.is_empty():
		var tps: Array = _thrust_points.get(_active_creep, [])
		for sel_idx: int in _selected_tp_indices:
			if sel_idx < 0 or sel_idx >= tps.size():
				continue
			tps[sel_idx]["dir_rot_base"] = rr.compose_rot(
				tps[sel_idx].get("dir_rot_base", Vector3.ZERO), tps[sel_idx].get("dir_rot", Vector3.ZERO))
			tps[sel_idx]["dir_rot"] = Vector3.ZERO
		_thrust_points[_active_creep] = tps
	elif _group_selected:
		for cname: String in _group_member_names(_active_creep):
			var mrig: Dictionary = _rig_for_creep(cname)
			if mrig.is_empty():
				continue
			mrig["rot_base"] = rr.compose_rot(mrig.get("rot_base", Vector3.ZERO), mrig.get("rot", Vector3.ZERO))
			mrig["rot"] = Vector3.ZERO
			_glb_apply_rotation(mrig)
	else:
		var rig: Dictionary = _glb_preview_cache.get(_active_glb_path, {})
		if rig.is_empty():
			return
		rig["rot_base"] = rr.compose_rot(rig.get("rot_base", Vector3.ZERO), rig.get("rot", Vector3.ZERO))
		rig["rot"] = Vector3.ZERO
		_glb_apply_rotation(rig)
	_dirty = true
	# Re-park the sliders WITHOUT firing their handler (that would write the handle positions back over the
	# values we just banked); then rebuild the previews and persist, same tail as a normal rotation edit.
	_sync_glb_rot_handles()
	_glb_refresh_tp_gizmos(_active_creep)
	_refresh_plume_preview()
	_refresh_tp_list()
	_save_layout(true)

## "Reset Rotation" — turns whatever is focused back to world-aligned (its "NN°" readouts go to 0/0/0).
## 2026-08-22: with the sliders now RELATIVE, zeroing the handles no longer resets anything (the delta would
## just be zero), so this computes the rotation that undoes the focused target's current absolute angle and
## routes it through the same delta path everything else uses — which also un-orbits a whole group rigidly
## rather than leaving its parts rotated in place.
func _on_glb_reset_rotation() -> void:
	if _active_glb_path.is_empty():
		return
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var delta := rr.rot_basis(_glb_focused_rot()).inverse()
	_apply_rotation_delta(delta)   # works for a TP too: base⁻¹·(base·old)⁻¹·base·old = base⁻¹, i.e. composed 0
	_sync_glb_rot_handles()

# ── Tentacle Points ──────────────────────────────────────────────────────────
# Each tentacle point spawns one tentacle (the child-segment chain) at its position, aimed by Dir.
func _toggle_adding_tentaclepoint() -> void:
	_adding_tentaclepoint = _add_tenp_btn.button_pressed
	if _adding_tentaclepoint:
		_adding_firepoint = false
		_adding_thrustpoint = false
		_adding_vortexpoint = false
		_adding_ledpoint = false
		_add_fp_btn.button_pressed = false
		_add_tp_btn.button_pressed = false
		_add_vortex_btn.button_pressed = false
		_add_led_btn.button_pressed = false
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
		_select_tenp(-1)
	_update_all_creep_interactivity()

func _add_tentaclepoint_at(viewport_pos: Vector2) -> void:
	if _active_creep.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _tentacle_points.has(_active_creep):
		_tentacle_points[_active_creep] = []
		_tenp_id_counter[_active_creep] = 1
	var tn_id: int = _tenp_id_counter.get(_active_creep, 1)
	_tentacle_points[_active_creep].append({"pos": ss_pos, "id": tn_id, "dir_angle": PI * 0.5})
	_tenp_id_counter[_active_creep] = tn_id + 1
	_dirty = true
	_refresh_tenp_list()
	_update_grid_overlay()

func _select_tenp(idx: int) -> void:
	_selected_tenp_idx = idx
	if idx >= 0:
		_select_obj(null)
		_selected_fp_idx = -1
		_selected_tp_idx = -1
		_selected_tp_indices.clear()
	_refresh_tenp_list()
	_update_grid_overlay()
	_refresh_tenp_angle_ui()

func _delete_selected_tenp() -> void:
	var tns: Array = _tentacle_points.get(_active_creep, [])
	if _selected_tenp_idx < 0 or _selected_tenp_idx >= tns.size():
		return
	tns.remove_at(_selected_tenp_idx)
	_tentacle_points[_active_creep] = tns
	_selected_tenp_idx = -1
	_dirty = true
	_refresh_tenp_list()
	_update_grid_overlay()

func _refresh_tenp_angle_ui() -> void:
	var show := _selected_tenp_idx >= 0
	_tenp_angle_row.visible = show
	if not show:
		return
	var tns: Array = _tentacle_points.get(_active_creep, [])
	if _selected_tenp_idx >= tns.size():
		return
	_updating_spin = true
	_tenp_angle_spin.value = snappedf(rad_to_deg(float(tns[_selected_tenp_idx].get("dir_angle", 0.0))), 1.0)
	_updating_spin = false

func _on_tenp_angle_changed() -> void:
	if _updating_spin or _selected_tenp_idx < 0:
		return
	var tns: Array = _tentacle_points.get(_active_creep, [])
	if _selected_tenp_idx >= tns.size():
		return
	tns[_selected_tenp_idx]["dir_angle"] = deg_to_rad(_tenp_angle_spin.value)
	_tentacle_points[_active_creep] = tns
	_dirty = true
	_update_grid_overlay()

func _refresh_tenp_list() -> void:
	for child in _tenp_vbox.get_children():
		child.queue_free()
	var tns: Array = _tentacle_points.get(_active_creep, [])
	for i: int in tns.size():
		_tenp_vbox.add_child(_make_tenp_row(tns[i], i))

func _make_tenp_row(pt: Dictionary, idx: int) -> Control:
	var is_sel: bool = (idx == _selected_tenp_idx)
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 30.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.70, 0.30, 0.95, 0.38) if is_sel else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	row.add_child(hbox)
	var pt_id: int   = pt.get("id",  idx + 1)
	var pos: Vector2 = pt.get("pos", Vector2.ZERO)
	var angle_deg    := int(round(rad_to_deg(float(pt.get("dir_angle", 0.0)))))
	var id_lbl := Label.new()
	id_lbl.text = "Tn%d" % pt_id
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.custom_minimum_size = Vector2(30.0, 0.0)
	id_lbl.modulate = Color(0.95, 0.55, 1.0) if is_sel else Color(0.70, 0.40, 0.90)
	hbox.add_child(id_lbl)
	var pos_lbl := Label.new()
	pos_lbl.text = "(%d,%d) %d°" % [int(pos.x), int(pos.y), angle_deg]
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(pos_lbl)
	var cap_idx := idx
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			_select_tenp(cap_idx)
	)
	return row

# ── Vortex Points ────────────────────────────────────────────────────────────
# A directionless point anchoring a spinning EnergyVortex VFX. Per-point style: radius / spin / arms / colors.
func _toggle_adding_vortexpoint() -> void:
	_adding_vortexpoint = _add_vortex_btn.button_pressed
	if _adding_vortexpoint:
		_adding_firepoint = false
		_adding_thrustpoint = false
		_adding_tentaclepoint = false
		_adding_ledpoint = false
		_add_fp_btn.button_pressed = false
		_add_tp_btn.button_pressed = false
		_add_tenp_btn.button_pressed = false
		_add_led_btn.button_pressed = false
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
		_select_tenp(-1)
	_update_all_creep_interactivity()

func _add_vortexpoint_at(viewport_pos: Vector2) -> void:
	if _active_creep.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _vortex_points.has(_active_creep):
		_vortex_points[_active_creep] = []
		_vortex_id_counter[_active_creep] = 1
	var vx_id: int = _vortex_id_counter.get(_active_creep, 1)
	_vortex_points[_active_creep].append({"pos": ss_pos, "id": vx_id})
	_vortex_id_counter[_active_creep] = vx_id + 1
	_selected_vortex_idx = _vortex_points[_active_creep].size() - 1
	_selected_vortex_indices = [_selected_vortex_idx]
	_dirty = true
	_refresh_vortex_list()
	_refresh_vortex_editor()
	_refresh_dynamic_panels()
	_update_grid_overlay()

func _select_vortex(idx: int) -> void:
	_selected_vortex_idx = idx
	_vortex_range_anchor = idx   # plain click always re-anchors a future Shift-click range here
	_selected_vortex_indices.clear()
	if idx >= 0:
		_selected_vortex_indices.append(idx)
		_select_obj(null)
		_selected_fp_idx = -1
		_selected_tp_idx = -1
		_selected_tp_indices.clear()
		_selected_tenp_idx = -1
	_refresh_vortex_list()
	_refresh_vortex_editor()
	_update_grid_overlay()

## 2026-08-15: Shift-click range-selects from the fixed anchor (last plain click) through `idx`, inclusive —
## see _select_tp_add()'s comment for the full reasoning (same behavior, ported here).
func _select_vortex_add(idx: int) -> void:
	if idx < 0:
		return
	_select_obj(null)
	_selected_fp_idx = -1
	_selected_tp_idx = -1
	_selected_tp_indices.clear()
	_selected_tenp_idx = -1
	if _vortex_range_anchor < 0:
		_vortex_range_anchor = idx
	var lo := mini(_vortex_range_anchor, idx)
	var hi := maxi(_vortex_range_anchor, idx)
	_selected_vortex_indices.clear()
	for i in range(lo, hi + 1):
		_selected_vortex_indices.append(i)
	_selected_vortex_idx = idx
	_refresh_vortex_list()
	_refresh_vortex_editor()
	_update_grid_overlay()

func _delete_selected_vortex() -> void:
	if _selected_vortex_indices.is_empty():
		return
	var vxs: Array = _vortex_points.get(_active_creep, [])
	var sorted: Array[int] = _selected_vortex_indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for idx: int in sorted:
		if idx >= 0 and idx < vxs.size():
			vxs.remove_at(idx)
	_vortex_points[_active_creep] = vxs
	_selected_vortex_idx = -1
	_selected_vortex_indices.clear()
	_dirty = true
	_refresh_vortex_list()
	_refresh_vortex_editor()
	_refresh_dynamic_panels()
	_update_grid_overlay()

func _refresh_vortex_list() -> void:
	if _vortex_vbox == null:
		return
	for child in _vortex_vbox.get_children():
		child.queue_free()
	var vxs: Array = _vortex_points.get(_active_creep, [])
	for i: int in vxs.size():
		_vortex_vbox.add_child(_make_vortex_row(vxs[i], i))

func _make_vortex_row(pt: Dictionary, idx: int) -> Control:
	var is_sel: bool = _selected_vortex_indices.has(idx)
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 28.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.30, 0.55, 0.95, 0.40) if is_sel else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	row.add_child(hbox)
	var pt_id: int   = pt.get("id", idx + 1)
	var pos: Vector2 = pt.get("pos", Vector2.ZERO)
	var id_lbl := Label.new()
	id_lbl.text = "Vx%d" % pt_id
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.custom_minimum_size = Vector2(34.0, 0.0)
	id_lbl.modulate = Color(0.70, 0.88, 1.0) if is_sel else Color(0.50, 0.70, 0.95)
	hbox.add_child(id_lbl)
	var pos_lbl := Label.new()
	pos_lbl.text = "(%d,%d)" % [int(pos.x), int(pos.y)]
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(pos_lbl)
	var cap_idx := idx
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			if Input.is_key_pressed(KEY_SHIFT):
				_select_vortex_add(cap_idx)
			else:
				_select_vortex(cap_idx)
	)
	return row

func _default_vortex_style() -> Dictionary:
	return {
		"radius":    40.0,
		"spin":      2.2,
		"arms":      3,
		"col_core":  Color(0.75, 0.92, 1.0, 1.0),
		"col_mid":   Color(0.30, 0.50, 1.0, 0.9),
		"col_outer": Color(0.55, 0.20, 0.95, 0.0),
	}

func _get_selected_vx_id() -> int:
	if _active_creep.is_empty() or _selected_vortex_idx < 0:
		return -1
	var vxs: Array = _vortex_points.get(_active_creep, [])
	if _selected_vortex_idx >= vxs.size():
		return -1
	return int(vxs[_selected_vortex_idx].get("id", _selected_vortex_idx + 1))

func _get_vx_style(vx_id: int) -> Dictionary:
	if _active_creep.is_empty() or vx_id < 0:
		return _default_vortex_style()
	if not _vortex_styles.has(_active_creep):
		_vortex_styles[_active_creep] = {}
	var cmap: Dictionary = _vortex_styles[_active_creep]
	var key := "vx_%d" % vx_id
	if not cmap.has(key):
		cmap[key] = _default_vortex_style()
	return cmap[key]

func _refresh_vortex_editor() -> void:
	if _vx_radius_spin == null:
		return
	var n := _selected_vortex_indices.size()
	var vx_id := _get_selected_vx_id()
	var has := vx_id >= 0
	if _vortex_lbl != null:
		if not has:
			_vortex_lbl.text = "– select a VX –"
			_vortex_lbl.modulate = Color(0.55, 0.55, 0.55)
		elif n <= 1:
			_vortex_lbl.text = "VX %d" % vx_id
			_vortex_lbl.modulate = Color(0.55, 0.80, 1.0)
		else:
			_vortex_lbl.text = "%d VXs selected" % n
			_vortex_lbl.modulate = Color(0.75, 0.90, 1.0)
	for spin: SpinBox in [_vx_radius_spin, _vx_spin_spin, _vx_arms_spin]:
		spin.editable = has
	for cpb: ColorPickerButton in [_vx_col_core_btn, _vx_col_mid_btn, _vx_col_outer_btn]:
		cpb.disabled = not has
	if not has:
		return
	_updating_vortex = true
	var s := _get_vx_style(vx_id)
	_vx_radius_spin.value   = float(s.get("radius", 40.0))
	_vx_spin_spin.value     = float(s.get("spin",   2.2))
	_vx_arms_spin.value     = float(s.get("arms",   3))
	_vx_col_core_btn.color  = s.get("col_core",  Color(0.75, 0.92, 1.0, 1.0))
	_vx_col_mid_btn.color   = s.get("col_mid",   Color(0.30, 0.50, 1.0, 0.9))
	_vx_col_outer_btn.color = s.get("col_outer", Color(0.55, 0.20, 0.95, 0.0))
	_updating_vortex = false

func _on_vortex_changed() -> void:
	if _updating_vortex or _active_creep.is_empty() or _selected_vortex_indices.is_empty():
		return
	if not _vortex_styles.has(_active_creep):
		_vortex_styles[_active_creep] = {}
	var vxs: Array = _vortex_points.get(_active_creep, [])
	for sel_idx: int in _selected_vortex_indices:
		if sel_idx < 0 or sel_idx >= vxs.size():
			continue
		var vx_id: int = int(vxs[sel_idx].get("id", sel_idx + 1))
		var s := _get_vx_style(vx_id)
		s["radius"]    = _vx_radius_spin.value
		s["spin"]      = _vx_spin_spin.value
		s["arms"]      = int(_vx_arms_spin.value)
		s["col_core"]  = _vx_col_core_btn.color
		s["col_mid"]   = _vx_col_mid_btn.color
		s["col_outer"] = _vx_col_outer_btn.color
		_vortex_styles[_active_creep]["vx_%d" % vx_id] = s
	_refresh_vortex_preview()
	_dirty = true

func _copy_vortex_style() -> void:
	if _active_creep.is_empty() or _selected_vortex_idx < 0:
		return
	var vx_id := _get_selected_vx_id()
	if vx_id < 0:
		return
	_vortex_clipboard = (_get_vx_style(vx_id) as Dictionary).duplicate(true)
	show_toast("Vortex style copied")

## Replace the selected VX(s)' style with the clipboard. No-op if nothing has been copied yet.
func _paste_vortex_style() -> void:
	if _vortex_clipboard.is_empty() or _active_creep.is_empty() or _selected_vortex_indices.is_empty():
		return
	# Push the clipboard into the controls (guarded so the per-spin signals don't write piecemeal),
	# then _on_vortex_changed() writes the whole style into every selected VX at once.
	_updating_vortex = true
	_vx_radius_spin.value   = float(_vortex_clipboard.get("radius", _vx_radius_spin.value))
	_vx_spin_spin.value     = float(_vortex_clipboard.get("spin",   _vx_spin_spin.value))
	_vx_arms_spin.value     = float(_vortex_clipboard.get("arms",   _vx_arms_spin.value))
	_vx_col_core_btn.color  = _vortex_clipboard.get("col_core",  _vx_col_core_btn.color)
	_vx_col_mid_btn.color   = _vortex_clipboard.get("col_mid",   _vx_col_mid_btn.color)
	_vx_col_outer_btn.color = _vortex_clipboard.get("col_outer", _vx_col_outer_btn.color)
	_updating_vortex = false
	_on_vortex_changed()
	show_toast("Vortex style pasted")

func _refresh_vortex_preview() -> void:
	for v in _preview_vortexes:
		if is_instance_valid(v):
			v.queue_free()
	_preview_vortexes.clear()
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var cmap: Dictionary = _vortex_styles.get(_active_creep, {})
	var vxs: Array = _vortex_points.get(_active_creep, [])
	for i: int in vxs.size():
		var vx: Dictionary = vxs[i]
		var vx_id: int = int(vx.get("id", i + 1))
		var style: Dictionary = cmap.get("vx_%d" % vx_id, _default_vortex_style())
		var ss_pos: Vector2 = vx["pos"]
		var node: Node2D = EnergyVortex.new()
		node.process_mode = Node.PROCESS_MODE_ALWAYS   # animate while the editor pauses the tree
		node.position = ss_pos + SCREEN_ORIGIN          # objects_container handles zoom/offset
		_objects_container.add_child(node)
		# Set z_index AFTER add_child: EnergyVortex._ready() forces z_index=2, so setting it
		# before add_child would be overwritten. Here the vortex is a SIBLING of the enemy EO
		# (z_index 115), so it needs an absolute z above the sprite to render on top.
		node.z_index = 120
		node.call("setup", style)
		_preview_vortexes.append(node)

# ── Led Points (2026-08-15) ─────────────────────────────────────────────────────
# A directionless point anchoring a small glowing/blinking light (LedLight). Mirrors Vortex Points exactly —
# per-point style: W/H/color/intensity/blink Hz instead of radius/spin/arms/colors.
func _toggle_adding_ledpoint() -> void:
	_adding_ledpoint = _add_led_btn.button_pressed
	if _adding_ledpoint:
		_adding_firepoint = false
		_adding_thrustpoint = false
		_adding_tentaclepoint = false
		_adding_vortexpoint = false
		_add_fp_btn.button_pressed = false
		_add_tp_btn.button_pressed = false
		_add_tenp_btn.button_pressed = false
		_add_vortex_btn.button_pressed = false
		_grid_mode = false
		_grid_btn.button_pressed = false
		_select_obj(null)
		_select_fp(-1)
		_select_tp(-1)
		_select_tenp(-1)
		_select_vortex(-1)
	_update_all_creep_interactivity()

func _add_ledpoint_at(viewport_pos: Vector2) -> void:
	if _active_creep.is_empty():
		return
	var oc_pos: Vector2 = _objects_container.position if (_objects_container != null and is_instance_valid(_objects_container)) else Vector2.ZERO
	var ss_pos := (viewport_pos - oc_pos) / _zoom - SCREEN_ORIGIN
	if not _led_points.has(_active_creep):
		_led_points[_active_creep] = []
		_led_id_counter[_active_creep] = 1
	var led_id: int = _led_id_counter.get(_active_creep, 1)
	_led_points[_active_creep].append({"pos": ss_pos, "id": led_id})
	_led_id_counter[_active_creep] = led_id + 1
	_selected_led_idx = _led_points[_active_creep].size() - 1
	_selected_led_indices = [_selected_led_idx]
	_dirty = true
	_refresh_led_list()
	_refresh_led_editor()
	_refresh_dynamic_panels()
	_update_grid_overlay()

func _select_led(idx: int) -> void:
	_selected_led_idx = idx
	_led_range_anchor = idx   # plain click always re-anchors a future Shift-click range here
	_selected_led_indices.clear()
	if idx >= 0:
		_selected_led_indices.append(idx)
		_select_obj(null)
		_selected_fp_idx = -1
		_selected_tp_idx = -1
		_selected_tp_indices.clear()
		_selected_tenp_idx = -1
		_selected_vortex_idx = -1
		_selected_vortex_indices.clear()
	_refresh_led_list()
	_refresh_led_editor()
	_update_grid_overlay()

## 2026-08-15: Shift-click range-selects from the fixed anchor (last plain click) through `idx`, inclusive —
## see _select_tp_add()'s comment for the full reasoning (same behavior, ported here).
func _select_led_add(idx: int) -> void:
	if idx < 0:
		return
	_select_obj(null)
	_selected_fp_idx = -1
	_selected_tp_idx = -1
	_selected_tp_indices.clear()
	_selected_tenp_idx = -1
	_selected_vortex_idx = -1
	_selected_vortex_indices.clear()
	if _led_range_anchor < 0:
		_led_range_anchor = idx
	var lo := mini(_led_range_anchor, idx)
	var hi := maxi(_led_range_anchor, idx)
	_selected_led_indices.clear()
	for i in range(lo, hi + 1):
		_selected_led_indices.append(i)
	_selected_led_idx = idx
	_refresh_led_list()
	_refresh_led_editor()
	_update_grid_overlay()

func _delete_selected_led() -> void:
	if _selected_led_indices.is_empty():
		return
	var leds: Array = _led_points.get(_active_creep, [])
	var sorted: Array[int] = _selected_led_indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for idx: int in sorted:
		if idx >= 0 and idx < leds.size():
			leds.remove_at(idx)
	_led_points[_active_creep] = leds
	_selected_led_idx = -1
	_selected_led_indices.clear()
	_dirty = true
	_refresh_led_list()
	_refresh_led_editor()
	_refresh_dynamic_panels()
	_update_grid_overlay()

func _refresh_led_list() -> void:
	if _led_vbox == null:
		return
	for child in _led_vbox.get_children():
		child.queue_free()
	var leds: Array = _led_points.get(_active_creep, [])
	for i: int in leds.size():
		_led_vbox.add_child(_make_led_row(leds[i], i))

func _make_led_row(pt: Dictionary, idx: int) -> Control:
	var is_sel: bool = _selected_led_indices.has(idx)
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 28.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.85, 0.35, 0.35) if is_sel else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	row.add_child(hbox)
	var pt_id: int   = pt.get("id", idx + 1)
	var pos: Vector2 = pt.get("pos", Vector2.ZERO)
	var id_lbl := Label.new()
	id_lbl.text = "Led%d" % pt_id
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.custom_minimum_size = Vector2(38.0, 0.0)
	id_lbl.modulate = Color(1.0, 0.90, 0.55) if is_sel else Color(0.85, 0.70, 0.35)
	hbox.add_child(id_lbl)
	var pos_lbl := Label.new()
	pos_lbl.text = "(%d,%d)" % [int(pos.x), int(pos.y)]
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(pos_lbl)
	var cap_idx := idx
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			if Input.is_key_pressed(KEY_SHIFT):
				_select_led_add(cap_idx)
			else:
				_select_led(cap_idx)
	)
	return row

func _default_led_style() -> Dictionary:
	return {
		"w":          12.0,
		"h":          12.0,
		"color":      Color(1.0, 0.85, 0.35, 1.0),
		"intensity":  1.0,
		"blink_hz":   0.0,
		"phase_deg":  0.0,   # 2026-08-15 — this LED's own blink cycle offset; stagger across LEDs for a wave
		"rotate_deg": 0.0,   # 2026-08-15 — extra rotation on top of whatever the anchor (body/segment) applies
	}

func _get_selected_led_id() -> int:
	if _active_creep.is_empty() or _selected_led_idx < 0:
		return -1
	var leds: Array = _led_points.get(_active_creep, [])
	if _selected_led_idx >= leds.size():
		return -1
	return int(leds[_selected_led_idx].get("id", _selected_led_idx + 1))

func _get_led_style(led_id: int) -> Dictionary:
	if _active_creep.is_empty() or led_id < 0:
		return _default_led_style()
	if not _led_styles.has(_active_creep):
		_led_styles[_active_creep] = {}
	var cmap: Dictionary = _led_styles[_active_creep]
	var key := "led_%d" % led_id
	if not cmap.has(key):
		cmap[key] = _default_led_style()
	return cmap[key]

func _refresh_led_editor() -> void:
	if _led_w_spin == null:
		return
	var n := _selected_led_indices.size()
	var led_id := _get_selected_led_id()
	var has := led_id >= 0
	if _led_lbl != null:
		if not has:
			_led_lbl.text = "– select a LED –"
			_led_lbl.modulate = Color(0.55, 0.55, 0.55)
		elif n <= 1:
			_led_lbl.text = "LED %d" % led_id
			_led_lbl.modulate = Color(1.0, 0.85, 0.45)
		else:
			_led_lbl.text = "%d LEDs selected" % n
			_led_lbl.modulate = Color(1.0, 0.90, 0.55)
	for spin: SpinBox in [_led_w_spin, _led_h_spin, _led_intensity_spin, _led_phase_spin, _led_rotate_spin]:
		spin.editable = has
	_led_col_btn.disabled = not has
	_led_blink_slider.editable = has
	if not has:
		return
	_updating_led = true
	var s := _get_led_style(led_id)
	_led_w_spin.value         = float(s.get("w", 12.0))
	_led_h_spin.value         = float(s.get("h", 12.0))
	_led_col_btn.color        = s.get("color", Color(1.0, 0.85, 0.35, 1.0))
	_led_intensity_spin.value = float(s.get("intensity", 1.0))
	_led_blink_slider.value   = float(s.get("blink_hz", 0.0))
	_led_blink_lbl.text       = "%dHz" % int(_led_blink_slider.value)
	_led_phase_spin.value     = float(s.get("phase_deg", 0.0))
	_led_rotate_spin.value    = float(s.get("rotate_deg", 0.0))
	_updating_led = false

func _on_led_changed() -> void:
	if _updating_led or _active_creep.is_empty() or _selected_led_indices.is_empty():
		return
	if not _led_styles.has(_active_creep):
		_led_styles[_active_creep] = {}
	var leds: Array = _led_points.get(_active_creep, [])
	for sel_idx: int in _selected_led_indices:
		if sel_idx < 0 or sel_idx >= leds.size():
			continue
		var led_id: int = int(leds[sel_idx].get("id", sel_idx + 1))
		var s := _get_led_style(led_id)
		s["w"]         = _led_w_spin.value
		s["h"]         = _led_h_spin.value
		s["color"]     = _led_col_btn.color
		s["intensity"] = _led_intensity_spin.value
		s["blink_hz"]  = _led_blink_slider.value
		s["phase_deg"]  = _led_phase_spin.value
		s["rotate_deg"] = _led_rotate_spin.value
		_led_styles[_active_creep]["led_%d" % led_id] = s
	_refresh_led_preview()
	_dirty = true

func _copy_led_style() -> void:
	if _active_creep.is_empty() or _selected_led_idx < 0:
		return
	var led_id := _get_selected_led_id()
	if led_id < 0:
		return
	_led_clipboard = (_get_led_style(led_id) as Dictionary).duplicate(true)
	show_toast("Led style copied")

## Replace the selected LED(s)' style with the clipboard. No-op if nothing has been copied yet.
func _paste_led_style() -> void:
	if _led_clipboard.is_empty() or _active_creep.is_empty() or _selected_led_indices.is_empty():
		return
	_updating_led = true
	_led_w_spin.value         = float(_led_clipboard.get("w", _led_w_spin.value))
	_led_h_spin.value         = float(_led_clipboard.get("h", _led_h_spin.value))
	_led_col_btn.color        = _led_clipboard.get("color", _led_col_btn.color)
	_led_intensity_spin.value = float(_led_clipboard.get("intensity", _led_intensity_spin.value))
	_led_blink_slider.value   = float(_led_clipboard.get("blink_hz", _led_blink_slider.value))
	_led_blink_lbl.text       = "%dHz" % int(_led_blink_slider.value)
	_led_phase_spin.value     = float(_led_clipboard.get("phase_deg", _led_phase_spin.value))
	_led_rotate_spin.value    = float(_led_clipboard.get("rotate_deg", _led_rotate_spin.value))
	_updating_led = false
	_on_led_changed()
	show_toast("Led style pasted")

## "Apply Wave" (2026-08-15) — assigns phase_deg = index × Wave-step to EVERY LED point of the active creep,
## in placement order (index 0, 1, 2, … — same order the LAYERS-style LED list shows them in), completely
## independent of whatever's currently selected. The direct, mistake-proof way to get "1 dải sóng tín hiệu
## chạy từ đầu về đuôi" — the multi-select-and-drag-Phase approach applies one shared value to every selected
## LED at once (by design — see the comment on the Wave-step row above), which can never produce a stagger.
func _apply_led_wave() -> void:
	if _active_creep.is_empty():
		return
	var leds: Array = _led_points.get(_active_creep, [])
	if leds.is_empty():
		return
	if not _led_styles.has(_active_creep):
		_led_styles[_active_creep] = {}
	var step: float = _led_wave_step_spin.value
	for i: int in leds.size():
		var led_id: int = int(leds[i].get("id", i + 1))
		var s := _get_led_style(led_id)
		s["phase_deg"] = fmod(float(i) * step, 360.0)
		_led_styles[_active_creep]["led_%d" % led_id] = s
	_refresh_led_editor()
	_refresh_led_preview()
	_dirty = true
	show_toast("Wave applied to %d LED(s)" % leds.size())

func _refresh_led_preview() -> void:
	for l in _preview_leds:
		if is_instance_valid(l):
			l.queue_free()
	_preview_leds.clear()
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var cmap: Dictionary = _led_styles.get(_active_creep, {})
	var leds: Array = _led_points.get(_active_creep, [])
	for i: int in leds.size():
		var led: Dictionary = leds[i]
		var led_id: int = int(led.get("id", i + 1))
		var style: Dictionary = cmap.get("led_%d" % led_id, _default_led_style())
		var ss_pos: Vector2 = led["pos"]
		var node: Node2D = LedLight.new()
		node.process_mode = Node.PROCESS_MODE_ALWAYS   # animate (blink) while the editor pauses the tree
		node.position = ss_pos + SCREEN_ORIGIN          # objects_container handles zoom/offset
		node.rotation = deg_to_rad(float(style.get("rotate_deg", 0.0)))   # static preview — no body/segment to auto-orient to, just the user's own Rotate value
		_objects_container.add_child(node)
		# Same z_index-after-add_child reasoning as _refresh_vortex_preview(): LedLight._ready() forces
		# z_index=3, so set it after — the LED is a sibling of the enemy EO (z_index 115), needs an absolute
		# z above the sprite to render on top.
		node.z_index = 120
		node.call("setup", style)
		_preview_leds.append(node)

func _make_point_row(pt: Dictionary, idx: int, is_fp: bool) -> Control:
	var is_sel: bool = (idx == _selected_fp_idx) if is_fp else _selected_tp_indices.has(idx)
	var col_sel  := Color(0.25, 0.85, 1.0, 0.38) if is_fp else Color(0.10, 0.80, 0.55, 0.38)
	var col_id   := Color(0.25, 0.85, 1.0) if is_fp else Color(0.10, 0.90, 0.65)
	var id_sel   := Color(1.0, 0.55, 0.12) if is_fp else Color(0.10, 0.75, 0.55)

	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 30.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = col_sel if is_sel else Color(0.0, 0.0, 0.0, 0.0)
	style.corner_radius_top_left    = 3; style.corner_radius_top_right    = 3
	style.corner_radius_bottom_left = 3; style.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 5)
	row.add_child(hbox)

	var pt_id: int   = pt.get("id",  idx + 1)
	var pos: Vector2 = pt.get("pos", Vector2.ZERO)
	var angle_deg    := int(round(rad_to_deg(float(pt.get("dir_angle", 0.0)))))
	var prefix       := "FP" if is_fp else "TP"

	var id_lbl := Label.new()
	id_lbl.text = "%s%d" % [prefix, pt_id]
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.custom_minimum_size = Vector2(30.0, 0.0)
	id_lbl.modulate = col_id if is_sel else id_sel
	hbox.add_child(id_lbl)

	var pos_lbl := Label.new()
	# 2026-08-21 ("dòng (tọa độ X, tọa độ Y) 90 độ... không còn đúng nữa"): a 3D TP (has "dir_rot") is edited
	# with the "3D VIEW / MOUNT ANGLE" Rotate X/Y/Z sliders now, not the flat single-axis `dir_angle` this row
	# used to show — that field is still SAVED (backward-compat, see _save_layout) but no longer means
	# anything for a 3D TP, so showing it here was actively misleading. Swap to the real 3-axis position
	# (_tp_xyz_get — same X/Y/Z-relative-to-object frame the "TP POS X/Y/Z" transform panel already uses) and
	# the 3-axis rotation in degrees. A plain 2D TP/FP (no "dir_rot") keeps the original flat display exactly
	# as before.
	if not is_fp and pt.has("dir_rot"):
		var xyz: Vector3 = _tp_xyz_get(_active_creep, pt)
		var rot: Vector3 = pt["dir_rot"]
		pos_lbl.text = "(%d,%d,%d) R:%d,%d,%d°" % [
			int(round(xyz.x)), int(round(xyz.y)), int(round(xyz.z)),
			int(round(rad_to_deg(rot.x))), int(round(rad_to_deg(rot.y))), int(round(rad_to_deg(rot.z)))]
	else:
		pos_lbl.text = "(%d,%d) %d°" % [int(pos.x), int(pos.y), angle_deg]
	pos_lbl.add_theme_font_size_override("font_size", 10)
	pos_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(pos_lbl)

	var cap_idx := idx
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (e as InputEventMouseButton).pressed:
			if is_fp:
				_select_fp(cap_idx)
			elif Input.is_key_pressed(KEY_SHIFT):
				_select_tp_add(cap_idx)
			else:
				_select_tp(cap_idx)
	)
	return row

# ── Grid overlay sync ──────────────────────────────────────────────────────────

func _reset_zoom() -> void:
	_zoom = 1.0
	if _objects_container != null and is_instance_valid(_objects_container):
		_objects_container.position = Vector2.ZERO
		_objects_container.scale    = Vector2.ONE
	if _grid_overlay != null:
		_grid_overlay.zoom          = 1.0
		_grid_overlay.canvas_offset = Vector2.ZERO
	_sync_zoom_slider()

func _apply_zoom(mouse_vp: Vector2) -> void:
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var old_offset := _objects_container.position
	var old_zoom   := _objects_container.scale.x
	_objects_container.position = mouse_vp + (old_offset - mouse_vp) * (_zoom / old_zoom)
	_objects_container.scale    = Vector2(_zoom, _zoom)
	_sync_zoom_slider()
	_update_grid_overlay()

func _sync_zoom_slider() -> void:
	if _zoom_slider == null or _updating_spin:
		return
	_updating_spin = true
	_zoom_slider.value = clampf(_zoom * 100.0, _zoom_slider.min_value, _zoom_slider.max_value)
	if _zoom_pct_lbl != null:
		_zoom_pct_lbl.text = "%d%%" % int(round(_zoom * 100.0))
	_updating_spin = false

func _on_zoom_slider_changed(value: float) -> void:
	if _updating_spin:
		return
	_zoom = value / 100.0
	var center := get_viewport().get_visible_rect().size * 0.5
	_apply_zoom(center)
	if _zoom_pct_lbl != null:
		_zoom_pct_lbl.text = "%d%%" % int(round(value))

func _update_grid_overlay() -> void:
	if _grid_overlay == null:
		return
	_grid_overlay.fire_points     = _fire_points.get(_active_creep, [])
	_grid_overlay.selected_fp_idx = _selected_fp_idx
	_grid_overlay.thrust_points   = _thrust_points.get(_active_creep, [])
	_grid_overlay.selected_tp_idx = _selected_tp_idx
	_grid_overlay.tentacle_points   = _tentacle_points.get(_active_creep, [])
	_grid_overlay.selected_tenp_idx = _selected_tenp_idx
	_grid_overlay.vortex_points     = _vortex_points.get(_active_creep, [])
	_grid_overlay.selected_vortex_idx = _selected_vortex_idx
	_grid_overlay.led_points        = _led_points.get(_active_creep, [])
	_grid_overlay.selected_led_idx  = _selected_led_idx
	_grid_overlay.front_markers = _front_markers()
	if _objects_container != null and is_instance_valid(_objects_container):
		_grid_overlay.zoom          = _zoom
		_grid_overlay.canvas_offset = _objects_container.position
	_refresh_plume_preview()
	_refresh_vortex_preview()
	_refresh_led_preview()

func _refresh_plume_preview() -> void:
	_glb_refresh_tp_gizmos(_active_creep)   # 3D counterpart (no-op for non-glb creeps) — keeps the real
	# plume preview in sync with style edits too (_on_plume_changed/_reset_plume_style both flow through
	# here), not just TP add/move — see _glb_refresh_tp_gizmos's own header.
	for p: CPUParticles2D in _preview_plumes:
		if is_instance_valid(p):
			p.queue_free()
	_preview_plumes.clear()
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	var cmap: Dictionary = _plume_styles.get(_active_creep, {})
	var tps: Array = _thrust_points.get(_active_creep, [])
	for i: int in tps.size():
		var tp: Dictionary = tps[i]
		var tp_id: int = int(tp.get("id", i + 1))
		var style: Dictionary = cmap.get("tp_%d" % tp_id, _default_plume_style())
		var ss_pos: Vector2 = tp["pos"]
		# 2026-08-22 ("Plume 2D không được spawn tại các object 3D" / "Plume 3D spawn tại điểm tôi click"):
		# a 3D TP gets a REAL 3D plume preview here instead of the flat CPUParticles2D below — see
		# `_preview_plumes3d`'s own header for why the 2D one could never rotate (it reads `dir_angle`, which
		# the Rotate X/Y/Z sliders never touch). Both render at the SAME canvas point (the click position),
		# so this is a straight swap of representation, not a move.
		if tp.has("dir_rot"):
			continue   # handled by _refresh_plume3d_preview(), called at the tail of this function
		var dir_angle: float = float(tp.get("dir_angle", PI * 0.5))
		var p := _make_preview_plume(ss_pos + SCREEN_ORIGIN, dir_angle, style)
		_objects_container.add_child(p)
		_preview_plumes.append(p)
	_refresh_plume3d_preview()

## Frees the full-screen 3D overlay (its SubViewport, which holds every part model + plume, and the
## TextureRect that composites it onto the canvas) and forgets the pivot table. Called both before a rebuild
## and on close — the overlay's two halves live on nodes that outlive the editor panel, so nothing else
## reclaims them.
func _clear_plume3d_preview() -> void:
	var old_layer: TextureRect = _preview_plumes3d.get("layer")
	if old_layer != null and is_instance_valid(old_layer):
		old_layer.queue_free()
	var old_vp: SubViewport = _preview_plumes3d.get("vp")
	if old_vp != null and is_instance_valid(old_vp):
		old_vp.queue_free()
	_preview_plumes3d.clear()

## Builds one standalone 3D plume preview per 3D TP of the active creep, at that TP's own click position on
## the edit canvas — see `_preview_plumes3d`'s header for the architecture and why it replaces the flat 2D
## preview. Full teardown+rebuild (cheap: a handful of TPs, only on add/select/style-change, NOT per slider
## tick — `_on_glb_rotation_changed()` writes `pivot.rotation` directly for that, see there).
func _refresh_plume3d_preview() -> void:
	_build_plume3d_preview()
	# The overlay and the flat thumbnails are two halves of one decision — which representation of each part
	# is on screen — so the second half runs from here rather than from the handful of call sites that
	# happened to remember it. Covers the early returns below too: with no overlay built, `covered` comes out
	# empty and every thumbnail is restored.
	_sync_flat_thumbnails()

func _build_plume3d_preview() -> void:
	_clear_plume3d_preview()
	# Safety net, same shape as this file's other "the editor owns this node" guards: several refresh paths
	# (_update_grid_overlay -> _refresh_plume_preview, style edits, chain rebuilds) can still fire while the
	# panel is closing, and any one of them would rebuild the overlay right back onto the running game.
	if not _is_open:
		return
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	if _active_glb_path.is_empty():
		return
	var eo: EditableObjectNode = _placed.get(_active_creep, null)
	if eo == null or not is_instance_valid(eo) or eo.size.x < 0.01 or eo.size.y < 0.01:
		return
	var rig_data: Dictionary = _glb_preview_cache.get(_active_glb_path, {})
	if rig_data.is_empty():
		return
	if float(rig_data.get("target_px", 32.0)) <= 0.001:
		return
	# Per-part display size and per-part style/TP lists are read inside the member loop below now — a group's
	# parts don't share any of them (a 44px head next to a 25.2px body), so hoisting the ACTIVE part's values
	# out here is exactly what made every other part render at the wrong scale.
	var rig := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()

	# ── One shared 3D scene, in canvas coordinates ────────────────────────────────────────────────────
	# 2026-08-22 ("muốn xoay qua xoay lại để căn chỉnh các part và plume cho chính xác, chứ ko phải xoay rồi
	# lưu"): the parts and their plumes are assembled here as ONE real 3D scene at their canvas positions
	# (1 world unit = 1 canvas px), and the VIEW CUBE orbits this scene's camera. That makes the orbit a pure
	# RENDER — nothing writes back to any EO position or to the cfg, so you can spin around, check that a
	# plume leaves the right spot on the right part, and come back with the layout untouched. It is the
	# reason this had to be one scene instead of the per-part thumbnails: separate viewports pinned to fixed
	# canvas rects can only ever spin each model in place, never show the parts' true spatial relationship.
	# ── Frame + resolution ────────────────────────────────────────────────────────────────────────────
	# 2026-08-23 ("các hình rất mờ"): this used to render the WHOLE SCREEN at 1 texture pixel per canvas
	# pixel. `cam.size = screen.y` means 1 world unit = 1 texture pixel, so a 44 px VIPER head got exactly
	# 44x44 pixels of detail — while the per-part thumbnail it replaced was a GLB_PREVIEW_PX (512) render
	# squeezed into the same 44 px rect, i.e. more than 10x the sampling, and still sharp when the canvas is
	# zoomed in. Swapping the sharp one for the soft one is what "rất mờ" was; the headlamp added in the 24th
	# pass was a real omission but not this.
	# Fixed by framing only what has to be visible and spending the pixels there. A square frame of radius
	# (half the group's bbox DIAGONAL + a plume allowance) can't clip at any view angle, because orbiting is a
	# rotation about the pivot and a point at radius r stays at radius r. That is a few hundred px instead of
	# a full screen, so it affords a real supersample within a sane texture budget.
	var root_name: String = _active_creep
	var par: String = _creep_parents.get(_active_creep, "")
	if not par.is_empty():
		root_name = par
	var bb := _group_render_bbox(root_name)
	var frame_half: float = maxf(bb.size.length() * 0.5, 48.0) + PLUME3D_FRAME_MARGIN
	var frame: float = frame_half * 2.0
	var ss: float = clampf(float(PLUME3D_MAX_TEX) / frame, 1.0, PLUME3D_SUPERSAMPLE)
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(int(frame * ss), 1), maxi(int(frame * ss), 1))
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	rig.build_lighting(vp)

	# Orbit pivot = the centre of whatever group is being edited, so spinning inspects THAT, not the canvas
	# corner. The layer is offset by the same amount, which is what keeps Game view pixel-exact: at pitch 90
	# the pivot projects to the frame centre, the offset puts that centre back on the pivot's own canvas
	# point, and every other point follows 1:1 (verified: a TP still draws exactly where it was clicked).
	var pivot2: Vector2 = (bb.position + bb.size * 0.5) if bb.size.length() > 0.01 else (eo.position + eo.size * 0.5)
	var pivot3 := Vector3(pivot2.x, 0.0, pivot2.y)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = frame               # world units across the frame; the SubViewport supplies the pixel density
	cam.near = 0.05
	cam.far = 20000.0
	cam.look_at_from_position(pivot3 + _view_dir() * 4000.0, pivot3, _view_up())
	# 2026-08-23 ("cả 3 đều rất mờ"): the per-part thumbnail rigs each add a camera-aligned headlamp on top of
	# `build_lighting()`'s 2 fixed directional lights (see _load_glb_topdown_tex, and glb_topdown_rig.gd's
	# `make_camera`, which bundles one for exactly this reason) — this overlay built its camera by hand and
	# never got one. Invisible while the overlay was only ever showing plumes and the crisp thumbnails did the
	# models; the moment it became the sole renderer, every part was lit by ambient + 2 glancing lights alone
	# and read as washed out. Same class of bug as item_3d_icon.gd's own dark-render fix.
	var headlamp := DirectionalLight3D.new()
	headlamp.rotation = cam.rotation
	headlamp.light_energy = 1.6
	vp.add_child(headlamp)

	# Every part of the group as a real model at its own canvas position — this is what makes the orbit show
	# the assembly rather than three unrelated thumbnails.
	#
	# 2026-08-22 ("có sự sai lệch giữa weapon hiển thị trên arena và trong weapon edit... lấy nguồn dữ liệu
	# hiển thị từ cùng 1 nguồn"): this overlay is now the SINGLE renderer for a 3D part — the flat EO
	# thumbnails are hidden for every part drawn here (see _sync_flat_thumbnails) instead of being shown at
	# Game view and hidden when orbited. Two reasons that swap was necessary rather than cosmetic:
	#   * a thumbnail's model is framed by its own preview camera (bounding-sphere fit + GLB_FRAME_MARGIN
	#     padding) and then STRETCHED to whatever the EO rect happens to be, so its apparent size was a
	#     function of the editor's framing constants and the user's W/H — nothing the game shares;
	#   * this scene draws at 1 world unit = 1 canvas px and now fits each model to `target_px`, the SAME
	#     number arena_weapons.gd renders it at (arena_weapons.display_px_for, reached through the
	#     `_arena_display_px()` hook). 44px head, 25.2px body, exactly as in the game.
	# With one renderer left there is nothing to keep in sync and nothing to double up.
	var pivots: Dictionary = {}
	var rot_pivot: Node3D = null
	for cname: String in _group_render_names(root_name):
		if bool(_layer_hidden.get(cname, false)):
			continue   # eye closed — see _layer_hidden
		var meo: EditableObjectNode = _placed.get(cname, null)
		if meo == null or not is_instance_valid(meo):
			continue
		var dname := _chain_data_name(cname)   # a duplicate reads its template's rotation/TPs/style
		# ...and its ASSET, which is the template's too. Independent of whatever `duplicate()` did or didn't
		# carry over (see _make_chain_dup_eo), so a future regression there can't blank the chain again.
		var mpath: String = meo.source_path
		var teo: EditableObjectNode = _placed.get(dname, null)
		if teo != null and is_instance_valid(teo):
			mpath = teo.source_path
		if mpath.get_extension().to_lower() != "glb":
			continue
		var mrig: Dictionary = _glb_preview_cache.get(_rig_key(dname, mpath), {})
		var part := Node3D.new()
		var mctr := meo.position + meo.size * 0.5
		# view space: canvas X -> X, the part's editor-space Z (vertical) -> view Y, canvas Y -> view Z.
		part.position = Vector3(mctr.x, _rig_z(mrig), mctr.y)
		part.rotation = rig.view_rotation(
			rig.compose_rot(mrig.get("rot_base", Vector3.ZERO), mrig.get("rot", Vector3.ZERO)))
		vp.add_child(part)
		# The model fills its own canvas rect. That is a ZOOM on the arena's `display_px`, never a different
		# shape — and because a TP is placed just below at `(frac - 0.5) * part_px`, the TP moves with it, so
		# it lands on the same spot of the same model as in game whatever the rect is. See the note above
		# `_auto_arrange_chain_templates` for why the rect is the user's and not forced to `display_px`.
		var part_px: float = maxf(meo.size.x, meo.size.y)
		var model: Node3D = rig.load_model(mpath)
		if model != null:
			rig.center_and_fit(model, part_px)
			part.add_child(model)
			# Each part's OWN clip — several layers can share one glb now, and without this they would all
			# render whichever animation happened to sort first in the merged file.
			_play_preview_animation(model, _preview_clip(dname))
		# Every part's OWN thrust points, not just the active one's (2026-08-22, "plume trên arena có, nhưng
		# trong edit lại không hiện"). The arena builds a plume anchor for head, body and tail alike, so
		# showing only `_active_creep`'s meant a VIPER whose TPs live on the Tail rendered no plume at all
		# while the head or the group row was selected — which is the normal way to have VIPER open.
		# Position uses the arena's own formula — `(frac - 0.5) * target_px` against the part's display size,
		# the same conversion arena_weapons.gd does when it reads the very same saved TP — instead of the raw
		# canvas offset this used before. The two agree only when an EO rect happens to equal `target_px`,
		# so the editor and the game were placing one saved TP at two different points on the model.
		for i: int in _thrust_points.get(dname, []).size():
			var tp: Dictionary = (_thrust_points.get(dname, []) as Array)[i]
			if not tp.has("dir_rot"):
				continue
			var tp_id: int = int(tp.get("id", i + 1))
			var pstyle: Dictionary = (_plume_styles.get(dname, {}) as Dictionary).get(
				"tp_%d" % tp_id, _default_plume_style())
			var frac := (((tp["pos"] as Vector2) + SCREEN_ORIGIN) - meo.position) / meo.size
			var pivot := Node3D.new()
			pivot.position = Vector3((frac.x - 0.5) * part_px, float(tp.get("z", 0.0)),
				(frac.y - 0.5) * part_px)
			# The part node above already carries the object half, so this holds only the TP's own angle — but
			# it must still be the COMPOSED (base ∘ dir_rot) one, carried into view space. 2026-08-22: the raw
			# read here silently dropped any banked "Set 0° here" baseline, so a TP with one rendered at a
			# different angle from the moment a slider was touched (_apply_rotation_delta writes composed).
			pivot.rotation = rig.view_rotation(
				rig.compose_rot(tp.get("dir_rot_base", Vector3.ZERO), tp.get("dir_rot", Vector3.ZERO)))
			part.add_child(pivot)
			var p: CPUParticles3D = rig.make_plume(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), pstyle, part_px)
			p.process_mode = Node.PROCESS_MODE_ALWAYS   # editor pauses the tree — keep emitting
			pivot.add_child(p)
			# Only the ACTIVE part's pivots go in the live-edit table: the rotate sliders address a TP by id
			# alone, and ids restart at 1 per part, so keying every part's here would collide.
			if cname == _active_creep:
				pivots[tp_id] = pivot
		if cname == _active_creep:
			rot_pivot = part

	if rot_pivot == null:   # active part had no glb model — still need a node to hang its TPs off
		rot_pivot = Node3D.new()
		var ac := eo.position + eo.size * 0.5
		rot_pivot.position = Vector3(ac.x, _rig_z(rig_data), ac.y)
		rot_pivot.rotation = rig.view_rotation(
			rig.compose_rot(rig_data.get("rot_base", Vector3.ZERO), rig_data.get("rot", Vector3.ZERO)))
		vp.add_child(rot_pivot)

	var layer := TextureRect.new()
	layer.texture = vp.get_texture()
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	layer.size = Vector2(frame, frame)
	layer.position = pivot2 - layer.size * 0.5   # see the pivot comment above
	# Sharp downsample of the supersampled render; without this the default nearest/linear pick can alias.
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_as_relative = false
	layer.z_index = 200
	_objects_container.add_child(layer)
	_preview_plumes3d = {"vp": vp, "rot_pivot": rot_pivot, "layer": layer, "pivots": pivots}

func _make_preview_plume(oc_pos: Vector2, dir_angle: float, style: Dictionary = {}) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = oc_pos
	p.amount = 20
	p.lifetime  = float(style.get("lifetime", 0.35))
	p.local_coords = true
	p.emitting = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.z_as_relative = false
	p.z_index = 200
	p.gravity = Vector2.ZERO
	p.direction = Vector2.RIGHT.rotated(dir_angle)
	p.spread              = float(style.get("spread",   12.0))
	p.initial_velocity_min = float(style.get("vel_min", 50.0))
	p.initial_velocity_max = float(style.get("vel_max", 90.0))
	p.scale_amount_min    = float(style.get("sc_min",  1.0))
	p.scale_amount_max    = float(style.get("sc_max",  2.0))
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = taper
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(16, 16) * 0.5
	for iy in 16:
		for ix in 16:
			var d: float = Vector2(ix + 0.5, iy + 0.5).distance_to(ctr) / 8.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(ix, iy, Color(1.0, 1.0, 1.0, a * a))
	p.texture = ImageTexture.create_from_image(img)
	var col_core:  Color = style.get("col_core",  Color(1.0, 0.95, 0.7, 1.0))
	var col_flame: Color = style.get("col_flame", Color(1.0, 0.6,  0.2, 1.0))
	var col_cool:  Color = style.get("col_cool",  Color(0.45, 0.6, 1.0, 0.85))
	var col_fade           := col_cool; col_fade.a = 0.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	grad.colors  = PackedColorArray([col_core, col_flame, col_cool, col_fade])
	p.color_ramp = grad
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cm
	return p

# ── Interactivity ──────────────────────────────────────────────────────────────

func _update_all_creep_interactivity() -> void:
	var allow_select: bool = not _grid_mode and not _adding_firepoint and not _adding_thrustpoint and not _adding_tentaclepoint and not _adding_vortexpoint and not _adding_ledpoint
	# Build the set of sprites that should be visible: the whole group (root + all its children).
	# Whether the active member is the root or a child, the entire assembly stays visible.
	var visible_set: Dictionary = {}
	if _is_open and not _active_creep.is_empty():
		var group_root: String = _creep_parents.get(_active_creep, "")
		if group_root.is_empty():
			group_root = _active_creep  # active is the root itself
		visible_set[group_root] = true
		for cname: String in _all_creep_names:
			if _creep_parents.get(cname, "") == group_root:
				visible_set[cname] = true
	for creep_name: String in _all_creep_names:
		var eo: EditableObjectNode = _placed.get(creep_name, null)
		if eo == null or not is_instance_valid(eo):
			continue
		var is_active:    bool = _is_open and creep_name == _active_creep
		var is_companion: bool = _is_open and (not is_active) and visible_set.has(creep_name)
		eo.set_gameplay_mode(not _is_open)
		# The eye toggle only ever SUBTRACTS from the group rule (2026-08-23 fix). It used to be applied in
		# its own pass right after this one, which overwrote this line and made every placed creep visible at
		# once — with nothing selected, `visible_set` is empty and the canvas should be empty too, but instead
		# it showed every Jeager clip layer plus VIPER, missile, bomb and the rest on top of each other.
		eo.visible = (visible_set.has(creep_name)
			and not bool(_layer_hidden.get(creep_name, false))) if _is_open else false
		if _is_open:
			eo.gif_paused = true
			eo.reset_gif()
		else:
			eo.gif_paused = false
		# Companions (children/parent) are also clickable so user can click-to-switch-active
		eo.mouse_filter = Control.MOUSE_FILTER_STOP \
			if ((is_active or is_companion) and _is_open and allow_select) \
			else Control.MOUSE_FILTER_IGNORE

func _on_canvas_object_clicked(obj: EditableObjectNode) -> void:
	if not _is_open or _grid_mode:
		return
	# If the clicked object belongs to a different creep, switch active to it
	for cname: String in _placed:
		if _placed[cname] == obj and cname != _active_creep:
			_set_active_creep(cname)
			return
	_select_obj(obj)

## 2026-08-14 hardened ("1 miếng tail và 1 miếng body của cent bay lòng vòng trên arena" — confirmed NOT a
## stale old enemy instance): this used to only walk `_all_creep_names`, so ANY placed EO that wasn't (or was
## no longer) in that list — for whatever reason, not just the already-fixed map-switch case — could be
## skipped and left permanently `visible = true` as a static overlay floating at wherever its EDITOR CANVAS
## coordinate happens to sit on screen (a totally different coordinate space than where a real enemy actually
## spawns in the arena — hence looking like it's "in some random spot"). Now iterates every EO this editor has
## EVER placed directly, with no list indirection to fall out of sync with — closing Creep Edit is now a hard
## guarantee that nothing it ever placed is still visible, full stop.
func _update_gameplay_visibility() -> void:
	for eo: EditableObjectNode in _placed.values():
		if eo != null and is_instance_valid(eo):
			eo.visible = false

# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _is_open and not _grid_mode and event is InputEventKey \
			and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		# 2026-08-22 ("Phím PgUp tăng giá trị Z, PgDn giảm giá trị Z"): Z is the TP's HEIGHT above the ground
		# plane (`tp["z"]`), which no key could reach before — it was spinbox-only. Arrow keys stay on X/Y
		# (see the `dir` mapping below; Y reads up-positive now, see _tp_xyz_get). Selected TPs only: Z is a
		# TP-specific field, meaningless for FP/tentacle/vortex/LED points, so those keep arrow keys only.
		var dz := 0.0
		if ke.keycode == KEY_PAGEUP:
			dz = 1.0
		elif ke.keycode == KEY_PAGEDOWN:
			dz = -1.0
		# 2026-08-22 ("Khi click mỗi layer đơn, phím pgup và pgdn có thể nâng hạ object"): with a plain OBJECT
		# layer selected (no TP focused), PgUp/PgDn raise/lower it in the LAYER stack — `z_index`, the same
		# value the Transform panel's own Z field edits. TP selection still wins (checked first, below), since
		# for a TP the Z axis means its height above the ground plane instead.
		if dz != 0.0 and _selected_tp_indices.is_empty() and is_instance_valid(_selected_obj):
			# Real 3D vertical offset (editor-space Z), NOT z_index — 2026-08-22, per explicit correction. It
			# is stored under the `z` key, matching a TP's own `z` and the "Trục Z là trục thẳng đứng"
			# convention the whole editor uses now. Under the game's
			# top-down orthographic camera a pure Y lift doesn't move the part on screen, but it does change
			# DEPTH, i.e. which part occludes which (head above body, etc.); in the editor's 35°-pitch preview
			# it is directly visible as the part rising/sinking. Whole-group selection lifts every member so
			# the assembled weapon moves as one, matching how the rotation sliders behave in group mode.
			# NOT a ternary — `[_active_creep]` builds an UNTYPED Array and assigning that to an
			# `Array[String]` throws at runtime (the same trap `_rebuild_chain_preview()` hit earlier).
			var names: Array[String] = []
			if _group_selected:
				names = _group_member_names(_active_creep)
			else:
				names.append(_active_creep)
			var touched := false
			for cname: String in names:
				var mrig: Dictionary = _rig_for_creep(cname)
				if mrig.is_empty():
					continue
				mrig["z"] = _rig_z(mrig) + dz
				mrig.erase("height")   # migrated key — don't leave a stale twin behind for _rig_z to prefer
				_glb_apply_rotation(mrig)   # also re-applies the vertical offset — see its own body
				touched = true
			if touched:
				_dirty = true
				_refresh_transform_panel()
				_save_layout(true)
				get_viewport().set_input_as_handled()
				return
		if dz != 0.0 and not _selected_tp_indices.is_empty():
			if ke.shift_pressed:
				dz *= 10.0
			var ztps: Array = _thrust_points.get(_active_creep, [])
			# Pure ALTITUDE, in editor world space — never a move across the play plane. Same reason as the
			# arrow keys above: adding to the stored `z` directly meant the part's mount rotation decided what
			# that did, and on VIPER Tail / VIPER body it slid the plume sideways across the plane instead.
			var lift_delta := Vector3(0.0, 0.0, dz)
			for sel_idx: int in _selected_tp_indices:
				if sel_idx >= 0 and sel_idx < ztps.size():
					_tp_xyz_set(_active_creep, ztps[sel_idx],
						_tp_xyz_get(_active_creep, ztps[sel_idx]) + lift_delta)
			_thrust_points[_active_creep] = ztps
			_dirty = true
			_refresh_tp_list()
			_refresh_transform_panel()   # keeps the TP POS X/Y/Z spinboxes in step with the new Z
			_update_grid_overlay()       # -> _refresh_plume_preview -> _refresh_plume3d_preview (rebuilds at new height)
			_save_layout(true)
			get_viewport().set_input_as_handled()
			return
		var dir := Vector2.ZERO
		match ke.keycode:
			KEY_UP:    dir = Vector2( 0.0, -1.0)   # screen-up = +Y (see _tp_xyz_get's up-positive note)
			KEY_DOWN:  dir = Vector2( 0.0,  1.0)   # screen-down = -Y
			KEY_LEFT:  dir = Vector2(-1.0,  0.0)   # -X
			KEY_RIGHT: dir = Vector2( 1.0,  0.0)   # +X
		if dir != Vector2.ZERO:
			if ke.shift_pressed:
				dir *= 10.0
			var fps: Array = _fire_points.get(_active_creep, [])
			var tps: Array = _thrust_points.get(_active_creep, [])
			var tns: Array = _tentacle_points.get(_active_creep, [])
			var vxs: Array = _vortex_points.get(_active_creep, [])
			var leds: Array = _led_points.get(_active_creep, [])
			if _selected_fp_idx >= 0 and _selected_fp_idx < fps.size():
				fps[_selected_fp_idx]["pos"] = (fps[_selected_fp_idx]["pos"] as Vector2) + dir
				_fire_points[_active_creep] = fps
				_dirty = true
				_refresh_fp_list()
				_update_grid_overlay()
				get_viewport().set_input_as_handled()
				return
			elif not _selected_tp_indices.is_empty():
				# 2026-08-23: the nudge is expressed in the PLAY PLANE (editor X right, Y up) and converted
				# into the part's own frame by _tp_xyz_set — it used to be added straight to the stored,
				# model-local `pos`, which the part's mount rotation then sent somewhere else entirely. On the
				# saved data that made VIPER Tail's arrow keys change ALTITUDE instead of moving the plume.
				# `dir.y` is canvas-down, world Y is up, hence the flip.
				var plane_delta := Vector3(dir.x, -dir.y, 0.0)
				for sel_idx: int in _selected_tp_indices:
					if sel_idx >= 0 and sel_idx < tps.size():
						_tp_xyz_set(_active_creep, tps[sel_idx],
							_tp_xyz_get(_active_creep, tps[sel_idx]) + plane_delta)
				_thrust_points[_active_creep] = tps
				_dirty = true
				_refresh_tp_list()
				_refresh_transform_panel()   # 2026-08-22 — was missing: TP POS X/Y/Z went stale after a nudge
				_update_grid_overlay()
				_save_layout(true)           # 2026-08-22 — match the Z (PgUp/PgDn) path; keeps the live weapon in step
				get_viewport().set_input_as_handled()
				return
			elif _selected_tenp_idx >= 0 and _selected_tenp_idx < tns.size():
				tns[_selected_tenp_idx]["pos"] = (tns[_selected_tenp_idx]["pos"] as Vector2) + dir
				_tentacle_points[_active_creep] = tns
				_dirty = true
				_refresh_tenp_list()
				_update_grid_overlay()
				get_viewport().set_input_as_handled()
				return
			elif not _selected_vortex_indices.is_empty():
				for sel_idx: int in _selected_vortex_indices:
					if sel_idx >= 0 and sel_idx < vxs.size():
						vxs[sel_idx]["pos"] = (vxs[sel_idx]["pos"] as Vector2) + dir
				_vortex_points[_active_creep] = vxs
				_dirty = true
				_refresh_vortex_list()
				_update_grid_overlay()
				get_viewport().set_input_as_handled()
				return
			elif not _selected_led_indices.is_empty():
				for sel_idx: int in _selected_led_indices:
					if sel_idx >= 0 and sel_idx < leds.size():
						leds[sel_idx]["pos"] = (leds[sel_idx]["pos"] as Vector2) + dir
				_led_points[_active_creep] = leds
				_dirty = true
				_refresh_led_list()
				_update_grid_overlay()
				get_viewport().set_input_as_handled()
				return
			elif is_instance_valid(_selected_obj):
				# 2026-08-23 ("các phím mũi tên lại ko di chuyển được các part") — two things had to change
				# here, both fallout from the 3D overlay becoming the only thing on screen for a 3D part.
				#
				# The mouse-drag path has always ended in `_follow_chain_on_move()` (see
				# _on_transform_motion); this one never did, and never needed to, because the part's own flat
				# thumbnail moved with its rect. That thumbnail is hidden now and the 3D overlay draws the
				# part — so without a refresh the rect moved under an unchanged picture and the keys looked
				# dead. The nudge itself stays on the SELECTED part: an earlier version redirected it to the
				# group anchor, which moved head and tail along with the body and is not what selecting one
				# layer means.
				if not ke.echo:
					_push_undo_transform(_selected_obj)
				_selected_obj.position += dir
				_refresh_transform_panel()
				_dirty = true
				_follow_chain_on_move()   # re-derives the chain if there is one, and refreshes the overlay
				get_viewport().set_input_as_handled()
				return

	# Asset panel drag
	if _dragging_asset:
		if event is InputEventMouseMotion:
			var mp: Vector2 = get_viewport().get_mouse_position()
			var vp: Vector2 = get_viewport().get_visible_rect().size
			var np: Vector2 = mp + _drag_asset_off
			np.x = clampf(np.x, 0.0, vp.x - ASSET_PANEL_W)
			np.y = clampf(np.y, 0.0, vp.y - 100.0)
			_asset_panel.position = np
		elif event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			_dragging_asset = false
		return

	# Control panel drag
	if _dragging_ctrl:
		if event is InputEventMouseMotion:
			var mp: Vector2 = get_viewport().get_mouse_position()
			var vp: Vector2 = get_viewport().get_visible_rect().size
			var np: Vector2 = mp + _drag_ctrl_off
			np.x = clampf(np.x, 0.0, vp.x - CTRL_PANEL_W)
			np.y = clampf(np.y, 0.0, vp.y - 100.0)
			_ctrl_panel.position = np
		elif event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			_dragging_ctrl = false
		return

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		if not ke.echo and ke.keycode == KEY_Z and ke.ctrl_pressed:
			_undo()
			get_viewport().set_input_as_handled()
			return
		if not ke.echo and ke.keycode == KEY_DELETE:
			if _selected_fp_idx >= 0:
				_delete_selected_fp()
			elif _selected_tp_idx >= 0:
				_delete_selected_tp()
			elif _selected_tenp_idx >= 0:
				_delete_selected_tenp()
			elif _selected_vortex_idx >= 0:
				_delete_selected_vortex()
			elif _selected_led_idx >= 0:
				_delete_selected_led()
			elif is_instance_valid(_selected_obj):
				_delete_selected()
			get_viewport().set_input_as_handled()
			return
		if not ke.echo and ke.keycode == KEY_ESCAPE:
			if _adding_firepoint:
				_adding_firepoint = false
				_add_fp_btn.button_pressed = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _adding_thrustpoint:
				_adding_thrustpoint = false
				_add_tp_btn.button_pressed = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _adding_tentaclepoint:
				_adding_tentaclepoint = false
				_add_tenp_btn.button_pressed = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _adding_vortexpoint:
				_adding_vortexpoint = false
				_add_vortex_btn.button_pressed = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _adding_ledpoint:
				_adding_ledpoint = false
				_add_led_btn.button_pressed = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			if _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_creep_interactivity()
				get_viewport().set_input_as_handled()
				return
			_request_close()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var in_panels := _asset_panel.get_global_rect().has_point(mb.position) \
					  or _ctrl_panel.get_global_rect().has_point(mb.position)
		# ── Scroll zoom ──
		if mb.pressed and not in_panels and \
				(mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := ZOOM_RATIO if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_RATIO)
			_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom(mb.position)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not in_panels:
			if _adding_firepoint:
				_add_firepoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
			if _adding_thrustpoint:
				_add_thrustpoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
			if _adding_tentaclepoint:
				_add_tentaclepoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
			if _adding_vortexpoint:
				_add_vortexpoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
			if _adding_ledpoint:
				_add_ledpoint_at(mb.position)
				get_viewport().set_input_as_handled()
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not in_panels:
			if _adding_firepoint:
				_adding_firepoint = false
				_add_fp_btn.button_pressed = false
				_update_all_creep_interactivity()
			elif _adding_thrustpoint:
				_adding_thrustpoint = false
				_add_tp_btn.button_pressed = false
				_update_all_creep_interactivity()
			elif _adding_tentaclepoint:
				_adding_tentaclepoint = false
				_add_tenp_btn.button_pressed = false
				_update_all_creep_interactivity()
			elif _adding_vortexpoint:
				_adding_vortexpoint = false
				_add_vortex_btn.button_pressed = false
				_update_all_creep_interactivity()
			elif _adding_ledpoint:
				_adding_ledpoint = false
				_add_led_btn.button_pressed = false
				_update_all_creep_interactivity()
			elif _grid_mode:
				_grid_mode = false
				_grid_btn.button_pressed = false
				_grid_overlay.show_grid = false
				_update_all_creep_interactivity()
			else:
				_select_obj(null)
				_select_fp(-1)
				_select_tp(-1)
				_select_tenp(-1)
				_select_vortex(-1)
				_select_led(-1)
			get_viewport().set_input_as_handled()

func _on_asset_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging_asset = true
			_drag_asset_off = _asset_panel.global_position - get_viewport().get_mouse_position()

func _on_ctrl_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging_ctrl = true
			_drag_ctrl_off = _ctrl_panel.global_position - get_viewport().get_mouse_position()

# ── Delete ─────────────────────────────────────────────────────────────────────

func _delete_selected() -> void:
	if not is_instance_valid(_selected_obj):
		return
	var creep_name := _active_creep
	_push_undo_delete(_selected_obj, creep_name)
	_placed.erase(creep_name)
	_selected_obj.queue_free()
	_select_obj(null)
	_refresh_layer_list()
	_dirty = true

# ── Undo ───────────────────────────────────────────────────────────────────────

func _push_undo_transform(obj: EditableObjectNode) -> void:
	_undo_stack.append({"type": "transform", "obj": obj,
		"pos": obj.position, "size": obj.size})

func _push_undo_delete(obj: EditableObjectNode, creep_name: String) -> void:
	_undo_stack.append({
		"type":  "delete",
		"tex":   obj.texture_rect.texture if obj.texture_rect != null else null,
		"path":  obj.source_path,
		"creep": creep_name,
		"pos":   obj.position,
		"size":  obj.size,
	})

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	match entry["type"]:
		"transform":
			var obj = entry["obj"]
			if is_instance_valid(obj):
				obj.position = entry["pos"]
				obj.size     = entry["size"]
				obj._sync_rect_size()
				_refresh_transform_panel()
		"delete":
			var tex: Texture2D = entry["tex"]
			if tex == null:
				return
			_place_creep_eo(entry["creep"], tex, entry["path"], entry["pos"], entry["size"])
			_refresh_layer_list()
	_dirty = not _undo_stack.is_empty()

# ── Persistence ────────────────────────────────────────────────────────────────

## `silent` (2026-08-21): skips the "Saved ..." toast — used by the live-preview auto-save triggered from
## every Rotate X/Y/Z drag tick (_on_glb_rotation_changed), which would otherwise spam a toast per mouse-move
## event. The explicit Save button still calls this with the default (false) and shows the toast as before.
func _save_layout(silent: bool = false) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_layout_path())
	cfg.set_value("meta", "version", 1)
	# Marks the whole file as holding EDITOR-space (Z-up) angles — see _load_layout's `legacy_axis`.
	cfg.set_value("meta", "axis_space", "z_up")
	for creep_name: String in _all_creep_names:
		var eo: EditableObjectNode = _placed.get(creep_name, null)
		if eo != null and is_instance_valid(eo):
			# "rot" (2026-08-20, "ghi nhớ góc... của object khi xuất hiện trên màn chơi thực tế" — now a full
			# 3-axis Vector3, was Y-only "yaw" in the previous pass) — the object's MOUNT ANGLE calibrated via
			# the "3D VIEW / MOUNT ANGLE" Rotate X/Y/Z sliders (see _load_glb_topdown_tex's rot_pivot), read
			# back from the live rig cache. Vector3.ZERO / omitted for non-glb creeps (nothing to calibrate —
			# a flat 2D sprite has no separate "model forward axis" to align).
			var rot := Vector3.ZERO
			var rot_base := Vector3.ZERO
			var z3 := 0.0
			if eo.source_path.get_extension().to_lower() == "glb":
				var rig: Dictionary = _glb_preview_cache.get(_rig_key(creep_name, eo.source_path), {})
				# EDITOR-space (Z-up) angles — see glb_topdown_rig.gd's axis-space section. Stored as authored
				# so the sliders, the readouts and this file all agree; the conversion to Godot's Y-up space
				# happens only where a Node3D is actually driven.
				rot = rig.get("rot", Vector3.ZERO)
				rot_base = rig.get("rot_base", Vector3.ZERO)   # 2026-08-22 "Set 0° here" baseline
				z3 = _rig_z(rig)                               # 2026-08-22 PgUp/PgDn vertical offset
			cfg.set_value("creeps", creep_name, {
				"path":    eo.source_path,
				"pos":     eo.position,
				"size":    eo.size,
				"z_index": eo.z_index,
				"parent":  _creep_parents.get(creep_name, ""),
				"blend":   eo.blend_id,
				"rot":     rot,
				"rot_base": rot_base,
				"z":       z3,
				"hidden":  bool(_layer_hidden.get(creep_name, false)),   # eye toggle, see _layer_hidden
			})
		# Fire points
		var fp_data: Array[Dictionary] = []
		for fp: Dictionary in _fire_points.get(creep_name, []):
			fp_data.append({"pos": fp["pos"], "id": fp.get("id", 0), "dir_angle": fp.get("dir_angle", 0.0)})
		cfg.set_value("firepoints", creep_name, fp_data)
		# Thrust points
		var tp_data: Array[Dictionary] = []
		for tp: Dictionary in _thrust_points.get(creep_name, []):
			# "z" (2026-08-20) and "dir_rot" (2026-08-21, spray-direction calibration — see
			# glb_topdown_rig.gd's tp_direction()) — this dict rebuild used to whitelist only pos/id/
			# dir_angle, silently dropping every field added after it on save (worked live in-session,
			# reset to default on reload). Every consumer already reads these via `.get(key, default)`, so
			# old saves missing them still load fine — this only fixes NEW writes going forward.
			var tp_out := {"pos": tp["pos"], "id": tp.get("id", 0), "dir_angle": tp.get("dir_angle", 0.0),
				"z": tp.get("z", 0.0)}
			if tp.has("dir_rot"):
				tp_out["dir_rot"] = tp["dir_rot"]
			tp_data.append(tp_out)
		cfg.set_value("thrustpoints", creep_name, tp_data)
		# Tentacle points
		var tn_data: Array[Dictionary] = []
		for tn: Dictionary in _tentacle_points.get(creep_name, []):
			tn_data.append({"pos": tn["pos"], "id": tn.get("id", 0), "dir_angle": tn.get("dir_angle", 0.0)})
		cfg.set_value("tentaclepoints", creep_name, tn_data)
		# Vortex points (directionless)
		var vx_data: Array[Dictionary] = []
		for vx: Dictionary in _vortex_points.get(creep_name, []):
			vx_data.append({"pos": vx["pos"], "id": vx.get("id", 0)})
		cfg.set_value("vortexpoints", creep_name, vx_data)
		# Led points (directionless, 2026-08-15)
		var led_data: Array[Dictionary] = []
		for led: Dictionary in _led_points.get(creep_name, []):
			led_data.append({"pos": led["pos"], "id": led.get("id", 0)})
		cfg.set_value("ledpoints", creep_name, led_data)
	cfg.save(_layout_path())
	_save_plume_styles()
	_save_vortex_styles()
	_save_led_styles()
	ArenaEnemyScript.reload_layout_cfgs()   # drop the spawn-time cache so live creep/plume edits apply next spawn
	_reload_live_weapon_3d()
	_dirty = false
	if not silent:
		show_toast("Saved " + _layout_path().get_file())

## 2026-08-21 ("TÔI CẦN XOAY ĐƯỢC PLUME 3D" — dragging Rotate X/Y/Z only ever updated the on-canvas arrow +
## the in-editor .glb preview; the REAL gameplay plume (mount-angle calibration + every TP's baked spray
## direction) is read from weapon_layout.cfg exactly ONCE by arena_weapons.gd, at that weapon's own
## `_setup_*_3d()` — equip/boot time only, never again). First pass only reloaded from `_save_layout()`
## (button press), which still left a "drag slider → nothing visibly happens → remember to click Save → NOW
## it updates" gap — confusing since the on-canvas arrow already reacts instantly. `reload_3d_weapon_layout()`
## reads weapon_layout.cfg FROM DISK, so a reload alone isn't enough mid-drag — the file has to actually be
## up to date first. `_on_glb_rotation_changed()` now calls `_save_layout(true)` (silent — a full write of
## every weapon's data, same as the Save button, just without the toast) on EVERY rotation-slider tick, so
## the real in-game plume tracks the sliders live now, same as the arrow always did — the explicit Save
## button remains for the toast/confirmation, not because it does anything extra. Accepted tradeoff: this
## writes the whole cfg to disk on every mouse-move during a drag (dozens of times/sec) — fine for a small
## dev-tool config file, flag if it ever visibly stutters.
func _reload_live_weapon_3d() -> void:
	if _layout_path() != "res://weapon_layout.cfg":
		return
	# 2026-08-21 BUG FIX ("VẪN CHỈ CÓ VECTOR INDICATOR XOAY. ACTUAL PLUME KHÔNG HỀ XOAY" — every fix up to
	# this point was individually correct and verified, yet nothing ever visibly changed in the real game):
	# wrong GROUP NAME. `arena_weapons.gd` (VIPER/Jaeger/Aliwa live here) joins group `"arena_weapons"` (see
	# its own `_ready()`), NOT `"weapon_system"` — that name belongs to a COMPLETELY DIFFERENT file/system,
	# `scripts/gameplay/weapon_system.gd` (the SpaceScreen/asteroid equipped-item engine — see CLAUDE.md's own
	# "weapon_system.gd vs gun_system.gd" section, which is where this wrong name was copied from). Looking up
	# `"weapon_system"` here returned either null or an unrelated node, so `ws.has_method(...)` below silently
	# failed EVERY time — `reload_3d_weapon_layout()` was never actually being called, despite the whole
	# reload/rebuild/local_coords mechanism being independently verified correct (numeric proof: rotating a
	# TP's saved `dir_rot` and calling `reload_3d_weapon_layout()` directly on a real `arena_weapons.gd`
	# instance measurably changes `anchor.global_transform.basis * particle.direction`, the actual world-space
	# spray vector). Fixed the group name; this is the root cause tying every prior 2026-08-21 fix together.
	var ws: Node = get_tree().get_first_node_in_group("arena_weapons")
	if ws != null and ws.has_method("reload_3d_weapon_layout"):
		ws.reload_3d_weapon_layout()

func _load_layout() -> void:
	if _objects_container == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(_layout_path()) != OK:
		return
	# 2026-08-22 (axis-space pass): stored `rot`/`rot_base` are EDITOR-space (Z-up, ZXY order) angles now.
	# A file written before this pass holds Godot-space (Y-up, YXZ) angles instead, and handing one of those
	# to `view_basis()` would silently re-interpret every tilt onto the wrong axis — the parts would still
	# render, just wrong, which is the failure mode that is hardest to notice. `[meta] axis_space` marks the
	# file; anything without it is converted on load (`editor_rot(Basis.from_euler(old))`, i.e. the same
	# conjugation, backwards) and re-saved in the new space by the next `_save_layout()`. Cheap, runs once,
	# and makes restoring an old backup safe instead of quietly destructive.
	var legacy_axis := String(cfg.get_value("meta", "axis_space", "y_up")) != "z_up"
	for creep_name: String in _all_creep_names:
		# EO
		if not _placed.has(creep_name) or not is_instance_valid(_placed.get(creep_name, null)):
			var entry: Dictionary = cfg.get_value("creeps", creep_name, {})
			if not entry.is_empty():
				var path: String = _asset_path_for(creep_name)
				if path.is_empty():
					path = _resolve_asset_path(entry.get("path", ""))
				var tex := _load_full_tex(path, creep_name)
				var saved_size: Vector2 = entry.get("size", Vector2(60.0, 60.0))
				# Self-heal aspect (2026-08-20, VIPER 3D swap): a creep placed/saved BEFORE its .glb existed
				# has `saved_size` sized to match the OLD flat PNG's own aspect — _resolve_asset_path just
				# swapped the texture to a NEW (square, see _load_glb_topdown_tex) render, so keeping the old
				# non-square size would stretch/squish it. Re-derive height from the NEW texture's own aspect,
				# keeping the saved WIDTH (preserves whatever scale the user already placed it at).
				if path.get_extension().to_lower() == "glb" and tex != null:
					var tw := float(tex.get_width())
					var th := float(tex.get_height())
					if tw > 0.0:
						saved_size = Vector2(saved_size.x, saved_size.x * th / tw)
				if tex != null:
					var eo := _place_creep_eo(creep_name, tex, path,
						entry.get("pos", Vector2(480.0, 380.0)),
						saved_size)
					if eo != null:
						eo.z_index = entry.get("z_index", 115)
						eo.set_blend_mode(int(entry.get("blend", 0)))
					if bool(entry.get("hidden", false)):
						_layer_hidden[creep_name] = true
					# Apply the saved mount-angle calibration (2026-08-20 — see _save_layout's "rot" comment)
					# to the just-built rig, so a glb creep restores its calibrated orientation on load
					# instead of resetting to 0 every session.
					if path.get_extension().to_lower() == "glb":
						var rig: Dictionary = _glb_preview_cache.get(_rig_key(creep_name, path), {})
						if not rig.is_empty():
							rig["rot"] = _migrate_axis(entry.get("rot", Vector3.ZERO), legacy_axis)
							rig["rot_base"] = _migrate_axis(entry.get("rot_base", Vector3.ZERO), legacy_axis)
							rig["z"] = float(entry.get("z", entry.get("height", 0.0)))
							rig.erase("height")
							_glb_apply_rotation(rig)
				var par: String = entry.get("parent", "")
				if not par.is_empty():
					# 2026-08-22: a force-arranged chain (see `_chain_force_arrange`) owns its own parenting —
					# ignore a stale saved parent for its members. `_auto_group_chain_names()` runs BEFORE this
					# function, so without the guard a pre-chain layout re-breaks the group on every single
					# load (VIPER's tail was saved with `parent = "VIPER body"` and kept dropping out of the
					# head's group, rendering a row with no tail).
					var auto_root: String = _creep_parents.get(creep_name, "")
					if auto_root.is_empty() or not _chain_force_arrange(auto_root):
						_creep_parents[creep_name] = par
		# Fire points
		_fire_points[creep_name] = []
		var max_fp_id := 0
		for fp: Dictionary in cfg.get_value("firepoints", creep_name, []):
			var fp_id: int = fp.get("id", max_fp_id + 1)
			_fire_points[creep_name].append({"pos": fp.get("pos", Vector2.ZERO), "id": fp_id, "dir_angle": fp.get("dir_angle", 0.0)})
			max_fp_id = maxi(max_fp_id, fp_id)
		_fp_id_counter[creep_name] = max_fp_id + 1
		# Thrust points
		_thrust_points[creep_name] = []
		var max_tp_id := 0
		for tp: Dictionary in cfg.get_value("thrustpoints", creep_name, []):
			var tp_id: int = tp.get("id", max_tp_id + 1)
			var tp_in := {"pos": tp.get("pos", Vector2.ZERO), "id": tp_id,
				"dir_angle": tp.get("dir_angle", 0.0), "z": tp.get("z", 0.0)}
			if tp.has("dir_rot"):
				tp_in["dir_rot"] = _migrate_axis(tp["dir_rot"], legacy_axis)
			if tp.has("dir_rot_base"):
				# 2026-08-22 "Set 0° here" baseline; migrated on the same flag as the object angles.
				tp_in["dir_rot_base"] = _migrate_axis(tp["dir_rot_base"], legacy_axis)
			_thrust_points[creep_name].append(tp_in)
			max_tp_id = maxi(max_tp_id, tp_id)
		_tp_id_counter[creep_name] = max_tp_id + 1
		# Tentacle points
		_tentacle_points[creep_name] = []
		var max_tn_id := 0
		for tn: Dictionary in cfg.get_value("tentaclepoints", creep_name, []):
			var tn_id: int = tn.get("id", max_tn_id + 1)
			_tentacle_points[creep_name].append({"pos": tn.get("pos", Vector2.ZERO), "id": tn_id, "dir_angle": tn.get("dir_angle", 0.0)})
			max_tn_id = maxi(max_tn_id, tn_id)
		_tenp_id_counter[creep_name] = max_tn_id + 1
		# Vortex points
		_vortex_points[creep_name] = []
		var max_vx_id := 0
		for vx: Dictionary in cfg.get_value("vortexpoints", creep_name, []):
			var vx_id: int = vx.get("id", max_vx_id + 1)
			_vortex_points[creep_name].append({"pos": vx.get("pos", Vector2.ZERO), "id": vx_id})
			max_vx_id = maxi(max_vx_id, vx_id)
		_vortex_id_counter[creep_name] = max_vx_id + 1
		# Led points (2026-08-15)
		_led_points[creep_name] = []
		var max_led_id := 0
		for led: Dictionary in cfg.get_value("ledpoints", creep_name, []):
			var led_id: int = led.get("id", max_led_id + 1)
			_led_points[creep_name].append({"pos": led.get("pos", Vector2.ZERO), "id": led_id})
			max_led_id = maxi(max_led_id, led_id)
		_led_id_counter[creep_name] = max_led_id + 1

# ── Asset loading ──────────────────────────────────────────────────────────────

## Map an assets/enemies/ path to its assets/enemiesHD/ twin when that file exists (dev:on editor preview).
func _hd_path(path: String) -> String:
	const HD_FOLDER := "res://assets/enemiesHD/"
	if path.begins_with(ENEMIES_FOLDER):
		var hd := HD_FOLDER + path.substr(ENEMIES_FOLDER.length())
		if FileAccess.file_exists(hd) or ResourceLoader.exists(hd):
			return hd
	return path

func _load_full_tex(path: String, creep_name: String = "") -> Texture2D:
	# Prefer the HD sprite; fall back to the standard one if HD is missing or fails to load.
	var src := _hd_path(path)
	var tex := _load_tex_raw(src, creep_name)
	if tex == null and src != path:
		tex = _load_tex_raw(path, creep_name)
	return tex

## Given a saved asset path (from a "creeps" entry in creep_layout.cfg / weapon_layout.cfg), swaps it for a
## sibling `.glb` with the same basename if one now exists — 2026-08-20, VIPER 3D swap bug fix: creeps placed
## BEFORE their .glb existed have their PNG path baked into the save file; without this, _load_layout() kept
## restoring the stale PNG forever regardless of _load_or_create_creep's own "glb first" preference below
## (that only applies to placing a BRAND NEW creep, never to restoring an already-saved one). Read-only —
## doesn't touch the save file; the next _save_layout()-equivalent naturally persists the resolved path via
## eo.source_path, so this is self-healing after one re-save.
func _resolve_asset_path(path: String) -> String:
	if path.is_empty() or path.get_extension().to_lower() == "glb":
		return path
	var glb_path := path.get_basename() + ".glb"
	if FileAccess.file_exists(glb_path) or ResourceLoader.exists(glb_path):
		return glb_path
	return path

## Cache for _load_glb_topdown_tex — path -> a Dictionary rig: {vp, cam, model, rot_pivot, headlamp, tp_root,
## target_px, rot: Vector3, dist, tex}. Keeps re-selecting the same creep in the editor from rebuilding its
## SubViewport every time, and is what _glb_apply_rotation / _glb_refresh_tp_gizmos reach into when the
## Rotate X/Y/Z sliders move or the active creep's TPs change.
var _glb_preview_cache: Dictionary = {}
const GLB_PREVIEW_PX := 256   # editor-preview render resolution CAP (longer edge) — modest, placement aid only
const GLB_FRAME_MARGIN := 1.06  # breathing room so the silhouette never touches the frame edge

## Weapons with REAL 3D runtime wiring in arena_weapons.gd — VIPER's 3 parts + Yari-Jeager, the only ones with
## their own _load_snake_plume_3d/_load_jaeger_plume_3d that actually READ "dir_rot"/"z". 2026-08-21 bug fix
## ("Có các TP 3D đã có sẵn trong từng weapon. Đó chính là bug"): this editor used to decide "is this creep
## 3D" purely from the resolved asset's FILE EXTENSION (any `.glb`) — but the user has since added `.glb`
## preview models for OTHER weapons too (ND-Aliwa-Bmr, BC-SL-Spore, ...) whose actual GAMEPLAY sprite/plume
## is still the untouched OLD 2D path (`BOOM_TEX`/`PARA_SPRITE` preload a `.png`; their plume still goes
## through `_register_plume`/`_make_orbital_plume`/`_load_para_plume_data`, none of which know "dir_rot" or
## "z" exist). Those weapons were getting the FULL 3D editing UI (Rotate X/Y/Z sliders, TP POS X/Y/Z panel)
## even though editing those fields has ZERO effect in the actual game — a convincing-looking but non-
## functional control, worse than no control at all. `_refresh_glb_view_ui` (the single choke point every
## other 3D-UI toggle in this file reads via `_active_glb_path`) now gates on THIS allowlist too, not just
## the file extension. The `.glb` PREVIEW TEXTURE itself (`_load_glb_topdown_tex`) stays available for every
## glb creep regardless — showing the nicer model is harmless; it's specifically the ROTATE/XYZ EDITING
## surface that's gated, since that's the part that silently promises something the game doesn't deliver.
## Add a name here ONLY once that weapon's own 3D runtime plume is actually wired up in arena_weapons.gd.
const WIRED_3D_CREEPS := ["VIPER head top", "VIPER body", "VIPER Tail", "Yari-Jeager", "ND-Aliwa-Bmr",
	"Swarmball", "Swarmbot", "shooter", "BC-SL-Spore", "Ship_model_1",
	# Yari Jeager's animation glbs (2026-08-23) — each clip carries its OWN mount angle, applied by
	# `_draw_yari()` while that clip is the one playing. See weapon_edit_mode.gd's JAEGER_CLIPS.
	"Fly", "Walk", "Run", "Dive", "Kick", "Low Kick", "Slash", "Fly punch",
	# The Metalfly boss's two bodies (2026-08-24). They meet this list's bar — arena_enemy.gd's
	# `_creep_mount_rot()` reads their saved `rot` on every spawn and hands it to metalfly_rig.gd /
	# glb_spin_body.gd, so the sliders move the real boss, not just the preview. Named via the runtime's own
	# constants rather than retyped, same as the MF_* block at the top of this file.
	ArenaEnemyScript.MF_LAYER_WINGS, ArenaEnemyScript.MF_LAYER_COCOON,
	# "stand" is Jeager's MASTER layer (2026-08-23) — the one plumes are authored on, so it needs the same
	# Rotate X/Y/Z + TP XYZ surface every other layer has. Its own mount angle is an authoring convenience
	# (turn the reference model to a workable angle); the runtime takes the object's orientation from the
	# PLAYING clip's layer, falling back to "Yari-Jeager" — see _jaeger_clip_pose().
	"stand"]
# 2026-08-21: "ND-Aliwa-Bmr" added once its own 3D runtime plume actually landed (_setup_aliwa_3d/
# _load_aliwa_plume_3d in arena_weapons.gd).
# 2026-08-23: "Swarmball"/"Swarmbot"/"shooter"/"BC-SL-Spore" added on the same terms — arena_weapons.gd's
# GLB3D_WEAPONS rig renders all four as live .glb models that read this mount angle, its Z lift and its TPs,
# so the panel drives something real. (Spore already HAD a MultiMesh rig; it was held off this list because
# that rig lacked the Z lift, the `display_px_for` entry and the 3D TP plumes — folding it into
# GLB3D_WEAPONS supplied all three.) "missile" was asked for in the same breath but has NO missile.glb in
# assets/weaponry — nothing to render in 3D — so it deliberately stays 2D and off this list.
# 2026-08-23: "Ship_model_1" is the PLAYER SHIP ("Đặt player ship vào bảng weapon edit như 1 loại vũ khí để
# tôi có thể gắn plume"). Its TPs become real 3D exhaust plumes on the ship's own SubViewport — see
# arena.gd::_load_ship_plumes(). One caveat worth knowing while authoring it: the ship's hull orientation is
# driven by AIM (`_update_ship_3d`), not by this cfg, so the Rotate X/Y/Z sliders turn the ship's PLUME RIG
# (every TP together), not the hull. That is still a real, useful control — it tilts the whole exhaust set —
# but it is not the same thing the sliders do for a weapon.
const GLB_DEFAULT_PITCH_DEG := 35.0   # DEFAULT camera elevation — a 3/4 "product shot"; the VIEW CUBE gizmo
									  # (2026-08-22) orbits away from it and right-click resets back to it.

## Live 3D render of a `.glb`, cached per-path — gives creep_edit_mode a real `.glb` asset type alongside its
## existing `.png`/`.gif` ones. Returns a `ViewportTexture` (IS-A `Texture2D`), so every existing consumer of
## _load_tex_raw()'s return value — EditableObjectNode display, layer thumbnails, thrust-point placement —
## keeps working completely unchanged: none of them care whether the source is a flat image or a live 3D
## render, and TPs are still stored as a FRACTION of the placed EO's own pos/size (see _load_snake_plume() in
## arena_weapons.gd), never against the texture's native pixel dimensions.
##
## 2026-08-20 (3rd pass — "TP là child của object, xoay thì plume xoay theo", "3 thanh slider XYZ",
## "clamp bởi sprite 2D"): three changes from the 2nd pass (Yaw/Pitch orbit):
##  1. Camera is now FIXED (GLB_DEFAULT_PITCH_DEG, never orbits) — the OBJECT rotates on all 3 axes instead,
##     via `rot_pivot` (renamed from `yaw_pivot`). `rot_pivot.rotation` is a full Vector3, driven by 3
##     Rotate X/Y/Z sliders (see _build_ui's "3D VIEW" section) — ALL THREE are the object's saved mount-
##     angle calibration now (was Y-only), read by arena_weapons.gd's live gameplay rig (see _read_creep_rot
##     there) to orient the model. Both the model AND `tp_root` (TP/plume preview) are real children of
##     `rot_pivot`, so one `rotation` write moves both — genuine scene-graph attachment, not two
##     independently-computed transforms that could drift apart.
##  2. Aspect auto-fit ("clamp bởi sprite 2D" bug): the previous pass forced every glb creep into a fixed
##     SQUARE render, which fed straight into `eo._aspect_ratio` (editable_object.gd reads it from the
##     texture's own w/h) and locked every 3D creep's W/H size spinboxes together at the wrong ratio — a
##     resize rule that makes sense for a flat PNG (never distort those) but is simply wrong for a 3D model,
##     whose true silhouette shape depends on the model itself. Now uses glb_topdown_rig.gd's
##     `silhouette_extent()` to size BOTH the SubViewport's pixel dimensions AND the camera's ortho `size` to
##     the model's ACTUAL projected width/height at the fixed camera angle — so the texture's own aspect (and
##     therefore `eo._aspect_ratio`) reflects the real model, and the W/H aspect-lock becomes correct instead
##     of wrong, rather than needing to be disabled.
##  3. TP preview markers (_glb_refresh_tp_gizmos) are the REAL plume particle effect now, not a placeholder —
##     see that function's own header (unchanged from the 2nd pass, still correct here).
func _load_glb_topdown_tex(path: String, creep_name: String = "") -> Texture2D:
	var key := _rig_key(creep_name, path)
	if _glb_preview_cache.has(key):
		return (_glb_preview_cache[key] as Dictionary)["tex"] as Texture2D
	var rig := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS   # only ever a handful of these live at once
	add_child(vp)
	rig.build_lighting(vp)

	var rot_pivot := Node3D.new()
	vp.add_child(rot_pivot)

	var model: Node3D = rig.load_model(path)
	if model == null:
		vp.queue_free()
		return null
	rot_pivot.add_child(model)
	_play_preview_animation(model, _preview_clip(creep_name))
	# 2026-08-22: taken from whatever system RENDERS this asset in the real game, via `_arena_display_px()`
	# (weapon_edit_mode.gd -> arena_weapons.display_px_for). This used to be a hardcoded 44 / 25.2 / 32 /
	# 25.35 table right here, kept in sync with arena_weapons.gd by comment only — and it had already drifted
	# once: Aliwa fell through to the generic 32.0 while the game drew it at 25.35, placing every one of its
	# saved TPs ~26% away from where the game put them. A TP is stored as a FRACTION of this number and read
	# back the same way on both sides, so any disagreement here is a silent misplacement, never an error.
	var target_px := _arena_display_px(path.get_file().get_basename())
	if target_px <= 0.001:
		target_px = 32.0   # generic fallback for a glb with no in-game renderer of its own yet
	rig.center_and_fit(model, target_px)

	var cam := Camera3D.new()
	vp.add_child(cam)   # camera is NOT under rot_pivot — it's the fixed viewer, not part of the object
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	var dist := target_px * 3.0
	cam.far = dist * 2.0
	# 2026-08-22: starts at whatever the VIEW CUBE is currently showing (default = GLB_DEFAULT_PITCH_DEG's
	# 3/4 view), so a preview built after the view was orbited matches the ones already on screen. The tight
	# fit happens in _fit_preview_cam() below, once the rig dict exists.
	cam.look_at_from_position(_view_dir() * dist, Vector3.ZERO, _view_up())

	# 2026-08-22 ("Bỏ frame crop object đi — khi tôi xoay aliwa, tôi thấy nó bị 1 khung chữ nhật crop"):
	# framing used to be fitted to the model's silhouette AS SEEN AT ROTATION ZERO (`silhouette_extent()`),
	# which is only correct for that one orientation — rotate the object and its now-wider silhouette runs
	# straight past the frame edge, visibly clipping it into a rectangle. Fixed by framing to the model's
	# BOUNDING SPHERE instead (half the AABB diagonal), the one extent that is INVARIANT under every possible
	# rotation: nothing can ever leave the frame, at any Rotate X/Y/Z value, so the crop is gone by
	# construction rather than by picking a bigger fudge margin. Necessarily square (a sphere has no aspect),
	# which also supersedes the earlier `ext.max(target_px, target_px)` floor — the sphere already covers the
	# full `±target_px/2` TP-placement range on every axis. Trade-off, deliberate: the model renders slightly
	# smaller inside its EO rect than a tight fit would (transparent padding around it) and `eo._aspect_ratio`
	# becomes 1.0 — but the model itself is still rendered at its own true proportions inside that square, so
	# nothing is stretched or distorted; only the padding changes.
	vp.size = Vector2i(GLB_PREVIEW_PX, GLB_PREVIEW_PX)   # square; cam.size is fitted per view in _fit_preview_cam()

	var headlamp := DirectionalLight3D.new()
	headlamp.light_energy = 1.6
	headlamp.rotation = cam.rotation
	vp.add_child(headlamp)

	var tp_root := Node3D.new()
	rot_pivot.add_child(tp_root)   # child of rot_pivot too — rotates WITH the model, see header above

	var rig_data: Dictionary = {
		"vp": vp, "cam": cam, "model": model, "rot_pivot": rot_pivot, "headlamp": headlamp, "tp_root": tp_root,
		"target_px": target_px, "rot": Vector3.ZERO, "dist": dist, "tex": vp.get_texture(),
	}
	_fit_preview_cam(rig_data)   # tight frame for the current view angle — see that function
	_glb_apply_rotation(rig_data)
	_glb_preview_cache[key] = rig_data
	return rig_data["tex"] as Texture2D

## Plays a preview model's own animation, if its glb shipped one (2026-08-23, added for Jeager's clip
## layers). Judging "is this clip facing the right way" from a bind pose is guesswork — a flight clip's whole
## point is the pose it holds mid-air — so the preview animates and the Rotate X/Y/Z sliders are dialled
## against what the arena will actually show.
##
## `PROCESS_MODE_ALWAYS` because the editor holds the tree paused; without it every preview freezes on frame
## zero. The glTF importer's own combined track is named "Armature|<something>|baselayer" — prefer a plainly
## named clip when the file has one, since that is the real animation and the baselayer is usually a
## concatenation of everything.
func _play_preview_animation(model: Node3D, clip: String = "") -> void:
	var ap := _find_preview_anim_player(model)
	if ap == null:
		return
	var list := ap.get_animation_list()
	if list.is_empty():
		return
	# An explicit clip (a layer of a shared, merged glb) is used as given.
	var pick := ""
	if not clip.is_empty():
		if not ap.has_animation(clip):
			return
		pick = clip
	else:
		# No clip asked for. Guessing is only safe when the file HAS one obvious animation: the merged Jeager
		# glb holds eight, and picking "the first named one" gave the master layer `stand` — which is meant to
		# sit in its rest pose — whichever sorted first, i.e. Dive. With several to choose from, play nothing.
		var named: Array[String] = []
		for n: String in list:
			if not n.contains("|"):
				named.append(n)
		if named.size() == 1:
			pick = named[0]
		elif named.is_empty() and list.size() == 1:
			pick = String(list[0])
		else:
			return
	var anim := ap.get_animation(pick)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.process_mode = Node.PROCESS_MODE_ALWAYS
	ap.play(pick)

func _find_preview_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c: Node in node.get_children():
		var r := _find_preview_anim_player(c)
		if r != null:
			return r
	return null

## Applies `rig`'s current 3-axis rotation (the object's saved mount-angle calibration, via `rot_pivot` — see
## _load_glb_topdown_tex header) — called on slider change (_on_glb_rotation_changed) and once at build time.
## The camera/headlamp are never touched here anymore — they're fixed at build time (see _load_glb_topdown_tex).
func _glb_apply_rotation(rig: Dictionary) -> void:
	var rot_pivot: Node3D = rig.get("rot_pivot")
	if rot_pivot != null:
		# base ∘ rot (2026-08-22) — see glb_topdown_rig.gd's compose_rot(): "Set 0° here" banks the current
		# orientation into `rot_base` and zeroes `rot`, so the two must be recombined everywhere it's applied.
		# 2026-08-22 (axis-space pass): the stored angle is EDITOR-space (Z-up); `view_rotation()` carries it
		# into Godot's own Y-up space before it reaches a Node3D. Assigning the stored value directly would
		# put every tilt on the wrong axis.
		var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
		rot_pivot.rotation = rr.view_rotation(
			rr.compose_rot(rig.get("rot_base", Vector3.ZERO), rig.get("rot", Vector3.ZERO)))
		# 2026-08-22 ("pgup/pgdn tăng giảm chiều cao THỰC của object 3D"): the editor-space Z lift, applied to the same
		# pivot the model and its TPs hang off so the whole part rises/sinks together. See the PgUp/PgDn
		# branch in _input().
		# 2026-08-22: the Z lift is deliberately NOT applied here. A part's thumbnail is a fixed-size sprite in
		# the 2D layout; letting a PgUp/PgDn lift shift the model inside it forced the frame to be inflated by
		# the lift to avoid cropping, which is what shrank every model to ~4% of its own texture. The height
		# still does everything it should elsewhere — depth ordering in the live weapon
		# (arena_weapons.gd's `_snake3d_world_xform`) and a true 3D offset in the full-screen plume overlay.
	# The frame is fitted to the ROTATED silhouette (see _fit_preview_cam), so it has to be re-fitted every
	# time that rotation changes or the model starts poking out of its own thumbnail again.
	_fit_preview_cam(rig)
	_sync_plume3d_rotations()   # 2026-08-22 — plumes are part of the object, they turn with it (see that func)

## Re-applies both halves of the overlay's rotation — the object's own mount rotation onto `rot_pivot` and
## each TP's own `dir_rot` onto its child pivot. Called whenever either changes: `_glb_apply_rotation()` for
## the object, `_on_glb_rotation_changed()` for a TP. Cheap enough to run wholesale (a handful of TPs).
func _sync_plume3d_rotations() -> void:
	if _preview_plumes3d.is_empty():
		return
	# 2026-08-22 (2nd pass): the overlay is now a real scene graph — `rot_pivot` (the object's own mount
	# rotation) PARENTS every TP pivot (each holding just its own raw `dir_rot`), so Godot composes the two
	# itself, for position AND orientation. No Basis product here any more: writing the composed value into
	# the child would double-apply the object half.
	var rot_pivot: Node3D = _preview_plumes3d.get("rot_pivot")
	if rot_pivot == null or not is_instance_valid(rot_pivot):
		return
	var rig_data: Dictionary = _glb_preview_cache.get(_active_glb_path, {})
	var rr := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	rot_pivot.rotation = rr.view_rotation(
		rr.compose_rot(rig_data.get("rot_base", Vector3.ZERO), rig_data.get("rot", Vector3.ZERO)))
	var pivots: Dictionary = _preview_plumes3d.get("pivots", {})
	for tp: Dictionary in _thrust_points.get(_active_creep, []):
		if not tp.has("dir_rot"):
			continue
		var pivot: Node3D = pivots.get(int(tp.get("id", 1)))
		if pivot != null and is_instance_valid(pivot):
			pivot.rotation = rr.tp_view_rotation(tp)   # (base ∘ dir_rot), editor space -> view space

## Rebuilds `creep_name`'s in-viewport TP markers as the REAL plume particle effect (2026-08-20, "thay chấm
## đỏ bằng TP thật") — not a placeholder dot — using the SAME style data (`_plume_styles`) and
## glb_topdown_rig.gd's `make_plume()` the live gameplay 3D plume uses, so what you see while placing a TP
## is what actually plays in-game. Parented under `tp_root` (a child of `yaw_pivot`), so these rotate
## correctly WITH the model — see _load_glb_topdown_tex header. Position uses the SAME fraction formula
## arena_weapons.gd's 3D plume readers use: `frac = ((tp.pos + SCREEN_ORIGIN) - eo.position) / eo.size`.
## No-op for non-glb creeps. Called from _refresh_tp_list() (the existing single choke point every TP add/
## delete/select/arrow-move already goes through), _refresh_glb_view_ui() (on creep switch), and
## _on_plume_changed()/_reset_plume_style() via _update_grid_overlay → _refresh_plume_preview (style edits).
func _glb_refresh_tp_gizmos(creep_name: String) -> void:
	var eo: EditableObjectNode = _placed.get(creep_name, null)
	if eo == null or not is_instance_valid(eo):
		return
	if eo.source_path.get_extension().to_lower() != "glb":
		return
	var rig: Dictionary = _glb_preview_cache.get(_rig_key(creep_name, eo.source_path), {})
	if rig.is_empty():
		return
	var tp_root: Node3D = rig.get("tp_root")
	if tp_root == null:
		return
	# 2026-08-21 bug fix ("xoay TP1 nhưng TP2 lại xoay"): `queue_free()` is DEFERRED to the end of the current
	# frame, not immediate. Dragging a slider fires `value_changed` many times per frame (every pixel of mouse
	# motion) — each call rebuilds ALL TPs' particles, so with queue_free the OLD (not-yet-actually-removed)
	# particles from the previous call(s) this same frame kept coexisting with the newly-added ones, stacking
	# up duplicate/stale particles for every TP (not just the one being edited). With ≥2 TPs this reads as "a
	# different TP visibly changed" — it's actually a leftover stale copy of it, not really moving. `free()`
	# removes synchronously, so each rebuild starts from a genuinely empty `tp_root` every time.
	for c: Node in tp_root.get_children():
		c.free()
	var target_px: float = rig.get("target_px", 32.0)
	if eo.size.x < 0.01 or eo.size.y < 0.01:
		return
	var rig_obj := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var cmap: Dictionary = _plume_styles.get(creep_name, {})
	for tp: Dictionary in _thrust_points.get(creep_name, []):
		# 2026-08-22 bug fix ("bấm addTP 1 lần thì lại xuất hiện 2 TP... 2 TP đều di chuyển nhưng theo các quỹ
		# đạo khác nhau"): a 3D TP is now drawn by the standalone per-TP preview (`_preview_plumes3d`, see
		# `_refresh_plume3d_preview()`) at its own click point. This function ALSO drew one for every TP,
		# inside the object's own SubViewport at a frac-of-bounding-box position — so ONE saved TP rendered
		# as TWO plumes, tracking two genuinely different transforms: this one is positioned by
		# `local_pos` in the model's own 3D space and rotates with `rot_pivot`, while the standalone one sits
		# at the flat canvas click point with `Basis(object_rot) * Basis(dir_rot)`. Hence "2 TPs on different
		# trajectories". Skip 3D TPs here — the standalone preview is the single owner of their visual now.
		# A glb creep NOT in WIRED_3D_CREEPS (e.g. BC-SL-Spore) never gets `dir_rot` on its TPs, so those
		# still render here exactly as before — this function stays the only preview they have.
		if tp.has("dir_rot"):
			continue
		var tp_oc: Vector2 = (tp["pos"] as Vector2) + SCREEN_ORIGIN
		var frac := (tp_oc - eo.position) / eo.size
		var z: float = tp.get("z", 0.0)
		var local_pos := Vector3((frac.x - 0.5) * target_px, z, (frac.y - 0.5) * target_px)
		var style: Dictionary = cmap.get("tp_%d" % int(tp.get("id", 1)), _default_plume_style())
		var p := rig_obj.make_plume(local_pos, rig_obj.tp_direction(tp), style, target_px)
		tp_root.add_child(p)

func _load_tex_raw(path: String, creep_name: String = "") -> Texture2D:
	var ext := path.get_extension().to_lower()
	if ext == "gif":
		return GifLoader.load_gif(path)
	if ext == "png":
		var json_path := path.get_basename() + ".json"
		if FileAccess.open(json_path, FileAccess.READ) != null:
			var PngSpriteLoader := preload("res://scripts/ui/edit_mode/png_sprite_loader.gd")
			return PngSpriteLoader.load_png_sprite(path)
	if ext == "glb":
		return _load_glb_topdown_tex(path, creep_name)
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		return ImageTexture.create_from_image(img)
	return null

# ── Plume editor helpers (UI construction) ─────────────────────────────────────

func _mk_pspin(parent: HBoxContainer, mn: float, mx: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = step
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 10)
	sb.value_changed.connect(func(_v: float) -> void: _on_plume_changed())
	parent.add_child(sb)
	return sb

func _mk_pcol_vbox(parent: HBoxContainer, lbl_text: String, default_col: Color) -> ColorPickerButton:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vb)
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	var cpb := ColorPickerButton.new()
	cpb.color = default_col
	cpb.custom_minimum_size = Vector2(0.0, 22.0)
	cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpb.color_changed.connect(func(_c: Color) -> void: _on_plume_changed())
	vb.add_child(cpb)
	return cpb

# ── Vortex style UI builders (same look as the plume builders, wired to _on_vortex_changed) ──
func _mk_vxspin(parent: HBoxContainer, mn: float, mx: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = step
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 10)
	sb.value_changed.connect(func(_v: float) -> void: _on_vortex_changed())
	parent.add_child(sb)
	return sb

func _mk_vxcol_vbox(parent: HBoxContainer, lbl_text: String, default_col: Color) -> ColorPickerButton:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vb)
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	var cpb := ColorPickerButton.new()
	cpb.color = default_col
	cpb.custom_minimum_size = Vector2(0.0, 22.0)
	cpb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpb.color_changed.connect(func(_c: Color) -> void: _on_vortex_changed())
	vb.add_child(cpb)
	return cpb

func _mk_ledspin(parent: HBoxContainer, mn: float, mx: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = step
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.get_line_edit().add_theme_font_size_override("font_size", 10)
	sb.value_changed.connect(func(_v: float) -> void: _on_led_changed())
	parent.add_child(sb)
	return sb

# ── Plume style data ────────────────────────────────────────────────────────────

## 2026-08-21 ("áp dụng code plume này vào weapon edit"): bumped from the original (barely-visible-at-
## gameplay-scale) numbers to match glb_topdown_rig.gd::make_plume()'s own updated fallback — see that
## function's header for the full story (rotation was correct the whole time; the ACTIVE TP just had no
## saved style, so both this dict AND make_plume()'s own inline fallback were what actually rendered, and
## both were too small/short-lived/pale to read as "clearly rotating" against real gameplay). This dict is
## what a freshly-SELECTED TP auto-populates with the moment `_refresh_plume_editor()`/`_get_tp_plume_style`
## first touches it — keep in sync with glb_topdown_rig.gd's fallback or the two defaults silently diverge
## again (this dict wins in practice: once a TP has been selected even once, this gets saved to
## weapon_plume_styles.cfg, and a saved key always beats make_plume()'s own `.get(key, fallback)`).
func _default_plume_style() -> Dictionary:
	return {
		"vel_min":   60.0,
		"vel_max":   80.0,
		"lifetime":  0.6,
		"spread":    4.0,
		"sc_min":    1.5,
		"sc_max":    2.5,
		"col_core":  Color(1.0, 0.95, 0.7, 1.0),
		"col_flame": Color(1.0, 0.6,  0.2, 1.0),
		"col_cool":  Color(0.45, 0.6, 1.0, 0.85),
	}

func _get_selected_tp_id() -> int:
	if _active_creep.is_empty() or _selected_tp_idx < 0:
		return -1
	var tps: Array = _thrust_points.get(_active_creep, [])
	if _selected_tp_idx >= tps.size():
		return -1
	return int(tps[_selected_tp_idx].get("id", _selected_tp_idx + 1))

func _get_tp_plume_style(tp_id: int) -> Dictionary:
	if _active_creep.is_empty() or tp_id < 0:
		return _default_plume_style()
	if not _plume_styles.has(_active_creep):
		_plume_styles[_active_creep] = {}
	var cmap: Dictionary = _plume_styles[_active_creep]
	var key := "tp_%d" % tp_id
	if not cmap.has(key):
		cmap[key] = _default_plume_style()
	return cmap[key]

func _refresh_plume_editor() -> void:
	if _plume_vel_min_spin == null:
		return
	var n := _selected_tp_indices.size()
	var has_tp := n > 0
	var tp_id := _get_selected_tp_id()
	if _plume_tp_label != null:
		if not has_tp:
			_plume_tp_label.text    = "– select a TP –"
			_plume_tp_label.modulate = Color(0.55, 0.55, 0.55)
		elif n == 1:
			_plume_tp_label.text    = "TP %d" % tp_id
			_plume_tp_label.modulate = Color(0.55, 0.90, 1.0)
		else:
			_plume_tp_label.text    = "%d TPs selected" % n
			_plume_tp_label.modulate = Color(0.75, 0.90, 1.0)
	for spin: SpinBox in [_plume_vel_min_spin, _plume_vel_max_spin,
			_plume_life_spin, _plume_spread_spin,
			_plume_sc_min_spin, _plume_sc_max_spin]:
		spin.editable = has_tp
	for cpb: ColorPickerButton in [_plume_col_core_btn, _plume_col_flame_btn, _plume_col_cool_btn]:
		cpb.disabled = not has_tp
	if not has_tp or tp_id < 0:
		return
	# Load primary TP's style into the controls
	_updating_plume = true
	var s := _get_tp_plume_style(tp_id)
	_plume_vel_min_spin.value  = float(s.get("vel_min",  80.0))
	_plume_vel_max_spin.value  = float(s.get("vel_max",  130.0))
	_plume_life_spin.value     = float(s.get("lifetime", 0.35))
	_plume_spread_spin.value   = float(s.get("spread",   12.0))
	_plume_sc_min_spin.value   = float(s.get("sc_min",   1.0))
	_plume_sc_max_spin.value   = float(s.get("sc_max",   2.2))
	_plume_col_core_btn.color  = s.get("col_core",  Color(1.0, 0.95, 0.7, 1.0))
	_plume_col_flame_btn.color = s.get("col_flame", Color(1.0, 0.6,  0.2, 1.0))
	_plume_col_cool_btn.color  = s.get("col_cool",  Color(0.45, 0.6, 1.0, 0.85))
	_updating_plume = false

func _on_plume_changed() -> void:
	if _updating_plume or _active_creep.is_empty() or _selected_tp_indices.is_empty():
		return
	if not _plume_styles.has(_active_creep):
		_plume_styles[_active_creep] = {}
	var tps: Array = _thrust_points.get(_active_creep, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx < 0 or sel_idx >= tps.size():
			continue
		var tp_id: int = int(tps[sel_idx].get("id", sel_idx + 1))
		var s := _get_tp_plume_style(tp_id)
		s["vel_min"]   = _plume_vel_min_spin.value
		s["vel_max"]   = _plume_vel_max_spin.value
		s["lifetime"]  = _plume_life_spin.value
		s["spread"]    = _plume_spread_spin.value
		s["sc_min"]    = _plume_sc_min_spin.value
		s["sc_max"]    = _plume_sc_max_spin.value
		s["col_core"]  = _plume_col_core_btn.color
		s["col_flame"] = _plume_col_flame_btn.color
		s["col_cool"]  = _plume_col_cool_btn.color
		_plume_styles[_active_creep]["tp_%d" % tp_id] = s
	_refresh_plume_preview()
	_dirty = true

## Copy the selected TP's full plume style (all params + colors) into the clipboard.
func _copy_plume_style() -> void:
	if _active_creep.is_empty() or _selected_tp_indices.is_empty():
		return
	var tp_id := _get_selected_tp_id()
	if tp_id < 0:
		return
	_plume_clipboard = (_get_tp_plume_style(tp_id) as Dictionary).duplicate(true)
	show_toast("Plume style copied")

## Replace the selected TP(s)' plume style with the clipboard. No-op if nothing has been copied yet.
func _paste_plume_style() -> void:
	if _plume_clipboard.is_empty() or _active_creep.is_empty() or _selected_tp_indices.is_empty():
		return
	# Push the clipboard into the controls (guarded so the per-spin signals don't write piecemeal),
	# then _on_plume_changed() writes the whole style into every selected TP at once.
	_updating_plume = true
	_plume_vel_min_spin.value  = float(_plume_clipboard.get("vel_min",  _plume_vel_min_spin.value))
	_plume_vel_max_spin.value  = float(_plume_clipboard.get("vel_max",  _plume_vel_max_spin.value))
	_plume_life_spin.value     = float(_plume_clipboard.get("lifetime", _plume_life_spin.value))
	_plume_spread_spin.value   = float(_plume_clipboard.get("spread",   _plume_spread_spin.value))
	_plume_sc_min_spin.value   = float(_plume_clipboard.get("sc_min",   _plume_sc_min_spin.value))
	_plume_sc_max_spin.value   = float(_plume_clipboard.get("sc_max",   _plume_sc_max_spin.value))
	_plume_col_core_btn.color  = _plume_clipboard.get("col_core",  _plume_col_core_btn.color)
	_plume_col_flame_btn.color = _plume_clipboard.get("col_flame", _plume_col_flame_btn.color)
	_plume_col_cool_btn.color  = _plume_clipboard.get("col_cool",  _plume_col_cool_btn.color)
	_updating_plume = false
	_on_plume_changed()
	show_toast("Plume style pasted")

func _reset_plume_style() -> void:
	if _active_creep.is_empty() or _selected_tp_indices.is_empty():
		return
	if not _plume_styles.has(_active_creep):
		_plume_styles[_active_creep] = {}
	var tps: Array = _thrust_points.get(_active_creep, [])
	for sel_idx: int in _selected_tp_indices:
		if sel_idx < 0 or sel_idx >= tps.size():
			continue
		var tp_id: int = int(tps[sel_idx].get("id", sel_idx + 1))
		_plume_styles[_active_creep]["tp_%d" % tp_id] = _default_plume_style()
	_refresh_plume_editor()
	_refresh_plume_preview()
	_dirty = true

# ── Plume style persistence ─────────────────────────────────────────────────────

func _load_plume_styles() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_plume_path()) != OK:
		return
	if not cfg.has_section("styles"):
		return
	for key: String in cfg.get_section_keys("styles"):
		_plume_styles[key] = cfg.get_value("styles", key, _default_plume_style())

func _save_plume_styles() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_plume_path())
	for cname: String in _plume_styles:
		cfg.set_value("styles", cname, _plume_styles[cname])
	cfg.save(_plume_path())

# ── Vortex style persistence (shares the plume cfg file, separate "vortex_styles" section) ──
func _load_vortex_styles() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_plume_path()) != OK:
		return
	if not cfg.has_section("vortex_styles"):
		return
	for key: String in cfg.get_section_keys("vortex_styles"):
		_vortex_styles[key] = cfg.get_value("vortex_styles", key, _default_vortex_style())

func _save_vortex_styles() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_plume_path())
	for cname: String in _vortex_styles:
		cfg.set_value("vortex_styles", cname, _vortex_styles[cname])
	cfg.save(_plume_path())

# ── Led style persistence (2026-08-15 — shares the plume cfg file, separate "led_styles" section) ──
func _load_led_styles() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_plume_path()) != OK:
		return
	if not cfg.has_section("led_styles"):
		return
	for key: String in cfg.get_section_keys("led_styles"):
		_led_styles[key] = cfg.get_value("led_styles", key, _default_led_style())

func _save_led_styles() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_plume_path())
	for cname: String in _led_styles:
		cfg.set_value("led_styles", cname, _led_styles[cname])
	cfg.save(_plume_path())

# ── CHAIN section (2026-08-12, taper added 2026-08-13) — segment count / spacing / bend-lock / taper for
# multi-node enemies ─────────────────────────────────────────────────────────────────────────────────────
## Persisted to res://creep_chain_overrides.cfg, same sparse-override + apply-at-director-_ready() shape as
## creep_info_panel.gd's res://creep_info_overrides.cfg (kept as a SEPARATE file on purpose: Creep Info's own
## Save rebuilds its whole "overrides" dict from its own visible rows on every save, which would silently
## drop these 4 keys if they shared one file). Static so both wave directors can call it without an instance.
static func load_chain_overrides() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(CHAIN_CFG_PATH) != OK:
		return {}
	var data = cfg.get_value("overrides", "data", {})
	return data if data is Dictionary else {}

## Mutates `defs` IN PLACE — call once per director, on its OWN ENEMY_DEFS, from that director's _ready().
static func apply_chain_overrides(defs: Dictionary) -> void:
	var ov := load_chain_overrides()
	for id in ov.keys():
		if not defs.has(id):
			continue
		var o: Dictionary = ov[id]
		var entry: Dictionary = defs[id]
		if o.has("centi_segments"):
			entry["centi_segments"] = int(o["centi_segments"])
		if o.has("centi_bend_deg"):
			entry["centi_bend_deg"] = float(o["centi_bend_deg"])
		if o.has("centi_spacing_mult"):
			entry["centi_spacing_mult"] = float(o["centi_spacing_mult"])
		if o.has("centi_taper_pct"):
			entry["centi_taper_pct"] = float(o["centi_taper_pct"])

## Which ENEMY_DEFS id (if any) the given creep name's CHAIN params belong to — checks the creep itself,
## then walks up to its group root (creep_layout.cfg "parent"), since the active creep may be any one of
## the chain's parts (head/body/tail), not just the one whose basename happens to key CHAIN_PARTS.
func _chain_id_for(creep_name: String) -> String:
	if CHAIN_PARTS.has(creep_name):
		return String(CHAIN_PARTS[creep_name])
	var root: String = _creep_parents.get(creep_name, "")
	if not root.is_empty() and CHAIN_PARTS.has(root):
		return String(CHAIN_PARTS[root])
	return ""

func _build_chain_controls(root: VBoxContainer) -> void:
	_chain_section = VBoxContainer.new()
	_chain_section.add_theme_constant_override("separation", 3)
	_chain_section.visible = false
	root.add_child(_chain_section)

	_chain_section.add_child(HSeparator.new())
	var hdr := Label.new()
	hdr.text = "CHAIN (multi-node)"
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.modulate = Color(0.60, 0.63, 0.76)
	_chain_section.add_child(hdr)

	# 2026-08-15, per user request ("không hiển thị description, để tránh làm bảng quá dài"): the explainer
	# label that used to sit here is gone — it was also stale (pos now DOES affect spawn for Head↔Body-
	# template and Body-template↔Tail gaps, see arena_enemy.gd's _centi_joint_spacing()). Kept as a code
	# comment instead: Head/every Body-template/Tail's SIZE and their gap to their immediate neighbor (when
	# both ends are real, non-duplicate nodes) are authored here and DO apply at spawn; Segments/Spacing/Bend/
	# Taper below still drive everything else (duplicate count, their derived size/spacing, bend clamp).
	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 3)
	_chain_section.add_child(seg_row)
	# NOTE: pass an explicit (no-op) callback — _small_spin()'s default with no callback wires value_changed
	# to _on_spin_changed()/_apply_spin_to_selected(), which would misapply these values as if they were the
	# SELECTED SPRITE'S transform (W/H/pos). These 3 fields are unrelated to any single EO's transform.
	_chain_seg_spin = _small_spin(seg_row, "Segments", 3.0, 40.0, _on_chain_field_changed)
	_chain_seg_spin.step = 1.0

	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 3)
	_chain_section.add_child(sp_row)
	# 2026-08-22 ("chỉnh spacing về min 0.3 nhưng các segment vẫn còn xa nhau... muốn hơi clip lên nhau"):
	# floor lowered 0.3 -> 0.05. With the centre-to-centre stepping a force-arranged chain uses, 1.0 = exactly
	# touching, so anything below that already overlaps — the old 0.3 floor only LOOKED far apart because
	# every EO rect was sized to a hugely padded thumbnail (see _fit_preview_cam); that is fixed separately,
	# and this just gives headroom to push segments further into each other.
	_chain_spacing_spin = _small_spin(sp_row, "Spacing x", 0.05, 3.0, _on_chain_field_changed)
	_chain_spacing_spin.step = 0.05

	var bend_row := HBoxContainer.new()
	bend_row.add_theme_constant_override("separation", 3)
	_chain_section.add_child(bend_row)
	# 2026-08-15: min was hardcoded at 10° with no functional reason — the bend-clamp math (arena_enemy.gd's
	# _update_centipede_chain(), `clampf(diff, -_centi_max_bend, _centi_max_bend)`) works fine all the way
	# down to 0° (a fully rigid, non-bending chain), so lowered the floor to let that be selectable.
	_chain_bend_spin = _small_spin(bend_row, "Bend lock (deg)", 0.0, 180.0, _on_chain_field_changed)
	_chain_bend_spin.step = 5.0

	# Taper — a literal drag slider (not a SpinBox like the 3 above), per explicit request; mirrors the
	# existing Zoom slider's own row layout (label + HSlider + "NN%" readout).
	var taper_row := HBoxContainer.new()
	taper_row.add_theme_constant_override("separation", 4)
	_chain_section.add_child(taper_row)
	var taper_lbl := Label.new()
	taper_lbl.text = "Taper:"
	taper_lbl.add_theme_font_size_override("font_size", 10)
	taper_lbl.custom_minimum_size = Vector2(34.0, 0.0)
	taper_row.add_child(taper_lbl)
	_chain_taper_slider = HSlider.new()
	_chain_taper_slider.min_value = 0.0
	_chain_taper_slider.max_value = 10.0   # 0% - 10% PER-STEP shrink (2026-08-14 re-spec — see _rebuild_chain_preview()/_centi_seg_scale())
	_chain_taper_slider.step      = 0.1
	_chain_taper_slider.value     = 0.0
	_chain_taper_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chain_taper_slider.value_changed.connect(_on_chain_taper_slider_changed)
	taper_row.add_child(_chain_taper_slider)
	_chain_taper_lbl = Label.new()
	_chain_taper_lbl.text = "0%"
	_chain_taper_lbl.add_theme_font_size_override("font_size", 10)
	_chain_taper_lbl.custom_minimum_size = Vector2(30.0, 0.0)
	_chain_taper_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	taper_row.add_child(_chain_taper_lbl)

	var chain_btn_row := HBoxContainer.new()
	chain_btn_row.add_theme_constant_override("separation", 3)
	_chain_section.add_child(chain_btn_row)
	# No "Save Chain" button (removed 2026-08-14, per explicit request: "Bỏ nút save chains đi, mọi thay đổi
	# có hiệu lực ngay tức thì") — every field edit now applies + persists immediately, see
	# _on_chain_field_changed()/_apply_chain_fields(). "Reset" (below) still makes sense on its own: revert to
	# hardcoded defaults.
	var chain_reset_btn := Button.new()
	chain_reset_btn.text = "Reset"
	chain_reset_btn.add_theme_font_size_override("font_size", 11)
	chain_reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain_reset_btn.pressed.connect(_on_chain_reset)
	chain_btn_row.add_child(chain_reset_btn)

	_chain_status = Label.new()
	_chain_status.add_theme_font_size_override("font_size", 9)
	_chain_status.modulate = Color(1.0, 0.85, 0.3)
	_chain_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_chain_section.add_child(_chain_status)

## Called whenever the active creep / selection changes (see _refresh_transform_panel()). Shows the section
## only when the active creep is part of a chain (CHAIN_PARTS) and fills the spinboxes with the LIVE
## ENEMY_DEFS value (which already reflects any saved override, applied at the director's own _ready()).
## 2026-08-14: every field is applied + persisted to disk IMMEDIATELY on every edit now (see
## _apply_chain_fields()) — there is no "unsaved" state anymore, so this can safely re-read `def` on EVERY
## call (including just clicking a different LAYERS row within the SAME chain group) without ever risking
## discarding a live edit; `def` already reflects whatever was last typed/dragged, not a stale saved copy.
## (This also happens to be exactly what fixes the "chỉnh segment lên 8, bấm layer tail, segment tự về 3"
## report — under the old deferred-save model `def` still held the pre-edit value until an explicit Save.)
func _refresh_chain_controls() -> void:
	if _chain_section == null:
		return
	_chain_active_id = _chain_id_for(_active_creep)
	_chain_section.visible = _chain_active_id != ""
	if _chain_active_id == "":
		# Switched away from any chain group entirely -- drop its duplicates (pure derived canvas clutter
		# once nothing chain-related is being edited).
		_clear_chain_dups()
		return
	# 2026-08-22 bug fix ("tăng segment, bấm save, di chuyển layer bằng phím mũi tên thì segment bị reset"):
	# this used to show `_chain_defaults()` ALONE. That silently worked for enemy chains only because
	# `apply_chain_overrides()` mutates `ENEMY_DEFS` IN PLACE — so for them "the defaults" already contain
	# whatever was saved. A chain whose defaults are real constants (VIPER's, from arena_weapons.gd) has no
	# such backdoor, so every refresh threw the saved values away and repainted the hardcoded ones. And since
	# `_refresh_transform_panel()` calls this on EVERY selection change / layer nudge, simply clicking another
	# layer was enough to do it — after which the next field edit wrote those wrong values back to disk,
	# destroying the real ones for good. Overlay the saved override explicitly instead of relying on a
	# side-effect: correct for both kinds of chain, and no longer dependent on who mutates what.
	# `.duplicate()` is required — the enemy path returns the live ENEMY_DEFS entry BY REFERENCE, and merging
	# into that would corrupt the very dict this is supposed to only read.
	var def: Dictionary = (_chain_defaults(_chain_active_id) as Dictionary).duplicate()
	var saved: Dictionary = load_chain_overrides().get(_chain_active_id, {})
	for k: String in saved:
		def[k] = saved[k]
	_updating_spin = true
	_chain_seg_spin.value     = float(def.get("centi_segments", ArenaEnemyScript.CENTI_SEGMENTS_DEFAULT))
	_chain_spacing_spin.value = float(def.get("centi_spacing_mult", 1.0))
	_chain_bend_spin.value    = float(def.get("centi_bend_deg", rad_to_deg(ArenaEnemyScript.CENTI_MAX_BEND_DEFAULT)))
	_chain_taper_slider.value = float(def.get("centi_taper_pct", 0.0))
	_chain_taper_lbl.text     = "%.1f%%" % _chain_taper_slider.value
	_updating_spin = false
	_chain_status.text = ""
	_rebuild_chain_preview()

## Fires on every keystroke/drag-tick in the 4 CHAIN fields — applies + persists immediately (no separate
## "Save Chain" step anymore, per explicit request: "mọi thay đổi có hiệu lực ngay tức thì"). Guarded so the
## programmatic refresh in _refresh_chain_controls() (which also touches .value, wrapped in _updating_spin)
## doesn't re-trigger itself.
func _on_chain_field_changed() -> void:
	if _updating_spin:
		return
	_apply_chain_fields()
	# Segments / Spacing / Taper change what the game's own layout IS, so re-seed the real parts from it
	# instead of leaving them at the previous spacing (2026-08-23). Clearing the once-per-root latch is all it
	# takes: `_rebuild_chain_preview()` re-runs `_auto_arrange_chain_templates()` whenever it is not set.
	# Only for a chain with an arena authority — an enemy chain's layout is hand-placed and must not be reset.
	var croot := _group_root_of(_active_creep)
	if not _chain_geometry(croot).is_empty():
		_chain_arranged.erase(croot)
	_rebuild_chain_preview()

## Taper slider's own value_changed — keeps the "NN%" readout live while dragging, same pattern as the
## existing Zoom slider (_on_zoom_slider_changed/_zoom_pct_lbl).
func _on_chain_taper_slider_changed(v: float) -> void:
	_chain_taper_lbl.text = "%.1f%%" % v
	_on_chain_field_changed()

## 2026-08-14 rewrite (full redo, per explicit request — the previous "sticky template" design kept
## regressing: nodes vanishing after a move+taper, positions snapping back, etc). Model is now as simple and
## defensive as possible:
##
##  - HEAD, every BODY TEMPLATE (the first-encountered sprite for each distinct body texture — e.g. plain
##    chains have exactly one, hammerhead-style reskins have two: body1/body2), and TAIL are ALL real, fully
##    independent nodes. This function NEVER writes to any of their `.position`/`.size` — full stop — so
##    nothing you do to one (move, resize) can ever be undone by a Segments/Spacing/Taper edit or by
##    re-selecting a different LAYERS row. The one-time exception is `_auto_arrange_chain_templates()` below,
##    which only fires once per root, per session, and only when every part is still stacked exactly on the
##    head's spot (i.e. never touched) — see `_chain_arranged`.
##  - DUPLICATES (extra segments beyond what naming gives you real sprites for) are the ONLY thing this
##    function ever creates/moves/resizes. They're fully derived, thrown away and regenerated from scratch on
##    every call: each hangs directly below whatever real/duplicate node comes right before it in the chain,
##    at that node's CURRENT position + size, so moving or resizing ANY earlier node drags every duplicate
##    after it along live. Kept OUT of _all_creep_names (_save_layout()/_scan_creeps()/palette never see them).
##  - Taper (0-10%, 2026-08-14 re-spec) scales ONLY duplicates, PER-STEP COMPOUNDING: each duplicate is
##    exactly (1-taper%) smaller than the one right before it in its own texture's run — not a fraction of the
##    whole chain. A texture's own template/first-use slot is always its own authored size (steps=0) — mirrors
##    arena_enemy.gd's _centi_seg_scale() exactly. Head, every template's own size, and Tail are never scaled.
var _chain_dup_names: Array[String] = []
var _chain_arranged: Dictionary = {}   # root_name -> true once its one-time stacked-default arrange has run

## Frees duplicates IMMEDIATELY (not queue_free()) — this runs on every single Taper/Segments/Spacing
## slider tick, and `_rebuild_chain_preview()` immediately re-creates fresh duplicates under the SAME names
## right after calling this. queue_free() only actually removes the node at end-of-frame, so a fast drag
## (multiple value_changed ticks per rendered frame) would add_child() a new node with a name that's still
## held by the not-yet-freed old one — Godot silently auto-renames the NEW node to dodge the collision, and
## the ORPHANED old node (no longer tracked in _placed/_chain_dup_names) stays fully visible on screen until
## its deferred free finally lands. Visually that reads as overlapping stale-sized ghosts under the cursor —
## exactly the "kéo taper thì méo/lệch" report. Freeing synchronously closes that window entirely.
func _clear_chain_dups() -> void:
	for cname: String in _chain_dup_names:
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo != null and is_instance_valid(eo):
			if eo.get_parent() != null:
				eo.get_parent().remove_child(eo)
			eo.free()
		_placed.erase(cname)
		_creep_parents.erase(cname)
	_chain_dup_names.clear()

## Defense-in-depth, run once whenever the editor is opened (toggle()): removes any leftover node under
## `_objects_container` that matches the chain-duplicate naming pattern ("<template> #<n>") but ISN'T one of
## the currently-tracked duplicates. In the old (pre-2026-08-14) `queue_free()`-based `_clear_chain_dups()`,
## a fast slider drag could leave a same-named node orphaned (Godot auto-renames the new add_child() on a
## collision, abandoning the old one outside of `_placed`/`_chain_dup_names` tracking forever — see the
## `_clear_chain_dups()` comment above for the full mechanism). Those never got cleaned up on their own and
## would sit there indefinitely, visually overlapping later duplicates. This sweep guarantees a clean slate
## on every editor open regardless of what state a previous (possibly pre-fix) session left behind.
func _sweep_stray_chain_dups() -> void:
	if _objects_container == null or not is_instance_valid(_objects_container):
		return
	for child: Node in _objects_container.get_children():
		var nm := String(child.name)
		if not nm.contains(" #"):
			continue
		if _placed.get(nm, null) == child:
			continue   # a currently-tracked duplicate — not stray
		_objects_container.remove_child(child)
		child.free()

## True only if every body/tail part is still sitting exactly on the head's own position — i.e. this chain
## group has never been arranged at all (freshly authored sprites all default-placed on top of each other).
## Real, previously-placed/loaded layouts (distinct positions) always return false here, so this can never
## discard existing data.
func _chain_all_stacked(head_eo: EditableObjectNode, body_templates: Array[String], tail_name: String) -> bool:
	var names := body_templates.duplicate()
	if not tail_name.is_empty():
		names.append(tail_name)
	for cname: String in names:
		var eo: EditableObjectNode = _placed.get(cname, null)
		if eo == null or not is_instance_valid(eo):
			continue
		if not eo.position.is_equal_approx(head_eo.position):
			return false
	return true

## One-time default layout for a chain group that's never been arranged — spreads each template + tail into
## a simple vertical line below the head so they're not all piled on one spot. Runs at most once per root per
## session (see `_chain_arranged` / _chain_all_stacked() above); never runs again after that, so it can never
## clobber a manual edit.
## The authoritative on-screen geometry of `root_name`'s chain, taken from whatever system actually RENDERS
## it in the real game — `{step_px, head_px, body_px, tail_px}`, or {} when there is no such authority
## (2026-08-22, "trên arena và trong weapon edit lấy nguồn dữ liệu hiển thị từ cùng 1 nguồn"). Every chain
## ENEMY returns {} on purpose: their arena layout is hand-placed per map, so the editor's own EO rects ARE
## the source there and must keep behaving exactly as before. `weapon_edit_mode.gd` overrides it for VIPER.
func _chain_geometry(_root_name: String) -> Dictionary:
	return {}

## Per-segment taper factor, `steps` = how many slots past that texture's own template. The default is the
## chain ENEMIES' own formula (mirrors arena_enemy.gd's `_centi_seg_scale()`); `weapon_edit_mode.gd` routes
## it to arena_weapons.gd's static so VIPER's editor preview and its arena render share one definition.
func _chain_seg_scale(taper_pct: float, steps: int) -> float:
	if taper_pct <= 0.001:
		return 1.0
	return pow(1.0 - taper_pct * 0.01, float(maxi(steps, 0)))

## The real on-screen diameter the game draws `creep_name` at, or 0.0 when this editor's own preview scale is
## the only source. Same single-authority idea as `_chain_geometry()`; see `_load_glb_topdown_tex`.
func _arena_display_px(_creep_name: String) -> float:
	return 0.0

## NOTE (2026-08-23) — a `_sync_arena_part_size()` used to sit here, forcing every 3D part's rect to the size
## the game draws it at on every open. Removed: it silently ate W/H edits ("chỉnh lên 33, bấm save, tắt rồi
## mở lại vẫn là 25") and it moved parts, which fed the position drift. W/H belongs to the user.
##
## Nothing is lost by that. A part's rect is a ZOOM on the game's geometry, not a competing definition of it:
## the model is drawn to fill the rect, and a thrust point is placed at `(frac - 0.5) * rect` — exactly the
## arena's `(frac - 0.5) * display_px` scaled by that same zoom, so a TP sits on the identical spot of the
## identical model either way. The zoom only changes how parts relate to EACH OTHER, which is why the chain
## step is scaled by the BODY's zoom (see `_chain_zoom()`): leave the parts at their in-game sizes, or scale
## them by a common factor, and the row is arena-exact.


## How far a part's canvas rect is zoomed relative to the size the GAME draws it at (1.0 = identical). The
## chain step is multiplied by this so the row keeps the arena's PROPORTIONS at whatever scale the parts are
## being authored at — the alternative, forcing the rects, is what ate the user's W/H edits (see the note
## above `_auto_arrange_chain_templates`). Read off the first BODY template, since the step is a body-to-body
## distance in the game. 1.0 whenever the part has no arena size or hasn't been laid out yet.
func _chain_zoom(body_templates: Array[String]) -> float:
	if body_templates.is_empty():
		return 1.0
	var bname: String = body_templates[0]
	var px := _arena_display_px(bname)
	if px <= 0.001:
		return 1.0
	var beo: EditableObjectNode = _placed.get(bname, null)
	if beo == null or not is_instance_valid(beo) or beo.size.y < 0.01:
		return 1.0
	return beo.size.y / px

## One-time default arrangement for a chain group. 2026-08-22: when `_chain_geometry()` supplies the game's
## own numbers, this steps by the ARENA's uniform centre-to-centre `step_px` along the chain axis, exactly
## like `_rebuild_chain_preview()` does for the generated duplicates — the two used to disagree (this one
## stepped by each part's own RECT HEIGHT from the head's bottom EDGE and always straight down; the other
## stepped centre-to-centre along the rotated axis), which is what buried the head inside the body run once
## the group was rotated. Without geometry (every chain enemy) the original edge-stacking is kept verbatim.
func _auto_arrange_chain_templates(root_name: String, head_eo: EditableObjectNode, body_templates: Array[String], tail_name: String) -> void:
	var spacing_mult: float = _chain_spacing_spin.value
	# With an arena authority, lay the real parts out on the GAME's own uniform centre-to-centre step, scaled
	# by the authored zoom — the same rule the duplicates use, so the whole row is one sequence. Runs when the
	# layout is seeded and whenever a CHAIN field changes (see _on_chain_field_changed), NOT on every rebuild:
	# between those, the positions are the user's to nudge and drag, and they stay put.
	var geo0 := _chain_geometry(root_name)
	if not geo0.is_empty():
		var step0: float = _chain_step_px(geo0) * _chain_zoom(body_templates)
		var centre0: Vector2 = head_eo.position + head_eo.size * 0.5
		var slot := 1
		for template_name: String in body_templates:
			var beo: EditableObjectNode = _placed.get(template_name, null)
			if beo == null or not is_instance_valid(beo):
				continue
			beo.position = centre0 + Vector2(0.0, step0 * float(slot)) - beo.size * 0.5
			slot += 1
		if not tail_name.is_empty():
			var teo0: EditableObjectNode = _placed.get(tail_name, null)
			if teo0 != null and is_instance_valid(teo0):
				# The tail belongs at the END of the whole chain, not right after the last TEMPLATE.
				var n0 := int(round(_chain_seg_spin.value))
				teo0.position = centre0 + Vector2(0.0, step0 * float(maxi(n0 - 1, slot))) - teo0.size * 0.5
		return
	var cursor_y: float = head_eo.position.y + head_eo.size.y
	for template_name: String in body_templates:
		var eo: EditableObjectNode = _placed.get(template_name, null)
		if eo == null or not is_instance_valid(eo):
			continue
		eo.position = Vector2(head_eo.position.x + (head_eo.size.x - eo.size.x) * 0.5, cursor_y)
		cursor_y += eo.size.y * spacing_mult
	if not tail_name.is_empty():
		var tail_eo: EditableObjectNode = _placed.get(tail_name, null)
		if tail_eo != null and is_instance_valid(tail_eo):
			tail_eo.position = Vector2(head_eo.position.x + (head_eo.size.x - tail_eo.size.x) * 0.5, cursor_y)

## The one centre-to-centre step every part of an arena-authored chain is laid out by. A separate reader so
## the three placement sites (templates, duplicates, tail) can't pick the value up differently — that
## divergence is what this whole pass is undoing.
func _chain_step_px(geo: Dictionary) -> float:
	return maxf(float(geo.get("step_px", 0.0)), 0.01)

## Unit vector on the canvas that the chain runs along, from the group's own mount rotation. Extracted so the
## one-time template arrangement and the per-rebuild duplicate placement can no longer drift apart — they
## used to compute this in only one of the two places. Canvas X = view X and canvas Y = view Z, so the
## chain's own "down" axis (view (0,0,1)) rotated by the mount angle projects to (x, z). Straight down at
## rotation zero, which is what the un-rotated layout has always been.
func _chain_axis(root_name: String) -> Vector2:
	var grig: Dictionary = _rig_for_creep(root_name)
	if grig.is_empty():
		return Vector2(0.0, 1.0)
	var rr_c := preload("res://scripts/gameplay/fx/glb_topdown_rig.gd").new()
	var grot: Vector3 = rr_c.compose_rot(grig.get("rot_base", Vector3.ZERO), grig.get("rot", Vector3.ZERO))
	var d3 := rr_c.view_basis(grot) * Vector3(0.0, 0.0, 1.0)
	var d2 := Vector2(d3.x, d3.z)
	return d2.normalized() if d2.length() > 0.01 else Vector2(0.0, 1.0)

func _rebuild_chain_preview() -> void:
	_clear_chain_dups()
	if _chain_active_id == "" or _objects_container == null:
		return
	var root_name: String = _active_creep
	var par: String = _creep_parents.get(_active_creep, "")
	if not par.is_empty():
		root_name = par
	var head_eo: EditableObjectNode = _placed.get(root_name, null)
	if head_eo == null or not is_instance_valid(head_eo):
		return
	# 2026-08-22 bug fix (pre-existing, newly reachable): `Dictionary.get()` hands back an UNTYPED Array, and
	# assigning that straight to an `Array[String]` throws at runtime — which happened for every chain root
	# NOT auto-grouped by the Head/Body<N>/Tail naming regex. No enemy chain hit it (their names all match),
	# but VIPER's parts ("VIPER head top" / "VIPER Tail") don't, so wiring VIPER into this panel started
	# spamming the error. `assign()` does the typed copy the plain assignment could not.
	var members: Array[String] = []
	members.assign(_chain_group_order.get(root_name, []))
	if members.is_empty():
		# Fallback for a chain group that wasn't naming-convention-detected (e.g. a CHAIN_PARTS entry added
		# by hand for a set that doesn't match Head/Body<N>/Tail) -- just chain whatever children exist, in
		# whatever order they're already in; no duplicate-generation for this path (kind is unknown).
		for cname: String in _all_creep_names:
			if _creep_parents.get(cname, "") == root_name:
				members.append(cname)
		_position_chain_members(head_eo, members)
		return
	# Split into ordered BODY templates + the (at most one) TAIL, using each member's own parsed kind rather
	# than assuming "last member = tail" (robust even if a future set's tail sorts earlier alphabetically).
	var body_templates: Array[String] = []
	var tail_name := ""
	for cname: String in members:
		var parsed := _parse_chain_name(cname)
		if String(parsed.get("kind", "")) == "tail":
			tail_name = cname
		else:
			body_templates.append(cname)
	if body_templates.is_empty():
		_position_chain_members(head_eo, members)   # nothing to template off of -- fall back to plain reposition
		return
	if not _chain_arranged.get(root_name, false):
		_chain_arranged[root_name] = true
		# `_chain_all_stacked()` is the conservative trigger: only auto-arrange a group whose parts are all
		# still piled on one spot, so a hand-placed layout is never clobbered. `_chain_force_arrange()`
		# (2026-08-22) is the opt-in override for a chain that should ALWAYS be laid out as one centred row —
		# see weapon_edit_mode.gd's VIPER implementation. Still once-per-root-per-session either way.
		if _chain_all_stacked(head_eo, body_templates, tail_name) or _chain_force_arrange(root_name):
			_auto_arrange_chain_templates(root_name, head_eo, body_templates, tail_name)
	var n := int(round(_chain_seg_spin.value))
	var spacing_mult: float = _chain_spacing_spin.value
	var taper_pct: float = _chain_taper_slider.value
	var template_count: int = body_templates.size()
	var body_count: int = maxi(0, n - 1 - (1 if not tail_name.is_empty() else 0))   # segments excluding head + tail
	var prev_eo: EditableObjectNode = head_eo
	# 2026-08-15 bug fix ("kéo Taper lên, các node xa gốc bị dẹp + lệch phải"): NOT a size/position math bug
	# (verified numerically — the ratio/centering formulas are exactly right at every step, see the reply's
	# analysis). Real cause: EditableObjectNodes don't clip each other — whichever one is LATER in
	# _objects_container's child list simply paints ON TOP in the overlap region (Godot's default same-z paint
	# order). Duplicates get add_child()ed in farthest-first order (i=2, then 3, then 4…), so at any Spacing <
	# 1.0 (segments overlapping on purpose) the FARTHEST/smallest duplicate always painted OVER the larger one
	# just ahead of it — backwards from the real arena's own convention (_draw_centipede(): tail drawn first,
	# head drawn LAST = head always on top). That mismatch read as "far ones chewed into a flattened, off-
	# center sliver" — the box itself never moved (proven), only which pixels of the overlap won the paint
	# order. `_chain_z_order` collects every real/dup node in head→tail order; fixed into the correct paint
	# order (head topmost, tail bottommost) right after the loop below.
	# Capture the PREVIOUS length before overwriting — the tail branch below compares against it to decide
	# whether the chain actually got longer/shorter (writing first would always compare equal).
	var prev_segs: int = int(_chain_last_segs.get(root_name, -1))
	_chain_last_segs[root_name] = n
	# A force-arranged chain lays its segments out along the direction the GROUP is rotated to, not always
	# straight down — otherwise rotating the assembly (see _apply_group_rigid_delta) swings the head/body/tail
	# templates round while the duplicates keep re-stacking vertically, tearing the chain apart. Enemy chains
	# keep the plain straight-down step: `_chain_force_arrange()` is false for them, and their layout is
	# hand-authored. Shared with the one-time template arrangement now — see `_chain_axis()`.
	var chain_dir := Vector2(0.0, 1.0)
	if _chain_force_arrange(root_name):
		chain_dir = _chain_axis(root_name)
	# The arena's own geometry when there is an authority for it ({} for every chain enemy) — see
	# `_chain_geometry()`. `step_px` is a single uniform centre-to-centre distance, so the duplicates below
	# and the templates above are laid out by the exact same rule the game uses.
	var geo := _chain_geometry(root_name)
	# Anchor for a derived chain: the head's own centre, so dragging the HEAD still moves the whole
	# assembly while every other slot is computed from it.
	var chain_zoom := _chain_zoom(body_templates)   # keeps arena proportions at the authored scale
	# 2026-08-23: an arena-authored chain runs along a FIXED axis, not one derived from the mount rotation.
	# In game the chain's path comes from where the weapon has travelled (`_snake_move`), and the mount
	# calibration `cal` only ever enters as an ORIENTATION (`Basis(UP,-ang) * view_basis(cal)` — it never
	# touches a position). Swinging the whole row when the Rotate sliders move was an editor invention that
	# put the row somewhere the game never puts it; the sliders still turn each part in place, which is
	# exactly what `cal` does.
	if not geo.is_empty():
		chain_dir = Vector2(0.0, 1.0)
	var _chain_z_order: Array[EditableObjectNode] = [head_eo]
	for i in range(1, body_count + 1):
		var idx: int = clampi(i - 1, 0, template_count - 1)   # mirrors arena_enemy.gd's _centi_tex_for()
		var template_name: String = body_templates[idx]
		var template_eo: EditableObjectNode = _placed.get(template_name, null)
		if template_eo == null or not is_instance_valid(template_eo):
			continue
		var is_first_use: bool = i <= template_count   # this slot IS that texture's own real template node
		var cur_eo: EditableObjectNode
		var steps: int = i - idx - 1
		var ratio: float = _chain_seg_scale(taper_pct, steps)
		if is_first_use:
			cur_eo = template_eo   # no duplicate needed; this slot IS the template node
		else:
			var dup_name := "%s #%d" % [template_name, i]
			var dup_eo: EditableObjectNode = _make_chain_dup_eo(dup_name, template_eo, root_name)
			if dup_eo == null:
				continue
			dup_eo.size = template_eo.size * ratio
			dup_eo._sync_rect_size()
			dup_eo.set_meta("chain_scale", ratio)
			_chain_dup_names.append(dup_name)
			cur_eo = dup_eo
		# Only DUPLICATES are placed here. A real head/body/tail keeps the position it was arranged to and
		# whatever you have since nudged or dragged it to — 2026-08-23, after an attempt at deriving every
		# slot on every rebuild ("bấm layer body lại di chuyển toàn bộ"): that did guarantee arena-exact
		# spacing, but it also meant selecting one layer and moving it either did nothing or moved the whole
		# weapon, because a per-part position could not survive to the next rebuild. The layout is seeded and
		# re-seeded from the game's own numbers instead (`_auto_arrange_chain_templates`, re-run whenever a
		# CHAIN field changes) and is yours in between.
		if not is_first_use:
			var step := (prev_eo.size.y * 0.5 + cur_eo.size.y * 0.5) * spacing_mult
			if not geo.is_empty():
				step = _chain_step_px(geo) * chain_zoom   # the game's uniform centre-to-centre step
			if _chain_force_arrange(root_name) or not geo.is_empty():
				var pc := prev_eo.position + prev_eo.size * 0.5
				cur_eo.position = pc + chain_dir * step - cur_eo.size * 0.5
			else:
				cur_eo.position = Vector2(prev_eo.position.x + (prev_eo.size.x - cur_eo.size.x) * 0.5,
					prev_eo.position.y + prev_eo.size.y * spacing_mult)
		prev_eo = cur_eo
		_chain_z_order.append(cur_eo)
	# 2026-08-15 reverted the 18th-pass "Tail always auto-follows the chain end" behavior (user report:
	# "chỉnh vị trí body2 thì tail cũng bị kéo theo, không chỉnh được vị trí tail độc lập"). Tail is now a
	# fully independent node again — this rebuild NEVER writes its position, same treatment as Head and every
	# Body-template (only true DUPLICATES, which have no position of their own, are ever repositioned here).
	# The 18th-pass concern this was originally solving ("tail nằm ở vị trí khác lạ" after raising Segments)
	# is still covered a different way: `_auto_arrange_chain_templates()` includes Tail in its one-time
	# stacked-default layout (same as Head/Body), and — more importantly — the REAL arena spawn never read
	# Tail's editor position anyway; it now reads the AUTHORED GAP between Tail and whatever precedes it
	# (`arena_enemy.gd`'s `_centi_joint_spacing()`, extended in this same pass to cover the Tail boundary) —
	# so whatever gap you set here is what actually shows up in-game, regardless of Segments/Spacing.
	if not tail_name.is_empty():
		var tail_eo: EditableObjectNode = _placed.get(tail_name, null)
		if tail_eo != null and is_instance_valid(tail_eo):
			# 2026-08-22: the independent-tail rule above is exactly right for ENEMY chains (hand-placed on a
			# map, tail gap authored per-creature) — but a force-arranged chain (`_chain_force_arrange`, i.e.
			# VIPER) is always one assembled row, so its tail has to sit at the END of that row or raising
			# Segments strands it mid-chain. Same centre-on-previous formula the duplicates above use.
			# 2026-08-22 ("Tail không dịch chuyển được độc lập với body như head"): only snap the tail to the
			# chain end when the LENGTH actually changed. Doing it on every rebuild (the previous behaviour)
			# meant any manual nudge was overwritten on the very next refresh — and `_refresh_transform_panel()`
			# triggers one on every selection change, so the tail could never be moved at all. Head and the
			# body TEMPLATE are already only ever positioned by the one-time auto-arrange; this gives the tail
			# the same deal, while still keeping it at the end whenever Segments changes (otherwise raising
			# Segments strands it mid-chain, the reason it was auto-positioned in the first place).
			if _chain_force_arrange(root_name) and prev_segs != n:
				var pc2 := prev_eo.position + prev_eo.size * 0.5
				var step2 := (prev_eo.size.y * 0.5 + tail_eo.size.y * 0.5) * spacing_mult
				if not geo.is_empty():
					step2 = _chain_step_px(geo) * chain_zoom
				tail_eo.position = pc2 + chain_dir * step2 - tail_eo.size * 0.5
			_chain_z_order.append(tail_eo)
	# Paint order fix (see the comment above the loop): re-sibling every node in `_chain_z_order` so head ends
	# up LAST (topmost) and tail FIRST (bottommost) among them, matching arena's tail-first/head-last draw
	# order — walk head→tail order IN REVERSE (tail, …, head), moving each to the current last child slot in
	# turn, so the final pass (head) lands truly last. Doesn't touch any node's saved `z_index` — purely a
	# sibling-order (paint-priority) change, so nothing here leaks into `_save_layout()`'s output.
	# 2026-08-15 — turned out this paint-order reorder was never the actual bug (see the 26th-pass changelog
	# entry: the REAL cause was `editable_object.tscn`'s `TextureRect.expand_mode` silently clamping a shrunk
	# duplicate's WIDTH back up toward the template's own — a Control minimum-size enforcement, fixed at the
	# source). Kept this reorder anyway since it's still a real (if minor, and now moot at non-overlapping
	# Spacing) correctness improvement matching the arena's own tail-first/head-last convention, and it's
	# side-effect-free (no saved data changed) — just no longer load-bearing for the flatten/shift symptom.
	for zi in range(_chain_z_order.size() - 1, -1, -1):
		var zeo: EditableObjectNode = _chain_z_order[zi]
		if zeo != null and is_instance_valid(zeo) and zeo.get_parent() == _objects_container:
			_objects_container.move_child(zeo, _objects_container.get_child_count() - 1)
	# 2026-08-22: this function is what decides the DUPLICATE SET, and the 3D overlay renders that set (and
	# hides exactly its thumbnails) — so the overlay is refreshed from here rather than from the five call
	# sites that rebuild a chain, three of which never did. Missing it left new duplicates drawn as flat
	# thumbnails at the editor's own scale, next to overlay models at the arena's, which is the mismatch this
	# whole pass is removing. Accepted cost: the group-rotation path (_apply_rotation_delta) now builds the
	# overlay twice per slider tick, since it also calls _refresh_plume_preview(). Bounded (a handful of glb
	# instantiations) and in line with what that path already does — see its note on the per-tick cfg write.
	_refresh_plume3d_preview()

## Creates one duplicate body node as an EXACT clone of its template (Node.duplicate(), default flags —
## guaranteed pixel-identical `.size`/`_aspect_ratio`/internal TextureRect state at the moment of cloning, so
## a later uniform `eo.size = template.size × ratio` can't introduce any distortion the template itself
## doesn't already have). Default flags include DUPLICATE_SIGNALS, so the template's OWN object_clicked/
## transform_ended/transform_motion connections likely come along already; the `is_connected()` guards below
## make the explicit (re)connect a no-op in that case instead of risking a double-fired handler either way.
func _make_chain_dup_eo(dup_name: String, template_eo: EditableObjectNode, root_name: String) -> EditableObjectNode:
	if _objects_container == null:
		return null
	var existing: EditableObjectNode = _placed.get(dup_name, null)
	if existing != null and is_instance_valid(existing):
		return existing
	var eo := template_eo.duplicate() as EditableObjectNode
	if eo == null:
		return null
	eo.name = dup_name
	# 2026-08-23 bug fix ("chỉ còn 1 head, 1 body (mất hết segment) và 1 tail"): `Node.duplicate()` copies
	# child nodes and EXPORTED properties, but a plain (non-@export) script variable has no
	# PROPERTY_USAGE_STORAGE, so it is NOT carried over — verified directly: duplicating an EditableObjectNode
	# with `source_path = "…/VIPER body.glb"` yields a copy whose `source_path` is "". Every duplicate has
	# therefore always been anonymous. It never showed because nothing used to ask a duplicate what it was —
	# its TextureRect child (whose `texture` IS exported) carried the picture on its own. The moment the 3D
	# overlay started rendering duplicates it did ask, got "", and skipped all of them, leaving the three
	# templates alone on screen. Copying the three identity fields fixes it at the source rather than in the
	# one caller that happened to notice.
	eo.source_path  = template_eo.source_path
	eo.group_id     = template_eo.group_id
	eo.display_name = template_eo.display_name
	_objects_container.add_child(eo)
	if not eo.object_clicked.is_connected(_on_canvas_object_clicked):
		eo.object_clicked.connect(_on_canvas_object_clicked)
	if not eo.transform_ended.is_connected(_on_transform_ended):
		eo.transform_ended.connect(_on_transform_ended)
	if not eo.transform_motion.is_connected(_on_transform_motion):
		eo.transform_motion.connect(_on_transform_motion)
	_placed[dup_name] = eo
	_creep_parents[dup_name] = root_name
	return eo

## Fallback used only for a chain group NOT detected by the Head/Body<N>/Tail naming convention (kind is
## unknown, so there's no template/duplicate split possible) -- just lines up whatever real children exist,
## every rebuild. Every real def in CHAIN_PARTS today follows the naming convention, so in practice this path
## is unused; kept only so a hand-added CHAIN_PARTS entry that doesn't match the convention still shows SOMETHING.
func _position_chain_members(head_eo: EditableObjectNode, members: Array[String]) -> void:
	var spacing_mult: float = _chain_spacing_spin.value
	var taper_pct: float = _chain_taper_slider.value
	var n: int = members.size()
	var cursor_y: float = head_eo.size.y
	for i in n:
		var eo: EditableObjectNode = _placed.get(members[i], null)
		if eo == null or not is_instance_valid(eo):
			continue
		var scl: float = 1.0 if taper_pct <= 0.0 else pow(1.0 - taper_pct * 0.01, float(i))
		eo.position = Vector2(head_eo.position.x + (head_eo.size.x - eo.size.x) * 0.5, head_eo.position.y + cursor_y)
		cursor_y += eo.size.y * spacing_mult * scl

## Applies the CHAIN section's current field values directly to ENEMY_DEFS (both the shared WaveDirScript
## dict and, if running, v2's own copy) AND persists to creep_chain_overrides.cfg — called on every single
## field edit (see _on_chain_field_changed()), not from a button anymore.
## 2026-08-14 bug fix ("sau khi tắt game mở lại, vẫn chỉ có 3 segment" — a saved Segments=8 silently reverting
## to the hardcoded default on restart): this used to compare the new value against
## `WaveDirScript.ENEMY_DEFS.get(_chain_active_id)` to decide whether to write an override, or ERASE one that
## "matches the default". But `apply_chain_overrides()` (called at the end of this same function) mutates that
## exact dict IN PLACE — so after the first apply, "the default" it was comparing against was actually just
## whatever got written a moment ago, not the true hardcoded default. Any later call that happened to reapply
## the SAME value (a redundant signal fire, re-selecting the same creep, etc.) would then look "unchanged" and
## silently ERASE the override from disk — while the CURRENT session's in-memory ENEMY_DEFS stayed correct
## (already mutated), masking the bug until the next restart re-read the now-empty override file. Fixed by
## dropping the "erase if same as default" cleverness entirely — just always write all 4 fields unconditionally.
## ("Reset", a separate explicit action below, is still how you actually clear an override.)
func _apply_chain_fields() -> void:
	if _chain_active_id == "":
		return
	var ov := load_chain_overrides()
	var entry: Dictionary = ov.get(_chain_active_id, {})
	entry["centi_segments"]     = int(round(_chain_seg_spin.value))
	entry["centi_spacing_mult"] = _chain_spacing_spin.value
	entry["centi_bend_deg"]     = _chain_bend_spin.value
	entry["centi_taper_pct"]    = _chain_taper_slider.value
	ov[_chain_active_id] = entry
	var cfg := ConfigFile.new()
	cfg.set_value("overrides", "data", ov)
	cfg.save(CHAIN_CFG_PATH)
	# Live-apply — matches creep_info_panel.gd's own save flow. WaveDirScript.ENEMY_DEFS is v1's const dict
	# (a single shared instance, so this covers v1 whether or not it's the currently running director); v2
	# (arena_wave_director_v2.gd) duplicates its OWN ENEMY_DEFS at _ready(), so the running instance (if v2)
	# needs its own separate apply too. Already-alive enemies of this type keep their old chain (rebuilt once
	# per instance in _load_centipede(), not re-read per frame) until they respawn.
	_apply_chain_runtime(_chain_active_id)
	_chain_status.text = ""

func _on_chain_reset() -> void:
	if _chain_active_id == "":
		return
	var ov := load_chain_overrides()
	if ov.has(_chain_active_id):
		ov.erase(_chain_active_id)
		var cfg := ConfigFile.new()
		cfg.set_value("overrides", "data", ov)
		cfg.save(CHAIN_CFG_PATH)
	# Reset back to hardcoded defaults (erase, don't just overwrite with the const — a stale key must not
	# linger once the override file no longer has one) — both v1's shared dict and, if running, v2's own copy.
	_clear_chain_runtime(_chain_active_id)
	_apply_chain_runtime(_chain_active_id)
	_refresh_chain_controls()
	_chain_status.text = "Reset to default."

# ── CHAIN hooks (2026-08-22, "áp dụng bảng segment/spacing cho vũ khí viper") ──
## The CHAIN section's own maths (Segments / Spacing× / Bend lock / Taper) was already fully generic — only
## its DATA SOURCE and its live-apply were hardwired to the enemy path (`ENEMY_DEFS` + the wave director).
## These three hooks are that hardwiring pulled out, so `weapon_edit_mode.gd` can point the exact same panel
## at a chain WEAPON (VIPER) without duplicating any of the UI, the cfg format, or the save flow.

## True = always lay `root_name`'s chain out as one centred vertical row on first build, even if its parts
## already sit at hand-placed positions. Base = false (enemy chains keep whatever layout was authored; the
## conservative `_chain_all_stacked()` check decides for them). See _rebuild_chain_preview()'s call site.
func _chain_force_arrange(_root_name: String) -> bool:
	return false

## Defaults shown in the 4 CHAIN fields for `id` when `creep_chain_overrides.cfg` has no entry for it.
func _chain_defaults(id: String) -> Dictionary:
	return WaveDirScript.ENEMY_DEFS.get(id, {})

## Live-apply whatever `creep_chain_overrides.cfg` now holds for `id` — called after every field edit and
## after Reset. Enemy path: push into v1's shared ENEMY_DEFS plus the running v2 director's own copy.
func _apply_chain_runtime(_id: String) -> void:
	apply_chain_overrides(WaveDirScript.ENEMY_DEFS)
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd != null:
		apply_chain_overrides(wd.ENEMY_DEFS)

## Drop `id`'s in-memory chain values so a Reset falls back to the hardcoded defaults (erase rather than
## overwrite — a stale key must not linger once the override file no longer has one).
func _clear_chain_runtime(id: String) -> void:
	var defs_list: Array[Dictionary] = [WaveDirScript.ENEMY_DEFS]
	var wd := get_tree().get_first_node_in_group("wave_director")
	if wd != null:
		defs_list.append(wd.ENEMY_DEFS)
	for defs: Dictionary in defs_list:
		var entry: Dictionary = defs.get(id, {})
		entry.erase("centi_segments")
		entry.erase("centi_spacing_mult")
		entry.erase("centi_bend_deg")
		entry.erase("centi_taper_pct")

# ── Overridable config (weapon_edit_mode.gd overrides these for the weapon editor) ──
func _edit_group() -> String: return "creep_edit"
func _folder() -> String: return ENEMIES_FOLDER
## Every folder the palette scans (see MAP_REGISTRY above). weapon_edit_mode.gd overrides this back down to
## `[_folder()]` — the per-map split is a creep-only concept, weapons have one shared folder.
## creep_edit_mode.gd's own folder list is driven by the "Map:" dropdown (_selected_map_id) — exactly ONE
## map's own folder, not a merge of every map (2026-08-13, per explicit request: "mỗi map sẽ hiện đúng enemy
## set của map đó"). Falls back to `[_folder()]` if _selected_map_id somehow doesn't match any MAP_REGISTRY
## entry (defensive only — the dropdown never offers an id outside MAP_REGISTRY).
func _folders() -> Array[String]:
	for m: Dictionary in MAP_REGISTRY:
		if String(m["id"]) == _selected_map_id:
			return [String(m["folder"])]
	return [_folder()]
func _layout_path() -> String: return LAYOUT_PATH
func _plume_path() -> String: return PLUME_STYLES_PATH
func _title() -> String: return "CREEP EDIT"
## Palette filter. `folder` (2026-08-23) is the folder the file was found in — weapon_edit_mode.gd scans a
## second folder for exactly one file (the player ship) and needs to reject that folder's other contents.
func _accept_file(_fname: String, _folder: String) -> bool: return true

## When false, the Fire/Thrust/Tentacle/Vortex/Led/Plume sections + Add FP/TP/Vortex/Led buttons are hidden
## (hud_edit_mode.gd overrides this — HUD sprites have no firing/thrust points).
func _uses_points() -> bool: return true

## Where a creep lands the FIRST time it is placed, before any saved layout overrides it. Overridable
## (2026-08-23) because Jeager's eight animation-clip layers would otherwise all stack on this one spot and
## the group overlay would render them on top of each other, which makes it impossible to see which one a
## rotation slider is moving. `aspect` is the source texture's height/width.
func _default_creep_rect(creep_name: String, aspect: float) -> Rect2:
	# Metalfly's two bodies get their own side-by-side spots at close to the size the arena draws them.
	# Stacking them on the shared default would put one exactly on top of the other, which makes it
	# impossible to see which body a rotation slider is moving — the same trap Jeager's grid avoids.
	match creep_name:
		MF_COCOON:
			return Rect2(MF_COCOON_POS, Vector2(MF_LAYER_PX, MF_LAYER_PX * aspect))
		MF_ROOT:
			return Rect2(MF_WINGS_POS, Vector2(MF_LAYER_PX, MF_LAYER_PX * aspect))
	return Rect2(Vector2(480.0, 380.0), Vector2(60.0, 60.0 * aspect))

## Explicit asset path for a creep, overriding the "<folder>/<name>.<ext>" scan. weapon_edit_mode.gd uses it
## to point every one of Jeager's animation layers at ONE merged glb; here it resolves Metalfly's two boss
## bodies. "" = use the scan (everything else).
## `_rig_key()` below is what keeps MF_ROOT and MF_WINGS from collapsing into one preview rig — they share
## metalfly.glb, and a path alone as the key would give them one rotation between them.
func _asset_path_for(creep_name: String) -> String:
	return String(MF_GLB.get(creep_name, ""))

## Which animation clip this creep's PREVIEW should play, "" for the glb's own first one. Only meaningful
## when several creeps share one asset, which is exactly Jeager's case after the merge.
func _preview_clip(_creep_name: String) -> String:
	return ""

## Key into `_glb_preview_cache`. Normally just the asset path — but once several layers share ONE glb, a
## path alone would give all of them a single rig, so they would share one rotation, one pose and one
## preview camera. Folding the clip into the key keeps each layer its own.
func _rig_key(creep_name: String, path: String) -> String:
	var clip := _preview_clip(creep_name)
	if not clip.is_empty():
		return path + "#" + clip
	# No clip, but still sharing the asset with other creeps (the master layers on Jeager's merged glb) —
	# fall back to the creep's own name, or they would share one rig and therefore one rotation.
	if not _asset_path_for(creep_name).is_empty():
		return path + "#" + creep_name
	return path

## Heading over the palette grid. The weapon editor overrides it — this panel is the enemy editor's by
## origin, but it is the SAME panel pointed at assets/weaponry there, so labelling that one "ENEMIES" was
## simply wrong (2026-08-23, "bảng này tên cũng đang bị sai, sửa lại thành Weapon").
func _palette_title() -> String: return "ENEMIES"

## When false, the "Map:" dropdown above the ENEMIES grid is hidden (weapon_edit_mode.gd overrides this —
## weapons have one shared folder, no per-map concept at all).
func _show_map_selector() -> bool: return true

## 2026-08-14 bug fix ("mở creep edit có pirate1 xuất hiện, tắt editor vẫn còn tồn tại trên arena"): switching
## the "Map:" dropdown rebuilds `_all_creep_names` down to ONLY the new map's sprites (_scan_creeps()) — the
## previously-ACTIVE creep (still fully `.visible = true` on the canvas) could easily belong to the OLD map and
## simply stop being in that list. Both `_update_all_creep_interactivity()` and `_update_gameplay_visibility()`
## (the only 2 places anything ever gets hidden) walk `_all_creep_names` to decide what to hide — so a creep no
## longer in that list is never visited again, EVER, including on close: a permanently stuck-visible ghost for
## the rest of the session. Hide every currently-placed EO up front, unconditionally, before the swap.
func _on_map_selected(idx: int) -> void:
	if idx < 0 or idx >= MAP_REGISTRY.size():
		return
	_selected_map_id = String(MAP_REGISTRY[idx]["id"])
	for eo: EditableObjectNode in _placed.values():
		if is_instance_valid(eo):
			eo.visible = false
	_active_creep = ""
	_scan_creeps()
	_auto_group_chain_names()
	_build_creep_buttons()
	# 2026-08-15 bug fix ("tail resize / body position bị reset mỗi lần tắt game mở lại — CHỈ ở Creep Edit,
	# arena vẫn đúng"): `_scan_creeps()` just repopulated `_all_creep_names` with THIS map's sprites, but
	# nothing here ever re-read their SAVED pos/size from `creep_layout.cfg` back into `_placed` — that only
	# ever happened once, in `_ensure_built()`, against whatever map was active at that moment (always
	# "default" on a fresh session — `_selected_map_id` isn't persisted). So the first time any non-default-
	# map creep (e.g. Atlantic's "cent") got selected this session, it fell through to
	# `_load_or_create_creep()`'s hardcoded-default fallback (size 60×60·aspect, pos (480,380) — exactly the
	# "reset" values reported) instead of what was actually on disk. `arena_enemy.gd` reads the same file
	# directly, independent of this editor state, which is why only the editor ever showed the wrong values.
	# `_load_layout()` is safe to call again here — it no-ops for any name already in `_placed`.
	_load_layout()
	if not _all_creep_names.is_empty():
		_set_active_creep(_all_creep_names[0])

## Hook: subclasses add extra TRANSFORM-area controls (hud_edit_mode adds the Blend dropdown). Default no-op.
func _build_extra_controls(_root: VBoxContainer) -> void:
	pass

## Hook: subclasses refresh their extra controls when the selection/active object changes. Default no-op.
func _refresh_extra_controls() -> void:
	pass

# ── Toast ──────────────────────────────────────────────────────────────────────

func show_toast(message: String) -> void:
	_toast_label.text    = message
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
