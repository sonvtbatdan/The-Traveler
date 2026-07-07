extends CanvasLayer
## Vampire-Survivors level-up flow (item-based). When GameManager emits `leveled_up`, pause the game and show
## CHOICES item cards; each card is either a NEW item (weapon or aux) or an UPGRADE to an owned one. Picking a
## card acquires/levels the item and resumes. Multiple level-ups from one XP gain queue up (shown one after
## another). CanvasLayer layer 100 + PROCESS_MODE_ALWAYS so it runs while the tree is paused.
##
## Selection follows the roguelite pivot spec: weighted random with owned-item priority, no duplicate cards in
## one screen, slot limits (full slots → only upgrades), and graceful fallback (fewer cards when the pool dries up).
## Replaces the old global-stat-card pool — weapons (arena_weapons.gd) + aux items (arena_aux.gd) ARE the upgrades now.

const ArenaWeapons := preload("res://scripts/gameplay/arena_weapons.gd")
const ArenaAux     := preload("res://scripts/gameplay/arena_aux.gd")
# Optional authored "Level Up" board (edited with the shared board editor): supplies role rects for the
# title / 3 slots / selected / options / stats so this UI can be laid out visually. Empty board → fallback.
const BoardEditScript := preload("res://scripts/ui/boss_edit/hud_edit_mode.gd")

const CHOICES := 3
# Chance a given card slot rolls from the owned-upgrade pool (vs the full new+owned pool). Higher = the player
# sees upgrades for what they already own more often, so picked items keep showing up. (Pivot §5 suggests this
# could scale with player_level — early lower, late higher; kept a flat tunable for now.)
const OWNED_UPGRADE_CHANCE := 0.65

# Weapon spawn weights for the NEW-weapon roll (rarer/special weapons → lower weight). Upgrade weight reuses these.
const WEAPON_WEIGHTS := {
	"gatling_gun": 100, "death_beam": 80, "arc": 80, "gauss": 70,
	"defensive_orbitals": 50, "rift_maker": 40, "dragons_breath": 30, "chemtrail": 40,
	"mortar": 20, "ultrasonicator": 60, "z_sword": 50, "ionizing_field": 70,
	"aliwa": 50, "venomancer": 50, "yari": 30, "swarm": 40, "viper": 30,
	"homing_missile": 60, "offensive_orbitals": 45,
}
const WEAPON_FALLBACK_COLOR := Color(0.55, 0.62, 0.72)   # placeholder swatch if a weapon icon fails to load

var _pending: int = 0
var _showing: bool = false
var _current: Array = []   # the OPTIONS-row array that _pick() acts on (pool / capstone / destroy / single confirm)
var _choices: Array = []   # left-column offered items (tier-1), persistent for this screen
var _route_cache: Dictionary = {}   # ckey → generated pool-perk options, rolled once per left-slot per screen
									 # (re-clicking the same weapon/aux slot must show the SAME 3 perks, not reroll)
var _selected_idx: int = -1   # which left slot is currently selected
var _options_back: bool = false   # true while the All-In "destroy a weapon" sub-view shows (offers a back affordance)
var _capstone_weapon: String = ""    # the weapon being evolved (for the capstone / destroy screens)
# Board-only select-then-confirm, mirrors weapon-icon's hover/click split (Weapon1-3): HOVERING an Upgrade1-3
# card only updates UpgradeDesc/stat-deltas (_hover_preview_idx) — no VFX colour change, matching the
# weapon-icon cards where hover is pure-visual (grow). CLICKING actually selects it (_pending_pick_idx): VFX
# turns red, the sprite is pushed onto WeaponDisplay (replacing whatever's shown), and the authored Confirm
# button commits whichever index is pending. Both reset to -1 on every new options screen, auto-set to 0 when
# there is exactly one option (single-choice screens need no extra click).
var _pending_pick_idx: int = -1
var _hover_preview_idx: int = -1

# ── Stat-delta preview (board Confirm flow) ─────────────────────────────────────────────────
# Hand-verified against arena_aux.gd's _apply_effect / _apply_*_pool_effect: only entries whose GameManager
# call directly touches one of the curated "Weapon Stat" rows are listed, so a shown delta is never a lie
# (many aux/weapon perks land on per-family or per-weapon mechs that don't have — and shouldn't get — a row).
# id → Array[{row, amt, pct}]. amt is the raw fraction/flat added; pct=true → shown as a percent.
const AUX_TOP_DELTAS := {
	"force_field": [{"row": "shield", "amt": 20.0}],
	"crit":        [{"row": "crit_chance", "amt": 0.05, "pct": true}],
	"pickup":      [{"row": "pickup", "amt": 0.15, "pct": true}],
	"xp":          [{"row": "xp", "amt": 0.10, "pct": true}],
	"spawn":       [{"row": "spawn", "amt": 0.15, "pct": true}],
	"retaliation": [{"row": "retaliation", "amt": 5.0}],
	"coin":        [{"row": "coin", "amt": 0.25, "pct": true}],
}
# aux id → {pool_id → Array[{row, amt, pct}]}. Perks not listed (mechs, per-weapon, meta-multipliers,
# STUBs) intentionally show no delta rather than an approximate/misleading one.
const AUX_POOL_DELTAS := {
	"hp": {
		"plating":   [{"row": "hp", "amt": 20.0}],
		"bulwark":   [{"row": "hp", "amt": 10.0}, {"row": "armor", "amt": 1.0}],
		"ablative":  [{"row": "hp", "amt": 10.0}, {"row": "move_speed", "amt": 0.02, "pct": true}],
		"sacrifice": [{"row": "hp", "amt": -0.05, "pct": true}, {"row": "damage", "amt": 0.05, "pct": true}],
		"overall":   [{"row": "hp", "amt": 0.01, "pct": true}, {"row": "damage", "amt": 0.01, "pct": true},
			{"row": "move_speed", "amt": 0.01, "pct": true}, {"row": "armor", "amt": 0.01, "pct": true}],
	},
	"regen": {
		"regen_flat":   [{"row": "hp_regen", "amt": 0.2}],
		"regen_hp":     [{"row": "hp_regen", "amt": 0.1}, {"row": "hp", "amt": 10.0}],
		"regen_shield": [{"row": "hp_regen", "amt": 0.1}],
		"overregen":    [{"row": "shield", "amt": 10.0}],
	},
	"armor": {
		"ex_armor":    [{"row": "armor", "amt": 2.0}],
		"ex_armor_hp": [{"row": "armor", "amt": 1.0}, {"row": "hp", "amt": 1.0}],
	},
	"fire_rate": {
		"rate_all": [{"row": "fire_rate", "amt": 0.025, "pct": true}],
		"tradeoff": [{"row": "fire_rate", "amt": -0.025, "pct": true}],
	},
	"speed": {
		"sp_ms":      [{"row": "move_speed", "amt": 0.06, "pct": true}],
		"sp_dodge":   [{"row": "dodge", "amt": 0.05, "pct": true}],
		"sp_ms_fire": [{"row": "move_speed", "amt": 0.02, "pct": true}, {"row": "fire_rate", "amt": 0.02, "pct": true}],
	},
}

# Node refs (full-screen layout).
var _root: Control = null
var _slot_nodes: Array = []        # the 3 left-column slot Controls
var _selected_box: Control = null  # center-top big-sprite panel
var _options_box: Control = null   # center-bottom options container
var _stats_box: VBoxContainer = null
var _stats_panel: Panel = null
var _title: Label = null
var _backdrop: ColorRect = null
# Authored Level-Up board host (runtime-only board_edit_mode) + its CanvasLayer. Null-safe: if the board is
# empty the layout falls back to the built-in fractional anchors and the chrome layer simply stays hidden.
var _board_layer: CanvasLayer = null
var _board_host = null
var _slot_specs: Array = []          # last computed left-slot specs (shared with the board renderer)
var _rt_choices: Array = []          # runtime board nodes: weapon-choice sprites (+ click)
var _rt_options: Array = []          # runtime board nodes: upgrade-option click targets + labels
var _rt_stats: Array = []            # runtime board nodes: stat rows
var _rt_updesc: Array = []           # runtime board nodes: single UpgradeDesc label (selected option's text)
var _rt_display: Array = []          # runtime board nodes: selected-item sprite (WeaponDisplay)
var _board_blocker: ColorRect = null # host input/darken backdrop while the board is showing
const WEAPON_SPRITE_MARGIN := 8.0    # weapon sprite is this many px smaller than its frame (per the spec)
const CHOICE_SPRITE_SCALE := 0.8     # Weapon1-3 choice sprites shown at 80% of the frame box
const AUX_ICON_DIR := "res://assets/hud/UpgradeIcon/"   # per-id aux icon set (filename = AUX_DEFS id), e.g. hp.png
const PERK_ICON_DIR := "res://assets/hud/perks/"        # per-perk icon set (filename = AUX_POOL perk id), e.g. regen_shield.png
const AUX_ICON_SCALE := 0.8          # aux/perk icons CONTAIN-fit within 80% of BOTH width and height of their frame
									  # (whichever axis is tighter wins) — neither dimension may exceed 80% of the frame.
var _aux_icon_cache: Dictionary = {} # aux id → Texture2D (or null if missing), loaded from AUX_ICON_DIR
var _perk_icon_cache: Dictionary = {} # perk id → Texture2D (or null if missing), loaded from PERK_ICON_DIR

# Weapon skill-point pool perk icons — one subfolder per weapon kind (folder names are the artist's informal
# label, NOT WEAPON_INFO.label/name — kept as authored rather than renaming their folders).
const WEAPON_PERK_ICON_DIR := "res://assets/hud/weapon perks/"
const WEAPON_PERK_FOLDER := {
	"gatling_gun": "Minigun", "death_beam": "Death Beam", "arc": "Arc Lightning", "gauss": "Gauss Pulser",
	"defensive_orbitals": "Orbital Defender", "dragons_breath": "red X", "chemtrail": "Chemtrail", "z_sword": "Z-Sword", "ultrasonicator": "sonic",
}
# A few files were authored with a shorthand name instead of the exact pool id — tolerate those instead of
# requiring a rename: GAUSS_POOL "aoe_mastery" → aoe.png; ZSWORD_POOL/SONIC_POOL "cd" → cooldown.png;
# CHEMTRAIL_POOL "ms" → movespeed.png; DRAGON_POOL "armor_reduction" → "armor reduction.png" (space, as
# authored). See docs/hud.md §12 for the full audit of this art pass.
const WEAPON_PERK_ID_ALIAS := {"aoe_mastery": "aoe", "cd": "cooldown", "ms": "movespeed", "armor_reduction": "armor reduction"}
var _weapon_perk_icon_cache: Dictionary = {} # "kind/perk_id" → Texture2D (or null if missing)

# Full-screen layout fractions (symmetric: left/right columns equal, centered main column).
const COL_L_LEFT  := 0.02
const COL_L_RIGHT := 0.23
const COL_C_LEFT  := 0.25
const COL_C_RIGHT := 0.75
const COL_R_LEFT  := 0.77
const COL_R_RIGHT := 0.98
const CONTENT_TOP    := 0.085   # below the title strip
const CONTENT_BOTTOM := 0.98
const SEL_BOTTOM := 0.55        # selected-item panel bottom (center column)
const OPT_TOP    := 0.60        # options row top (center column)
const SLOT_GAP   := 0.015       # vertical gap between the 3 left slots (fraction)
const FONT_PATH := "res://assets/fonts/Good Old DOS.ttf"
const RING_COL  := Color(1.0, 0.85, 0.2)   # fusion source-box yellow ring

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("levelup_ui")   # reward chests find this to grant a choice without a real level-up
	_build_ui()
	_build_board_host()
	_root.hide()
	if GameManager.has_signal("leveled_up"):
		GameManager.leveled_up.connect(_on_leveled_up)

# ── Authored Level-Up board (optional visual layout) ─────────────────────────────────────────────────
## Spawn a runtime-only board surface (CanvasLayer 99, below this UI's cards at 100) that renders the
## authored "levelup" board chrome. Hidden until a level-up shows. Its LevelUpBinder supplies role rects.
func _build_board_host() -> void:
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 99
	_board_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_board_layer.visible = false
	add_child(_board_layer)
	var oc := Control.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_layer.add_child(oc)
	_board_host = BoardEditScript.new()
	add_child(_board_host)
	_board_host.setup(oc, "levelup", false)   # runtime-only host (no authoring UI)

## The host's LevelUpBinder (exposes has_layout/has_role/role_rect), or null.
func _board_binder():
	if _board_host != null and is_instance_valid(_board_host):
		return _board_host.get_binder()
	return null

func _board_authored() -> bool:
	var b = _board_binder()
	return b != null and b.has_method("has_layout") and bool(b.call("has_layout"))

func _use_board() -> bool:
	return _board_authored()

## Re-read the board layout (picks up edits saved in the editor). Clears runtime nodes first so they don't
## linger across the host rebuild.
func _board_reload() -> void:
	_board_clear_all()
	if _board_host != null and is_instance_valid(_board_host):
		_board_host.reload()

## Toggle the authored board. Authored → hide the built-in full-screen panels (backdrop lets input through)
## and show the host chrome + a full-rect input/darken blocker. Not authored → keep the built-in UI.
func _board_show(v: bool) -> void:
	var authored := v and _board_authored()
	if _board_layer != null and is_instance_valid(_board_layer):
		_board_layer.visible = authored
	# Authored board fully replaces the built-in UI: HIDE _root, otherwise its full-rect Control (mouse
	# STOP, layer 100) swallows every click meant for the host's interactive nodes at layer 99. Input +
	# darkening are handled by the host blocker instead.
	if _root != null and is_instance_valid(_root):
		_root.visible = v and not authored
	if authored:
		_ensure_blocker()
	elif _board_blocker != null and is_instance_valid(_board_blocker):
		_board_blocker.visible = false

## Full-rect dark input blocker on the host container (behind the chrome): darkens gameplay + absorbs
## clicks that miss an interactive element, so nothing leaks to the paused game.
func _ensure_blocker() -> void:
	var b = _board_binder()
	if b == null:
		return
	var host_c = b.call("container")
	if host_c == null or not is_instance_valid(host_c):
		return
	if _board_blocker == null or not is_instance_valid(_board_blocker):
		_board_blocker = ColorRect.new()
		_board_blocker.color = Color(0.02, 0.03, 0.06, 0.97)
		_board_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
		_board_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		_board_blocker.z_index = -100
		host_c.add_child(_board_blocker)
	_board_blocker.visible = true

# ── Board render helpers ──────────────────────────────────────────────────────────────
func _board_clear(list: Array) -> void:
	for n in list:
		if n != null and is_instance_valid(n):
			n.queue_free()
	list.clear()

func _board_clear_all() -> void:
	_board_clear(_rt_choices); _board_clear(_rt_options); _board_clear(_rt_stats)
	_board_clear(_rt_updesc); _board_clear(_rt_display)

func _board_add(n: Control) -> void:
	var b = _board_binder()
	if b == null:
		return
	var c = b.call("container")
	if c != null and is_instance_valid(c):
		c.add_child(n)

func _node_rect(n) -> Rect2:
	if n == null or not is_instance_valid(n):
		return Rect2()
	return Rect2((n as Control).position, (n as Control).size)

## Weapon1-3: place each choice's weapon sprite centred on its WeaponFrame (WEAPON_SPRITE_MARGIN px smaller),
## with hover (brighten + 5% grow + uiclick) and click (uialert → select the item).
func _board_render_choices() -> void:
	_board_clear(_rt_choices)
	var b = _board_binder()
	if b == null:
		return
	for i in 3:
		_board_set_text(b.call("weapon_codename", i), "")   # blank unused slots' code name
	for i in mini(_slot_specs.size(), 3):
		var spec: Dictionary = _slot_specs[i]
		var frame = b.call("weapon_frame", i)
		if frame == null or not is_instance_valid(frame):
			continue
		var fc := frame as Control
		# Code name of this choice, centred on the "CodeName" indicator sprite if authored, else the WeaponFrame.
		var cn_ind = b.call("weapon_codename_ind", i)
		var cx := fc.position.x + fc.size.x * 0.5
		if cn_ind != null and is_instance_valid(cn_ind):
			cx = (cn_ind as Control).position.x + (cn_ind as Control).size.x * 0.5
		_board_set_text_cx(b.call("weapon_codename", i), String(spec.get("name", "")), cx)
		var node := _board_make_choice(fc, spec, int(spec["idx"]))
		_board_add(node)
		_rt_choices.append(node)
		# Ambient scan VFX on WeaponFrame + CodeName — green idle, red for the currently-selected slot.
		var wcol := SCAN_COLOR_RED if int(spec["idx"]) == _selected_idx else SCAN_COLOR_GREEN
		var wvfx := _board_make_icon_vfx(_node_rect(fc), fc.z_index + 1, wcol)
		_board_add(wvfx)
		_rt_choices.append(wvfx)
		if cn_ind != null and is_instance_valid(cn_ind):
			var cvfx := _board_make_name_vfx(_node_rect(cn_ind), (cn_ind as CanvasItem).z_index + 1, wcol)
			_board_add(cvfx)
			_rt_choices.append(cvfx)

func _board_make_choice(frame: Control, spec: Dictionary, idx: int) -> Control:
	var root := Control.new()
	root.position = frame.position
	root.size = frame.size
	root.pivot_offset = frame.size * 0.5     # hover scale grows from centre
	root.z_index = frame.z_index + 5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := (frame.size - Vector2(WEAPON_SPRITE_MARGIN, WEAPON_SPRITE_MARGIN)) * CHOICE_SPRITE_SCALE
	var def_id := String(spec.get("def", ""))
	var aux_id := String(spec.get("aux_id", ""))
	var tex: Texture2D = InventoryManager.get_icon(def_id) if def_id != "" else _aux_icon_tex(aux_id)
	var content: Control
	if tex != null:
		if aux_id != "":
			box = _contain_box(tex.get_size(), box.x, box.y)   # aux: CONTAIN both axes (weapon keeps its own margin box)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		content = tr
	else:
		var sw := ColorRect.new()
		sw.color = spec.get("color", Color.GRAY)
		content = sw
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size = box
	content.position = (frame.size - box) * 0.5
	root.add_child(content)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.mouse_entered.connect(func() -> void:
		root.scale = Vector2(1.05, 1.05)
		content.modulate = Color(1.35, 1.35, 1.35)
		_play_sfx("res://assets/audio/sfx/uiclick.wav"))
	btn.mouse_exited.connect(func() -> void:
		root.scale = Vector2.ONE
		content.modulate = Color.WHITE)
	btn.pressed.connect(func() -> void:
		_play_sfx("res://assets/audio/sfx/uialert.wav")
		_select_item(idx))
	root.add_child(btn)
	return root

## Codename=label, Full Name=name, Lore=WEAPON_INFO.lore (optional). Aux → codename=name only.
func _weapon_meta(c: Dictionary) -> Dictionary:
	var cat := String(c.get("cat", ""))
	if cat in ["weapon", "pool", "capstone"]:
		var kind := String(c.get("key", c.get("weapon", "")))
		var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
		return {"codename": String(info.get("label", c.get("name", ""))), "fullname": String(info.get("name", "")),
			"lore": String((ArenaWeapons.WEAPON_LORE as Dictionary).get(kind, "")), "def_id": String(c.get("def_id", info.get("def_id", "")))}
	if cat == "fusion":
		var fkind := String(c.get("key", ""))
		var rec: Dictionary = (ArenaWeapons.FUSION_DEFS as Dictionary).get(fkind, {})
		return {"codename": String(rec.get("label", c.get("name", ""))), "fullname": String(c.get("name", "")),
			"lore": String((ArenaWeapons.WEAPON_LORE as Dictionary).get(fkind, "")), "def_id": String(c.get("def_id", ""))}
	return {"codename": String(c.get("name", "")), "fullname": "", "lore": "", "def_id": String(c.get("def_id", ""))}

## WeaponDisplay: big weapon sprite on the frame + Codename/Full Name/Item Lore. All hidden with no selection.
func _board_render_selected() -> void:
	var b = _board_binder()
	if b == null:
		return
	_board_clear(_rt_display)
	# MainDisplay: ambient black scan VFX, always on — not tied to any selection state.
	var main_disp = b.call("main_display")
	if main_disp != null and is_instance_valid(main_disp):
		var mvfx := _board_make_icon_vfx(_node_rect(main_disp), (main_disp as CanvasItem).z_index + 1, SCAN_COLOR_BLACK)
		_board_add(mvfx)
		_rt_display.append(mvfx)
	var cn = b.call("display_codename")
	var fn = b.call("display_fullname")
	var lr = b.call("display_lore")
	if _selected_idx < 0 or _selected_idx >= _choices.size():
		_board_set_text(cn, ""); _board_set_text(fn, ""); _board_set_text(lr, "")
		return
	var sel_c: Dictionary = _choices[_selected_idx]
	var info := _weapon_meta(sel_c)   # Codename/Full Name/Lore text ALWAYS reflect the top-level pick
	# The SPRITE, though, follows whichever Upgrade1-3 card was last CLICKED (_pending_pick_idx) — clicking
	# an option (e.g. a perk) pushes ITS icon here, replacing the top-level pick's icon. Falls back to the
	# top-level pick's own icon when nothing's been clicked yet (unchanged from before).
	var icon_c := sel_c
	if _pending_pick_idx >= 0 and _pending_pick_idx < _current.size():
		icon_c = _current[_pending_pick_idx]
	# WeaponDisplay centre X (frame if present, else the group) — codename/full name centre on it.
	var disp_cx := 0.0
	var frame = b.call("display_frame")
	if frame != null and is_instance_valid(frame):
		var fc := frame as Control
		disp_cx = fc.position.x + fc.size.x * 0.5
		var icon_def_id := String(icon_c.get("def_id", ""))
		var box := fc.size - Vector2(WEAPON_SPRITE_MARGIN, WEAPON_SPRITE_MARGIN)
		var tex := _option_icon_tex(icon_c)
		if tex != null:
			if icon_def_id == "":
				box = _contain_box(tex.get_size(), box.x, box.y)   # aux: CONTAIN both axes (weapon keeps its own margin box)
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.size = box
			tr.position = fc.position + (fc.size - box) * 0.5
			tr.z_index = (frame as CanvasItem).z_index + 5
			_board_add(tr)
			_rt_display.append(tr)
		else:
			# No art at all (neither the clicked option's own icon nor its parent aux's) → colour swatch.
			var sw := ColorRect.new()
			sw.color = icon_c.get("color", Color.GRAY)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sw.size = box
			sw.position = fc.position + (fc.size - box) * 0.5
			sw.z_index = (frame as CanvasItem).z_index + 5
			_board_add(sw)
			_rt_display.append(sw)
	else:
		var dgr: Rect2 = b.call("group_rect", "WeaponDisplay")
		disp_cx = dgr.position.x + dgr.size.x * 0.5
	_board_set_text_cx(cn, String(info.get("codename", "")), disp_cx)
	_board_set_text_cx(fn, String(info.get("fullname", "")), disp_cx)
	# Item Lore: wrap inside the LoreDisplay indicator's box (runtime label; hide the authored template text).
	_board_set_vis(lr, false)
	var lore := String(info.get("lore", ""))
	if lore != "":
		var lframe = b.call("display_lore_frame")
		var rect := Rect2()
		var lz := 260
		if lframe != null and is_instance_valid(lframe):
			rect = _node_rect(lframe)
			lz = (lframe as CanvasItem).z_index + 6
		elif lr != null and is_instance_valid(lr):
			rect = _node_rect(lr)   # fallback: the Item Lore text's own rect
			lz = (lr as CanvasItem).z_index + 6
		if rect.size.x > 1.0:
			var lore_lbl := _make_wrapped_label(rect, b.call("display_lore_style"), lore, lz, VERTICAL_ALIGNMENT_CENTER)
			if lore_lbl != null:
				_rt_display.append(lore_lbl)

func _board_set_text(node, s: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("set_text_value"):
		node.call("set_text_value", s)
	(node as CanvasItem).visible = s != ""

## Set an authored text node's value + visibility, then re-centre it horizontally on center_x (+ off_x),
## keeping its Y.
func _board_set_text_cx(node, s: String, center_x: float, off_x: float = 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("set_text_value"):
		node.call("set_text_value", s)
	var c := node as Control
	c.visible = s != ""
	if s != "":
		c.position.x = center_x - c.size.x * 0.5 + off_x

## Upgrade1-3: fill from _current (1..N options, extras hidden). prompt=true → the pre-selection state
## ("Select Weapon" in each name, no click targets). Clicking a card only PREVIEWS it (_select_option):
## highlight ring + UpgradeDesc text + Weapon Stat deltas. The authored Confirm button (_board_render_confirm)
## is what actually commits the pending pick — folded in here so every options render keeps it in sync.
func _board_render_options(prompt: bool = false) -> void:
	var b = _board_binder()
	if b == null:
		return
	_board_clear(_rt_options)
	var n := 0 if prompt else _current.size()
	for i in 3:
		# Hide the authored template texts (runtime wrapped labels / icon replace them).
		_board_set_vis(b.call("upg_name_text", i), false)
		_board_set_vis(b.call("upg_icon_text", i), false)
		var name_ind = b.call("upg_name_ind", i)
		var icon_ind = b.call("upg_icon_ind", i)
		if prompt:
			var pl := _board_wrapped(name_ind, b.call("upg_name_text", i), b.call("upg_name_style", i), "Select Weapon")
			if pl != null:
				_rt_options.append(pl)
			# Ambient green VFX runs even before any option is offered (no pending pick possible yet → never red).
			if icon_ind != null and is_instance_valid(icon_ind):
				var pivfx := _board_make_icon_vfx(_node_rect(icon_ind), (icon_ind as CanvasItem).z_index + 1, SCAN_COLOR_GREEN)
				_board_add(pivfx)
				_rt_options.append(pivfx)
			if name_ind != null and is_instance_valid(name_ind):
				var pnvfx := _board_make_name_vfx(_node_rect(name_ind), (name_ind as CanvasItem).z_index + 1, SCAN_COLOR_GREEN)
				_board_add(pnvfx)
				_rt_options.append(pnvfx)
			continue
		if i >= n:
			# Fewer than 3 options this screen (pool ran dry, etc.) — empty slot: black ambient VFX, same
			# treatment as MainDisplay/StatDisplay for "not a selectable item" (SCAN_COLOR_BLACK).
			if icon_ind != null and is_instance_valid(icon_ind):
				var bivfx := _board_make_icon_vfx(_node_rect(icon_ind), (icon_ind as CanvasItem).z_index + 1, SCAN_COLOR_BLACK)
				_board_add(bivfx)
				_rt_options.append(bivfx)
			if name_ind != null and is_instance_valid(name_ind):
				var bnvfx := _board_make_name_vfx(_node_rect(name_ind), (name_ind as CanvasItem).z_index + 1, SCAN_COLOR_BLACK)
				_board_add(bnvfx)
				_rt_options.append(bnvfx)
			continue
		var c: Dictionary = _current[i]
		var slot_labels: Array = []
		var name_lbl := _board_wrapped(name_ind, b.call("upg_name_text", i), b.call("upg_name_style", i), String(c.get("name", "")))
		if name_lbl != null:
			_rt_options.append(name_lbl); slot_labels.append(name_lbl)
		if icon_ind != null and is_instance_valid(icon_ind):
			var icon_node := _board_make_option_icon(icon_ind as Control, c)
			_board_add(icon_node)
			_rt_options.append(icon_node); slot_labels.append(icon_node)
		var rect := _node_rect(name_ind).merge(_node_rect(icon_ind)) if name_ind != null and icon_ind != null else _node_rect(name_ind if name_ind != null else icon_ind)
		# Ambient scan VFX on UpgradeIcon + UpgradeName separately — green idle, red for the pending pick.
		var ucol := SCAN_COLOR_RED if i == _pending_pick_idx else SCAN_COLOR_GREEN
		if icon_ind != null and is_instance_valid(icon_ind):
			var ivfx := _board_make_icon_vfx(_node_rect(icon_ind), (icon_ind as CanvasItem).z_index + 1, ucol)
			_board_add(ivfx)
			_rt_options.append(ivfx)
		if name_ind != null and is_instance_valid(name_ind):
			var nvfx := _board_make_name_vfx(_node_rect(name_ind), (name_ind as CanvasItem).z_index + 1, ucol)
			_board_add(nvfx)
			_rt_options.append(nvfx)
		if rect.size.x > 1.0:
			var btn := _board_click(rect, i, slot_labels)
			_board_add(btn)
			_rt_options.append(btn)
	_board_render_updesc()
	_board_render_stats()
	_board_render_confirm()

## Centred icon/swatch for an Upgrade1-3 card, sized into its UpgradeIcon indicator rect. Weapon cards (new/
## capstone/fusion, and pool-perk cards that have no dedicated icon) keep the frame-margin box (same rule as
## the left-column choice sprites) — pool-perk cards (cat "pool") try their OWN icon (WEAPON_PERK_ICON_DIR)
## first, falling back to the parent weapon's icon. Aux cards (their own pick, a skill-point perk, or an
## evolve capstone under them) CONTAIN-fit within AUX_ICON_SCALE (80%) of the indicator's width AND height
## (aspect kept, neither dimension exceeds 80%), centred in the rect. Aux pool-perk cards (cat "aux_pool")
## try their OWN icon (PERK_ICON_DIR, filename = the perk's own id, e.g. "regen_shield") first, falling back
## to the parent aux's icon, then a colour-swatch if neither exists.
func _board_make_option_icon(frame: Control, c: Dictionary) -> Control:
	var def_id := String(c.get("def_id", ""))
	var color: Color = c.get("color", Color.GRAY)
	var content: Control
	var box: Vector2
	if def_id != "":
		box = frame.size - Vector2(WEAPON_SPRITE_MARGIN, WEAPON_SPRITE_MARGIN)
		var wtex := _option_icon_tex(c)   # weapon-perk icon for "pool" cards, else the weapon's own icon
		if wtex != null:
			var wtr := TextureRect.new()
			wtr.texture = wtex
			wtr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			wtr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			wtr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content = wtr
		else:
			var wsw := ColorRect.new()
			wsw.color = color
			wsw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content = wsw
	else:
		var max_w := frame.size.x * AUX_ICON_SCALE
		var max_h := frame.size.y * AUX_ICON_SCALE
		var tex: Texture2D = null
		if String(c.get("cat", "")) == "aux_pool":
			tex = _perk_icon_tex(String(c.get("key", "")))
		if tex == null:
			tex = _aux_icon_tex(_aux_id_for(c))
		if tex != null:
			var fit := _fit_texture_rect(tex, max_w, max_h)
			box = fit["box"]
			content = fit["control"]
		else:
			box = Vector2(max_w, max_h)
			var sw := ColorRect.new()
			sw.color = color
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content = sw
	content.size = box
	content.position = frame.position + (frame.size - box) * 0.5
	content.z_index = (frame as CanvasItem).z_index + 5
	return content

## Ambient VFX for the level-up board — runs on EVERY cell continuously, not just the selected one. Colour
## communicates state: green = idle, red = this cell is the currently-selected one (_selected_idx /
## _pending_pick_idx), black = MainDisplay/StatDisplay (not a selectable item, always the same colour).
## Two cell "kinds":
##  - Icon cells (WeaponFrame / UpgradeIcon / MainDisplay / StatDisplay): scan+noise+border (shared/cached
##    material per colour — these don't need per-instance variation) + an additive sweep band. The sweep
##    material is ALWAYS per-instance with a randomised speed + start phase, so multiple cells never sweep
##    in lockstep.
##  - Name-plate cells (CodeName / UpgradeName): scan+noise+border only, no sweep — instead a gentle
##    breathing flicker (also per-instance randomised phase/speed) via the same shader's flicker uniforms.
const SCAN_SHADER := "res://assets/shaders/selection_scan.gdshader"
const SWEEP_SHADER := "res://assets/shaders/selection_sweep.gdshader"
const SCAN_COLOR_GREEN := Color(0.35, 1.0, 0.45, 0.5)    # idle (not selected) — 50% opacity
const SCAN_COLOR_RED := Color(1.0, 0.30, 0.30, 1.0)
const SCAN_COLOR_BLACK := Color(0.15, 0.15, 0.15, 1.0)   # MainDisplay/StatDisplay — +10% brightness over near-black
const NAME_FLICKER_STRENGTH := 0.30
var _scan_mats: Dictionary = {}    # Color → ShaderMaterial (selection_scan.gdshader, flicker off)

## Shared/cached scan+noise+border material for icon cells (no flicker) — identical look, no need to desync.
func _scan_material(color: Color) -> ShaderMaterial:
	if not _scan_mats.has(color):
		var m := ShaderMaterial.new()
		m.shader = load(SCAN_SHADER) as Shader
		m.set_shader_parameter("scan_color", color)
		_scan_mats[color] = m
	return _scan_mats[color]

## Per-instance scan+noise+border material WITH a gentle flicker (name-plate cells) — unique per call so
## each cell's flicker phase/speed differs and they never pulse in unison.
func _flicker_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SCAN_SHADER) as Shader
	m.set_shader_parameter("scan_color", color)
	m.set_shader_parameter("flicker_strength", NAME_FLICKER_STRENGTH)
	m.set_shader_parameter("flicker_speed", randf_range(1.6, 2.8))
	m.set_shader_parameter("flicker_phase", randf() * 20.0)
	return m

## Per-instance sweep material — always randomised (speed ±25%, start phase random) so icon cells' sweep
## bands never sync up even though they share a colour.
func _sweep_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SWEEP_SHADER) as Shader
	m.set_shader_parameter("sweep_color", color)
	m.set_shader_parameter("sweep_speed", 0.35 * randf_range(0.75, 1.25))
	m.set_shader_parameter("time_offset", randf() * 20.0)
	return m

## `z` is the z_index of the frame/icon node this VFX sits on top of — callers pass frame.z_index + 1 (or the
## icon indicator's) so the VFX always draws just above ITS OWN cell but stays below the "Frame" board-chrome
## group (authored above every cell group in the editor's group order), matching the layering the frame art
## is meant to have over the scan effect.
func _board_make_icon_vfx(rect: Rect2, z: int, color: Color) -> Control:
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = z
	var scan := ColorRect.new()
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.color = Color.WHITE
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.material = _scan_material(color)
	root.add_child(scan)
	var sweep := ColorRect.new()
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.color = Color.WHITE
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.z_index = 1   # relative to root (z_as_relative defaults true) — draws just above the scan layer
	sweep.material = _sweep_material(color)
	root.add_child(sweep)
	return root

## Name-plate cell (CodeName / UpgradeName): scan+noise+border only, no sweep, gentle randomised flicker.
func _board_make_name_vfx(rect: Rect2, z: int, color: Color) -> Control:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = z
	r.material = _flicker_material(color)
	return r

## Click a card: SELECT it — VFX turns red, its sprite is pushed onto WeaponDisplay (replacing whatever's
## shown), UpgradeDesc/stat deltas show it. Does not apply/commit yet, Confirm does that. Mirrors weapon-
## icon's click-to-select (_select_item); hover-only preview is _hover_option, below.
func _select_option(idx: int) -> void:
	if idx < 0 or idx >= _current.size():
		return
	_hover_preview_idx = idx   # a click also counts as "previewing" it, keep desc/stats in sync
	if idx == _pending_pick_idx:
		return
	_pending_pick_idx = idx
	_board_render_options()
	_board_render_selected()   # push the clicked option's sprite onto WeaponDisplay

## Hover a card: PREVIEW only — UpgradeDesc + stat deltas update to show it. No VFX colour change and no
## WeaponDisplay swap (those are click-only, see _select_option) — matches weapon-icon's hover, which is
## pure-visual (grow) and never changes what's selected.
func _hover_option(idx: int) -> void:
	if idx < 0 or idx >= _current.size() or idx == _hover_preview_idx:
		return
	_hover_preview_idx = idx
	_board_render_updesc()
	_board_render_stats()

## Single UpgradeDesc box: the currently-selected (pending confirm) option's text, split into 3 coloured
## parts — stat/effect number (white), rank/level (red), flavour trivia (yellow) — wrapped inside the
## "UpgradeDesc" indicator's rect, same placement pattern as LoreDisplay (indicator hidden, runtime shown).
func _board_render_updesc() -> void:
	var b = _board_binder()
	if b == null:
		return
	_board_clear(_rt_updesc)
	_board_set_vis(b.call("updesc_text"), false)
	if _hover_preview_idx < 0 or _hover_preview_idx >= _current.size():
		return
	var c: Dictionary = _current[_hover_preview_idx]
	var parts := _updesc_parts(c)
	var lines: Array = []
	if String(parts["stat"]) != "":
		lines.append("[color=#ffffff]%s[/color]" % String(parts["stat"]))
	if String(parts["rank"]) != "":
		lines.append("[color=#ff4444]%s[/color]" % String(parts["rank"]))
	if String(parts["trivia"]) != "":
		lines.append("[color=#ffd23f]%s[/color]" % String(parts["trivia"]))
	if lines.is_empty():
		return
	var ind = b.call("updesc_ind")
	var rect := _node_rect(ind)
	var z := ((ind as CanvasItem).z_index + 6) if ind != null and is_instance_valid(ind) else 250
	if rect.size.x <= 1.0:
		return
	var style: Dictionary = b.call("updesc_style")
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = false
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", maxi(1, int(style.get("font_size", 24)) - 4))
	var font := _font_from(style)
	if font != null:
		rtl.add_theme_font_override("normal_font", font)
	rtl.text = "\n\n".join(lines)   # blank line between stat/rank/trivia so the 3 parts read as separate blocks
	rtl.position = rect.position
	rtl.size = rect.size
	rtl.z_index = z
	_board_add(rtl)
	_rt_updesc.append(rtl)
	# Vertical centring: RichTextLabel has no built-in vertical_alignment, so measure the wrapped content
	# and re-centre the box in `rect` (only when shorter than the box — never push it above/overflow).
	var ch := rtl.get_content_height()
	if ch > 0.0 and ch < rect.size.y:
		rtl.position.y = rect.position.y + (rect.size.y - ch) * 0.5

## Split a choice's description into {stat, rank, trivia} for the 3-coloured UpgradeDesc box. Mirrors
## _default_text's branches (same source fields), just kept separate instead of concatenated into one string.
func _updesc_parts(c: Dictionary) -> Dictionary:
	var lvl := int(c.get("level", 0))
	var action := String(c.get("action", ""))
	var cat := String(c.get("cat", ""))
	if action == "capstone" or action == "destroy":
		return {"stat": String(c.get("effect", "")), "rank": "", "trivia": ""}
	if cat == "weapon" and not _weapon_pool(String(c.get("key", ""))).is_empty():
		return {"stat": "", "rank": ("NEW" if action == "new" else "Lv %d" % lvl), "trivia": "pick a perk"}
	if cat == "aux" and not _aux_pool(String(c.get("key", ""))).is_empty():
		return {"stat": "", "rank": ("NEW" if action == "new" else "Lv %d" % lvl), "trivia": "pick a perk"}
	if action == "pool":
		var rank := int(c.get("rank", 0))
		var maxr := int(c.get("maxr", 0))
		var rt := ("Rank %d/%d" % [rank, maxr]) if maxr > 0 else ("Rank %d" % rank)
		return {"stat": String(c.get("effect", "")), "rank": rt, "trivia": String(c.get("desc", ""))}
	if action == "fuse":
		return {"stat": String(c.get("effect", "FUSE")), "rank": "", "trivia": ""}
	if action == "new":
		var stat := "" if cat == "weapon" else String(c.get("effect", ""))
		return {"stat": stat, "rank": "NEW", "trivia": ""}
	# upgrade (simple leveled aux/weapon)
	return {"stat": String(c.get("effect", "")), "rank": "Lv %d → %d" % [lvl, lvl + 1], "trivia": ""}

## Confirm button (2-state sprite: "confirm" normal / "confirmpress" pressed). Commits whichever card is
## currently pending (_pending_pick_idx) via _pick() — which already applies the choice, plays
## selectconfirm3.wav, and closes/advances the board. No-op while nothing is selected.
func _board_render_confirm() -> void:
	var b = _board_binder()
	if b == null:
		return
	var on = b.call("confirm_normal")
	var press = b.call("confirm_press")
	_board_set_vis(on, true)
	_board_set_vis(press, false)
	if on == null or not is_instance_valid(on):
		return
	var rect := _node_rect(on)
	if rect.size.x <= 1.0:
		return
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = rect.position
	btn.size = rect.size
	btn.z_index = (on as CanvasItem).z_index + 5
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	# Hover: swap to the confirmpress sprite (so it's already showing well before any click). Click: just
	# play the confirm sfx + apply/close — no artificial delay needed since the pressed art has been
	# visible since hover, not swapped in the same frame as the close.
	btn.mouse_entered.connect(func() -> void:
		_board_set_vis(on, false)
		_board_set_vis(press, true)
		_play_sfx("res://assets/audio/sfx/uiclick.wav"))
	btn.mouse_exited.connect(func() -> void:
		_board_set_vis(on, true)
		_board_set_vis(press, false))
	btn.pressed.connect(func() -> void:
		if _pending_pick_idx < 0 or _pending_pick_idx >= _current.size():
			return
		btn.disabled = true   # swallow extra clicks
		_pick(_pending_pick_idx))
	_board_add(btn)
	_rt_options.append(btn)

func _board_set_vis(node, v: bool) -> void:
	if node != null and is_instance_valid(node):
		(node as CanvasItem).visible = v

## Core: a horizontally-centred, wrapped runtime Label filling `rect`, styled from an authored text child
## dict (font/size/color/outline). Returns the label (caller tracks + frees it).
func _make_wrapped_label(rect: Rect2, style: Dictionary, text: String, z: int, valign: int = VERTICAL_ALIGNMENT_CENTER) -> Label:
	if text == "" or rect.size.x <= 1.0:
		return null
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = valign
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", int(style.get("font_size", 16)))
	var font := _font_from(style)
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_color_override("font_color", style.get("color", Color.WHITE))
	if int(style.get("outline_size", 0)) > 0:
		lbl.add_theme_constant_override("outline_size", int(style.get("outline_size", 0)))
		lbl.add_theme_color_override("font_outline_color", style.get("outline_color", Color.BLACK))
	lbl.position = rect.position
	lbl.size = rect.size
	lbl.z_index = z
	_board_add(lbl)
	return lbl

## Upgrade name/desc: a centred wrapped label at the indicator sprite's rect (wrap width = indicator
## width, always centred on it). Falls back to the template text node's rect if no indicator. Returns the
## label so the caller can wire hover-scale.
func _board_wrapped(ind, template_node, style: Dictionary, text: String) -> Label:
	var rect := _node_rect(ind) if ind != null and is_instance_valid(ind) else _node_rect(template_node)
	var z := ((ind as CanvasItem).z_index + 6) if ind != null and is_instance_valid(ind) else 250
	return _make_wrapped_label(rect, style, text, z)

func _font_from(style: Dictionary) -> Font:
	var fname := String(style.get("font", ""))
	if fname != "":
		for ext: String in ["ttf", "otf", "fnt"]:
			var p := "res://assets/fonts/" + fname + "." + ext
			if ResourceLoader.exists(p):
				return load(p) as Font
	return load(FONT_PATH) as Font

func _board_click(rect: Rect2, idx: int, labels: Array = []) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = rect.position
	btn.size = rect.size
	btn.z_index = 300
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	# Hover: enlarge the slot's icon/text 5% (from centre) + uiclick + preview UpgradeDesc/stat deltas
	# (_hover_option — no VFX colour change, no WeaponDisplay swap). Click: _select_option actually selects
	# it (VFX red + WeaponDisplay swap) — same hover/click split as the weapon-icon Weapon1-3 cards.
	btn.mouse_entered.connect(func() -> void:
		for l in labels:
			if l != null and is_instance_valid(l):
				(l as Control).pivot_offset = (l as Control).size * 0.5
				(l as Control).scale = Vector2(1.05, 1.05)
		_play_sfx("res://assets/audio/sfx/uiclick.wav")
		_hover_option(idx))
	btn.mouse_exited.connect(func() -> void:
		for l in labels:
			if l != null and is_instance_valid(l):
				(l as Control).scale = Vector2.ONE)
	btn.pressed.connect(_select_option.bind(idx))
	return btn

## StatDisplay: replace the "Weapon Stat" text with the curated stats list (reuses _fill_stat_rows).
func _board_render_stats() -> void:
	var b = _board_binder()
	if b == null:
		return
	_board_clear(_rt_stats)
	# StatDisplay: ambient black scan VFX, always on — not tied to any selection state.
	var stat_disp = b.call("stat_display_ind")
	if stat_disp != null and is_instance_valid(stat_disp):
		var svfx := _board_make_icon_vfx(_node_rect(stat_disp), (stat_disp as CanvasItem).z_index + 1, SCAN_COLOR_BLACK)
		_board_add(svfx)
		_rt_stats.append(svfx)
	var anchor = b.call("stat_text")
	if anchor == null or not is_instance_valid(anchor):
		return
	(anchor as CanvasItem).visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.scale = Vector2(0.8, 0.8)   # stats shown at 80% size (per request)
	var gr: Rect2 = b.call("group_rect", "StatDisplay")
	if gr.size.x > 1.0:
		vb.position = gr.position
		vb.custom_minimum_size = Vector2(gr.size.x / 0.8, 0.0)   # pre-scale width so the 80% result fits the group
		vb.size = Vector2(gr.size.x / 0.8, gr.size.y)
	else:
		vb.position = (anchor as Control).position
	vb.position.y += 100.0   # shift the stats list down 100px (per request)
	vb.z_index = (anchor as CanvasItem).z_index + 6
	var preview := {}
	if _hover_preview_idx >= 0 and _hover_preview_idx < _current.size():
		preview = _preview_map(_current[_hover_preview_idx])
	_fill_stat_rows(vb, preview)
	_board_add(vb)
	_rt_stats.append(vb)

## Stat deltas for a choice dict, keyed by row id (row → {row, amt, pct}). Only aux items are mapped (see
## AUX_TOP_DELTAS / AUX_POOL_DELTAS) — weapon perks mostly land on per-weapon or per-family mechs that don't
## correspond 1:1 to a curated global row, so showing a number there would be a guess, not a fact.
func _preview_map(c: Dictionary) -> Dictionary:
	var out := {}
	var cat := String(c.get("cat", ""))
	var deltas: Array = []
	if cat == "aux":
		deltas = (AUX_TOP_DELTAS as Dictionary).get(String(c.get("key", "")), [])
	elif cat == "aux_pool":
		var m: Dictionary = (AUX_POOL_DELTAS as Dictionary).get(String(c.get("aux", "")), {})
		deltas = m.get(String(c.get("key", "")), [])
	for d: Dictionary in deltas:
		out[String(d["row"])] = d
	return out

func _on_leveled_up(_level: int) -> void:
	_pending += 1
	if not _showing:
		_begin()

## Grant ONE level-up choice (the pick-1-of-3 card) WITHOUT changing the player's level/XP. Used by reward chests.
func grant_reward() -> void:
	_pending += 1
	if not _showing:
		_begin()

func _begin() -> void:
	_showing = true
	get_tree().paused = true
	_board_reload()   # refresh the authored chrome + lay boxes out from its role rects
	_show_cards()

func _show_cards() -> void:
	_choices = _generate_choices(CHOICES)
	_route_cache.clear()   # freeze this level-up's perk options
	if _choices.is_empty():
		# Nothing left to offer (everything owned + maxed) — silently skip this level-up.
		_pending -= 1
		if _pending > 0:
			_show_cards()
		else:
			_finish()
		return
	_title.text = "LEVEL UP — choose an item"
	_options_back = false
	_render_left()
	_refresh_stats()
	_root.show()
	_board_show(true)
	_play_sfx("res://assets/audio/sfx/uialert.wav")
	if _use_board():
		# Authored board: render the 3 choices + stats, and wait for a weapon click ("Select Weapon" prompt).
		_selected_idx = -1
		_pending_pick_idx = -1
		_hover_preview_idx = -1
		_board_render_choices()
		_board_render_selected()
		_board_render_options(true)   # also renders stats/UpgradeDesc/Confirm (folded in)
	else:
		_select_item(0)

## Resolve the aux id a card dict refers to — top-level pick ("aux"), a skill-point pool perk under one
## ("aux_pool", parent id in "aux"), or an evolve capstone ("capstone" + is_aux, parent id in "weapon").
## "" for weapon/pool/capstone/fusion cards. Pool perks and capstones show their PARENT aux's icon (they
## have no per-perk art of their own — same as they already share the parent's colour swatch).
func _aux_id_for(c: Dictionary) -> String:
	var cat := String(c.get("cat", ""))
	if cat == "aux":
		return String(c.get("key", ""))
	if cat == "aux_pool":
		return String(c.get("aux", ""))
	if cat == "capstone" and bool(c.get("is_aux", false)):
		return String(c.get("weapon", ""))
	return ""

## Cached aux icon (AUX_ICON_DIR + id + ".png"), or null if that id has no art yet.
func _aux_icon_tex(id: String) -> Texture2D:
	if id == "":
		return null
	if _aux_icon_cache.has(id):
		return _aux_icon_cache[id]
	var path := AUX_ICON_DIR + id + ".png"
	var tex: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	_aux_icon_cache[id] = tex
	return tex

## Cached raw perk icon (PERK_ICON_DIR + id + ".png"), or null if that perk has no art yet — capstones and
## some pool perks (see the level-up docstring listing) still fall back to their parent aux's icon.
func _perk_icon_tex(id: String) -> Texture2D:
	if id == "":
		return null
	if _perk_icon_cache.has(id):
		return _perk_icon_cache[id]
	var path := PERK_ICON_DIR + id + ".png"
	var tex: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	_perk_icon_cache[id] = tex
	return tex

## Cached weapon skill-point pool perk icon (WEAPON_PERK_ICON_DIR + WEAPON_PERK_FOLDER[kind] + "/" + perk_id +
## ".png", falling back to WEAPON_PERK_ID_ALIAS[perk_id] as the filename if the exact id has no file) — null
## if that weapon has no perk-icon folder, or this specific perk has no art (weapon capstones + any weapon
## with no folder yet fall back to the parent weapon's own icon, same as before this art pass).
func _weapon_perk_icon_tex(kind: String, perk_id: String) -> Texture2D:
	if kind == "" or perk_id == "" or not WEAPON_PERK_FOLDER.has(kind):
		return null
	var cache_key := kind + "/" + perk_id
	if _weapon_perk_icon_cache.has(cache_key):
		return _weapon_perk_icon_cache[cache_key]
	var dir := WEAPON_PERK_ICON_DIR + String(WEAPON_PERK_FOLDER[kind]) + "/"
	var fname := String(WEAPON_PERK_ID_ALIAS.get(perk_id, perk_id))
	var path := dir + fname + ".png"
	var tex: Texture2D = (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	_weapon_perk_icon_cache[cache_key] = tex
	return tex

## Resolve the icon texture for ANY level-up card dict — weapon pool perks (cat "pool") prefer their OWN icon
## (WEAPON_PERK_ICON_DIR) before falling back to the parent weapon's; other weapon cards (new/capstone/
## fusion) via InventoryManager (def_id); aux/aux_pool/capstone via _aux_id_for, with aux_pool perks
## preferring their OWN icon (PERK_ICON_DIR) before falling back to the parent aux's. Shared by the
## Upgrade1-3 option icon and the WeaponDisplay icon-swap-on-click (_board_render_selected) so both agree on
## what a card's icon is.
func _option_icon_tex(c: Dictionary) -> Texture2D:
	var cat := String(c.get("cat", ""))
	if cat == "pool":
		var wtex := _weapon_perk_icon_tex(String(c.get("weapon", "")), String(c.get("key", "")))
		if wtex != null:
			return wtex
	var def_id := String(c.get("def_id", ""))
	if def_id != "":
		return InventoryManager.get_icon(def_id)
	var tex2: Texture2D = null
	if cat == "aux_pool":
		tex2 = _perk_icon_tex(String(c.get("key", "")))
	if tex2 == null:
		tex2 = _aux_icon_tex(_aux_id_for(c))
	return tex2

## CONTAIN-fit box (aspect kept) for `native` within (max_w × max_h) — neither dimension exceeds the box (the
## tighter axis wins). Pure math, no resampling: aux/perk icons render through the SAME GPU stretch as weapon
## icons (EXPAND_IGNORE_SIZE + STRETCH_KEEP_ASPECT_CENTERED, see _fit_texture_rect) — a CPU Image.resize() was
## tried here first but looked visibly softer in-game than the weapon icons' GPU stretch at a similar or
## larger downscale ratio, so this project's proven-sharp path for big source art is the GPU one, not CPU.
func _contain_box(native: Vector2, max_w: float, max_h: float) -> Vector2:
	var s := minf(max_w / native.x, max_h / native.y)
	return native * s

## A GPU-stretched TextureRect showing `tex` CONTAIN-fit within (max_w × max_h) — identical setup to the
## weapon-icon TextureRects elsewhere in this file. Returns {control, box} (box = the actual on-screen size,
## for the caller's centring math).
func _fit_texture_rect(tex: Texture2D, max_w: float, max_h: float) -> Dictionary:
	var box := _contain_box(tex.get_size(), max_w, max_h)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = box
	return {"control": tr, "box": box}

## A centered sprite for a weapon/fusion def_id or an aux id, or a colour swatch fallback (missing art).
## The TextureRect keeps the texture's aspect (never stretched).
func _sprite_or_swatch(def_id: String, color: Color, aux_id: String = "") -> Control:
	var tex: Texture2D = InventoryManager.get_icon(def_id) if def_id != "" else _aux_icon_tex(aux_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var sw := ColorRect.new()
	sw.color = color
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sw

## Fill the 3 left slots from _choices. A fusion choice expands into its two source weapons (slots 0 & 1).
func _render_left() -> void:
	for slot: Control in _slot_nodes:
		for c in slot.get_children():
			c.free()
		slot.visible = false
	# Find a fusion (if any) — it claims slots 0 & 1 with the two source weapons.
	var fusion: Dictionary = {}
	var rest: Array = []
	for c: Dictionary in _choices:
		if String(c.get("cat", "")) == "fusion" and fusion.is_empty():
			fusion = c
		else:
			rest.append(c)
	var slot_specs: Array = []   # each: {def, name, color, idx (into _choices), fusion}
	if not fusion.is_empty():
		slot_specs.append({"def": String(fusion.get("def_a", "")), "name": fusion["name"], "color": fusion.get("color", Color.GRAY), "idx": _choices.find(fusion), "fusion": true})
		slot_specs.append({"def": String(fusion.get("def_b", "")), "name": fusion["name"], "color": fusion.get("color", Color.GRAY), "idx": _choices.find(fusion), "fusion": true})
	for c: Dictionary in rest:
		if slot_specs.size() >= 3:
			break
		slot_specs.append({"def": String(c.get("def_id", "")), "name": c["name"], "color": c.get("color", Color.GRAY), "idx": _choices.find(c), "fusion": false, "aux_id": _aux_id_for(c)})
	_slot_specs = slot_specs   # shared with the authored-board renderer
	for i in mini(slot_specs.size(), 3):
		_make_slot(_slot_nodes[i], slot_specs[i])

func _make_slot(slot: Control, spec: Dictionary) -> void:
	slot.visible = true
	var idx := int(spec["idx"])
	var is_fusion := bool(spec["fusion"])
	# Centered sprite (upper band of the slot).
	var spr := _sprite_or_swatch(String(spec["def"]), spec.get("color", Color.GRAY), String(spec.get("aux_id", "")))
	spr.anchor_left = 0.12; spr.anchor_right = 0.88
	spr.anchor_top = 0.08; spr.anchor_bottom = 0.66
	slot.add_child(spr)
	# Name label (lower band).
	var lbl := Label.new()
	lbl.text = String(spec["name"])
	lbl.add_theme_font_override("font", load(FONT_PATH))
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.anchor_left = 0.04; lbl.anchor_right = 0.96
	lbl.anchor_top = 0.70; lbl.anchor_bottom = 0.96
	slot.add_child(lbl)
	# Click target.
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(_select_item.bind(idx))
	slot.add_child(btn)
	# Fusion source boxes get a yellow ring + a rainbow pulse.
	if is_fusion:
		var sb := slot.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			var sb2 := sb.duplicate() as StyleBoxFlat
			sb2.set_border_width_all(3)
			sb2.border_color = RING_COL
			slot.add_theme_stylebox_override("panel", sb2)
			var pulse := slot.create_tween().set_loops()
			pulse.tween_property(slot, "modulate", Color(1.4, 0.7, 1.4), 0.5).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(slot, "modulate", Color(0.7, 1.4, 1.4), 0.5).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(slot, "modulate", Color(1.4, 1.4, 0.7), 0.5).set_trans(Tween.TRANS_SINE)

func _select_item(idx: int) -> void:
	if idx < 0 or idx >= _choices.size():
		return
	_selected_idx = idx
	_options_back = false
	# Clear any pending/hovered option from the PREVIOUS weapon/aux's options row before showing this one —
	# otherwise _board_render_selected (below) would index into the new _current with a stale idx from the
	# old one (wrong icon, or an out-of-range no-op that accidentally still looks right).
	_pending_pick_idx = -1
	_hover_preview_idx = -1
	var c: Dictionary = _choices[idx]
	if String(c.get("cat", "")) == "fusion":
		_select_fusion(c)   # bespoke A-top / FUSION / B-bottom view
		return
	_set_selected_display(String(c.get("def_id", "")), String(c["name"]), c.get("color", Color.GRAY), _aux_id_for(c))
	_title.text = String(c["name"])
	_route_options(c)
	_play_sfx("res://assets/audio/sfx/uiclick.wav")
	if _use_board():
		_board_render_choices()   # refresh the left-column scan VFX onto the newly-selected slot

## Fill the center-top panel with a big centered sprite + the item name.
func _set_selected_display(def_id: String, item_name: String, color: Color, aux_id: String = "") -> void:
	for ch in _selected_box.get_children():
		ch.free()
	var spr := _sprite_or_swatch(def_id, color, aux_id)
	spr.anchor_left = 0.2; spr.anchor_right = 0.8
	spr.anchor_top = 0.06; spr.anchor_bottom = 0.78
	_selected_box.add_child(spr)
	var lbl := Label.new()
	lbl.text = item_name
	lbl.add_theme_font_override("font", load(FONT_PATH))
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.05; lbl.anchor_right = 0.95
	lbl.anchor_top = 0.80; lbl.anchor_bottom = 0.97
	_selected_box.add_child(lbl)
	if _use_board():
		_board_render_selected()

## Decide the bottom-row content for the selected choice and render it. Sets _current = the array _pick() acts on.
func _route_options(c: Dictionary) -> void:
	var cat := String(c.get("cat", ""))
	var key := String(c.get("key", ""))
	var ckey := String(c.get("ckey", ""))
	if cat == "weapon" and not _weapon_pool(key).is_empty():
		var aw := get_tree().get_first_node_in_group("arena_weapons")
		# Maxed weapon → its capstones become the options (EVOLVE). _show_capstone sets _current + renders.
		if aw != null and bool(aw.call("weapon_needs_capstone", key)):
			_show_capstone(key)
			return
		# Roll the 3 perk options ONCE per left-slot choice per screen (cached by ckey) — clicking back and
		# forth between the 3 weapon/aux slots must keep showing the same options, not re-shuffle each time.
		if not _route_cache.has(ckey):
			var pool_choices := _gen_pool_choices(key)
			_route_cache[ckey] = pool_choices if not pool_choices.is_empty() else [c]
		_current = _route_cache[ckey]
		_render_options()
		return
	if cat == "aux" and not _aux_pool(key).is_empty():
		var ax := get_tree().get_first_node_in_group("arena_aux")
		if ax != null and bool(ax.call("aux_needs_capstone", key)):
			_show_aux_capstone(key)
			return
		if not _route_cache.has(ckey):
			var aux_choices := _gen_aux_pool_choices(key)
			_route_cache[ckey] = aux_choices if not aux_choices.is_empty() else [c]
		_current = _route_cache[ckey]
		_render_options()
		return
	# New weapon / poolless weapon / simple aux → a single Confirm panel.
	_current = [c]
	_render_options()

## Render _current into _options_box: 1 item → full-width confirm; N → N equal boxes. Adds a Back box in the
## All-In destroy sub-view (_options_back).
func _render_options() -> void:
	# Single option (new/upgrade/fuse confirm) auto-previews itself — no reason to force an extra click
	# before Confirm works. Multi-option screens (pool perks, capstones, destroy) start with nothing pending.
	_pending_pick_idx = 0 if _current.size() == 1 else -1
	_hover_preview_idx = _pending_pick_idx
	for ch in _options_box.get_children():
		ch.free()
	var n := _current.size()
	for i in n:
		_options_box.add_child(_make_option_box(_current[i], i, n))
	if _options_back:
		var back := Button.new()
		back.text = "← back"
		back.add_theme_font_override("font", load(FONT_PATH))
		back.focus_mode = Control.FOCUS_NONE
		back.anchor_left = 0.0; back.anchor_right = 0.18
		back.anchor_top = -0.16; back.anchor_bottom = -0.02
		back.pressed.connect(func() -> void: _show_capstone(_capstone_weapon))
		_options_box.add_child(back)
	if _use_board():
		_board_render_options()

## One option/confirm box: bold name + small detail + full-rect click → _pick(idx).
func _make_option_box(c: Dictionary, idx: int, total: int) -> Control:
	var box := _make_panel()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	if total <= 1:
		box.anchor_left = 0.0; box.anchor_right = 1.0
	else:
		var step := 1.0 / float(total)
		box.anchor_left = float(idx) * step + 0.01
		box.anchor_right = float(idx + 1) * step - 0.01
	box.anchor_top = 0.0; box.anchor_bottom = 1.0
	var name_lbl := Label.new()
	name_lbl.text = String(c.get("name", ""))
	name_lbl.add_theme_font_override("font", load(FONT_PATH))
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.anchor_left = 0.06; name_lbl.anchor_right = 0.94
	name_lbl.anchor_top = 0.06; name_lbl.anchor_bottom = 0.34
	box.add_child(name_lbl)
	var detail := Label.new()
	var dtxt := _default_text(c)
	if String(c.get("desc", "")) != "":
		dtxt += "\n" + String(c.get("desc", ""))
	detail.text = dtxt
	detail.add_theme_font_override("font", load(FONT_PATH))
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.anchor_left = 0.06; detail.anchor_right = 0.94
	detail.anchor_top = 0.40; detail.anchor_bottom = 0.94
	box.add_child(detail)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(_pick.bind(idx))
	# Hover highlight: brighten the box border + fill while the cursor is over it.
	var base_sb := box.get_theme_stylebox("panel") as StyleBoxFlat
	var hover_sb := base_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.16, 0.21, 0.32, 0.95)
	hover_sb.set_border_width_all(3)
	hover_sb.border_color = Color(1.0, 0.85, 0.35, 1.0)
	btn.mouse_entered.connect(func() -> void: box.add_theme_stylebox_override("panel", hover_sb))
	btn.mouse_exited.connect(func() -> void: box.add_theme_stylebox_override("panel", base_sb))
	box.add_child(btn)
	return box

## Fusion view: source A big (center-top), source B in the options area, a FUSION button between them.
func _select_fusion(c: Dictionary) -> void:
	_selected_idx = _choices.find(c)
	_title.text = "FUSE — %s" % String(c["name"])
	_set_selected_display(String(c.get("def_a", "")), String(c["name"]), c.get("color", Color.GRAY))
	for ch in _options_box.get_children():
		ch.free()
	# Source B sprite (fills the options box, leaving room for the FUSION button on top).
	var spr := _sprite_or_swatch(String(c.get("def_b", "")), c.get("color", Color.GRAY))
	spr.anchor_left = 0.3; spr.anchor_right = 0.7
	spr.anchor_top = 0.28; spr.anchor_bottom = 0.96
	_options_box.add_child(spr)
	# FUSION button, centered above source B (visually between A and B).
	var btn := Button.new()
	btn.text = "✦ FUSION ✦"
	btn.add_theme_font_override("font", load(FONT_PATH))
	btn.add_theme_font_size_override("font_size", 22)
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left = 0.3; btn.anchor_right = 0.7
	btn.anchor_top = 0.02; btn.anchor_bottom = 0.22
	btn.pressed.connect(func() -> void: _pick_fusion(c))
	_options_box.add_child(btn)
	_play_sfx("res://assets/audio/sfx/uialert.wav")
	if _use_board():
		# Board: show the fused result in WeaponDisplay + a single FUSION option in Upgrade1 (click → fuse).
		_current = [c]
		_pending_pick_idx = 0
		_hover_preview_idx = 0
		_board_render_selected()
		_board_render_options()

# ── Choice generation (weighted, owned-priority, no-dup, slot-limited, fallback) ──────────────
func _generate_choices(n: int) -> Array:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	var ax := get_tree().get_first_node_in_group("arena_aux")
	var choices: Array = []
	var chosen := {}   # ckey → true (prevents duplicate cards this screen)
	var weapons_full: bool = aw == null or bool(aw.call("weapons_full"))
	var aux_full: bool = ax == null or bool(ax.call("aux_slots_full"))
	# Guaranteed FUSION cards: every ready recipe (both components owned + maxed) is always offered, filling up
	# to all n slots, and keeps reappearing each level-up until picked.
	if aw != null:
		for fid: String in aw.call("available_fusions"):
			if choices.size() >= n:
				break
			var fc := _fusion_choice(aw, fid)
			if not chosen.has(String(fc["ckey"])):
				choices.append(fc)
				chosen[String(fc["ckey"])] = true
	while choices.size() < n:
		var owned_pool: Array = []
		var new_pool: Array = []
		# Owned, still-upgradeable weapons + aux → the upgrade pool.
		if aw != null:
			for k: String in aw.call("acquired_weapons"):
				if bool(aw.call("weapon_can_upgrade", k)) and not chosen.has("w:" + k):
					owned_pool.append(_weapon_choice(aw, k, "upgrade"))
		if ax != null:
			for id: String in ax.call("owned_aux"):
				if bool(ax.call("aux_can_upgrade", id)) and not chosen.has("a:" + id):
					owned_pool.append(_aux_choice(ax, id, "upgrade"))
		# Un-owned items → the new pool (only while there is a free slot of that kind).
		if aw != null and not weapons_full:
			var owned_w: Array = aw.call("acquired_weapons")
			for k: String in ArenaWeapons.WEAPON_INFO.keys():
				if bool(aw.call("is_fusion_kind", k)):
					continue   # fused weapons are only obtained via the fusion card, never the new-weapon roll
				if k == "player_2" and not bool(aw.call("player2_eligible")):
					continue   # Player 2 only appears once you own a weapon at level 10+
				if not (k in owned_w) and not chosen.has("w:" + k):
					new_pool.append(_weapon_choice(aw, k, "new"))
		if ax != null and not aux_full:
			var owned_a: Array = ax.call("owned_aux")
			for d: Dictionary in ArenaAux.AUX_DEFS:
				var id := String(d["id"])
				if not (id in owned_a) and not chosen.has("a:" + id):
					new_pool.append(_aux_choice(ax, id, "new"))
		# Candidate pool for THIS slot (pivot §7).
		var candidates: Array
		if weapons_full and aux_full:
			candidates = owned_pool                      # all slots full → upgrades only
		elif owned_pool.size() > 0 and randf() < OWNED_UPGRADE_CHANCE:
			candidates = owned_pool                      # owned-item priority
		else:
			candidates = owned_pool + new_pool
		if candidates.is_empty():
			break                                        # fallback: stop early (fewer than n cards)
		var pick := _weighted_pick(candidates)
		choices.append(pick)
		chosen[String(pick["ckey"])] = true
	return choices

func _weighted_pick(pool: Array) -> Dictionary:
	var total := 0.0
	for c: Dictionary in pool:
		total += float(c.get("weight", 1))
	var r := randf() * total
	for c: Dictionary in pool:
		r -= float(c.get("weight", 1))
		if r <= 0.0:
			return c
	return pool[pool.size() - 1]

func _weapon_choice(aw: Node, kind: String, action: String) -> Dictionary:
	var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
	return {
		"cat": "weapon", "key": kind, "action": action, "ckey": "w:" + kind,
		"name": String(info.get("label", kind)),
		"def_id": String(info.get("def_id", "")),
		"weight": WEAPON_WEIGHTS.get(kind, 50),
		"color": WEAPON_FALLBACK_COLOR,
		"level": int(aw.call("weapon_level", kind)),
		"effect": "+%d%% Damage" % int(round(ArenaWeapons.WEAPON_DMG_PER_LEVEL * 100.0)),
	}

func _aux_choice(ax: Node, id: String, action: String) -> Dictionary:
	var d: Dictionary = ax.call("def_for", id)
	return {
		"cat": "aux", "key": id, "action": action, "ckey": "a:" + id,
		"name": String(d.get("name", id)),
		"def_id": "",
		"weight": d.get("weight", 50),
		"color": d.get("color", Color.GRAY),
		"level": int(ax.call("aux_level", id)),
		"effect": String(d.get("effect", "")),
	}

## A guaranteed fusion card — combines two maxed weapons into one fused weapon. Carries the two source
## def_ids so the cutscene + card icon can show what's being combined (the fused icon art comes later).
func _fusion_choice(aw: Node, fid: String) -> Dictionary:
	var rec: Dictionary = (ArenaWeapons.FUSION_DEFS as Dictionary).get(fid, {})
	var a := String(rec.get("a", ""))
	var b := String(rec.get("b", ""))
	var ai: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(a, {})
	var bi: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(b, {})
	return {
		"cat": "fusion", "key": fid, "action": "fuse", "ckey": "f:" + fid,
		"name": String(rec.get("label", fid)),
		"def_id": String(rec.get("def_id", "")),
		"def_a": String(ai.get("def_id", "")),
		"def_b": String(bi.get("def_id", "")),
		"weight": 1,
		"color": Color(1.0, 0.82, 0.30),
		"level": 0,
		"effect": "FUSE\n%s + %s" % [String(ai.get("label", a)), String(bi.get("label", b))],
	}

func _pick(idx: int) -> void:
	if idx < 0 or idx >= _current.size():
		return
	_play_sfx("res://assets/audio/sfx/selectconfirm3.wav")
	var c: Dictionary = _current[idx]
	if String(c.get("cat", "")) == "fusion":
		_pick_fusion(c)
		return
	# Pool pick (2nd tier): grant the chosen upgrade rank + spend a skill point (auto-levels the weapon).
	if String(c.get("cat", "")) == "pool":
		var aw := get_tree().get_first_node_in_group("arena_weapons")
		var wk := String(c["weapon"])
		if aw != null:
			aw.call("pool_grant", wk, String(c["key"]))
			aw.call("spend_weapon_point", wk)
			# At max level the weapon does NOT auto-evolve — it stays un-evolved so it can still FUSE (lv 15-18).
			# EVOLVE is offered as its own choice next level-up (via weapon_can_upgrade + _route_options).
		_advance()
		return
	# Aux pool pick (2nd tier): grant the chosen perk rank + spend an aux skill point (auto-levels the item).
	if String(c.get("cat", "")) == "aux_pool":
		var ax := get_tree().get_first_node_in_group("arena_aux")
		var ak := String(c["aux"])
		if ax != null:
			ax.call("aux_pool_grant", ak, String(c["key"]))
			ax.call("spend_aux_point", ak)
			if bool(ax.call("aux_needs_capstone", ak)):
				_show_aux_capstone(ak)   # just hit max level → evolve! (don't consume the level-up yet)
				return
		_advance()
		return
	# Capstone (evolve) pick.
	if String(c.get("cat", "")) == "capstone":
		_pick_capstone(c)
		return
	# All-In destroy-a-weapon pick.
	if String(c.get("cat", "")) == "destroy":
		var aw2 := get_tree().get_first_node_in_group("arena_weapons")
		if aw2 != null:
			aw2.call("destroy_weapon", String(c["weapon"]))
			aw2.call("pool_set_capstone", _capstone_weapon, "all_in")
		_finish_capstone()
		return
	# A weapon/aux confirm box (new / poolless / pool-perks-maxed). The pool drill-down is handled by
	# _route_options when the LEFT item is selected, so here we just acquire/level the item.
	_apply(c)
	_advance()   # next queued level-up, or finish

# ── Shared tail: consume one queued level-up, then show the next or finish. ──────────
func _advance() -> void:
	_pending -= 1
	if _pending > 0:
		_show_cards()
	else:
		_finish()

# ── Skill-point pool (2nd tier) ─────────────────────────────────────────────────────
## The upgrade pool for a weapon kind (only Gatling so far). Add more weapons here as their pools land.
func _weapon_pool(kind: String) -> Dictionary:
	if kind == "gatling_gun":
		return ArenaWeapons.GATLING_POOL
	if kind == "death_beam":
		return ArenaWeapons.DEATHBEAM_POOL
	if kind == "arc":
		return ArenaWeapons.ARC_POOL
	if kind == "gauss":
		return ArenaWeapons.GAUSS_POOL
	if kind == "defensive_orbitals":
		return ArenaWeapons.ORBITAL_POOL
	if kind == "dragons_breath":
		return ArenaWeapons.DRAGON_POOL
	if kind == "chemtrail":
		return ArenaWeapons.CHEMTRAIL_POOL
	if kind == "z_sword":
		return ArenaWeapons.ZSWORD_POOL
	if kind == "ultrasonicator":
		return ArenaWeapons.SONIC_POOL
	if kind == "mortar":
		return ArenaWeapons.MORTAR_POOL
	if kind == "venomancer":
		return ArenaWeapons.PARA_POOL
	if kind == "aliwa":
		return ArenaWeapons.BOOM_POOL
	if kind == "viper":
		return ArenaWeapons.SNAKE_POOL
	if kind == "offensive_orbitals":
		return ArenaWeapons.STRIKER_POOL
	if kind == "ionizing_field":
		return ArenaWeapons.IONIZE_POOL
	if kind == "player_2":
		return ArenaWeapons.PLAYER2_POOL
	return {}

func _gen_pool_choices(kind: String) -> Array:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	var pool := _weapon_pool(kind)
	var avail: Array = []
	for id: String in pool.keys():
		var maxr := int(pool[id]["max"])
		var rank: int = int(aw.call("pool_rank", kind, id)) if aw != null else 0
		if maxr > 0 and rank >= maxr:
			continue   # this upgrade is maxed → don't offer it
		# Per-rank level gate (e.g. boomerang "Split Blade" unlocks at weapon level 6/11/16).
		if (pool[id] as Dictionary).has("gate") and aw != null:
			var gates: Array = pool[id]["gate"]
			var lvl := int(aw.call("weapon_level", kind))
			if rank < gates.size() and lvl < int(gates[rank]):
				continue
		avail.append(id)
	avail.shuffle()
	var out: Array = []
	var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
	var def_id := String(info.get("def_id", ""))
	for id: String in avail.slice(0, mini(CHOICES, avail.size())):
		var d: Dictionary = pool[id]
		out.append({
			"cat": "pool", "weapon": kind, "key": id, "action": "pool",
			"name": String(d.get("name", id)),
			"def_id": def_id,
			"color": WEAPON_FALLBACK_COLOR,
			"effect": String(d.get("per", "")),
			"desc": String(d.get("desc", "")),
			"rank": int(aw.call("pool_rank", kind, id)) if aw != null else 0,
			"maxr": int(d.get("max", 0)),
			"level": 0,
		})
	return out

# ── Aux skill-point pool (2nd tier) — mirrors the weapon pool flow for pooled passives ─────────
## The upgrade pool for an aux id (only Reinforcement Plate so far). Empty for simple-levelling aux.
func _aux_pool(id: String) -> Dictionary:
	return (ArenaAux.AUX_POOL as Dictionary).get(id, {})

func _gen_aux_pool_choices(id: String) -> Array:
	var ax := get_tree().get_first_node_in_group("arena_aux")
	var pool := _aux_pool(id)
	var col: Color = (ax.call("def_for", id) as Dictionary).get("color", Color.GRAY) if ax != null else Color.GRAY
	var avail: Array = []
	for pid: String in pool.keys():
		var maxr := int(pool[pid]["max"])
		var rank: int = int(ax.call("aux_pool_rank", id, pid)) if ax != null else 0
		if maxr > 0 and rank >= maxr:
			continue   # maxed perk → don't offer it
		# Level-gated perk (Beacon "Rival Beacon"): rank r needs aux level ≥ gate_first + gate_step×r.
		if (pool[pid] as Dictionary).has("gate_first") and ax != null:
			var need := int(pool[pid]["gate_first"]) + int(pool[pid].get("gate_step", 5)) * rank
			if int(ax.call("aux_level", id)) < need:
				continue
		avail.append(pid)
	avail.shuffle()
	var out: Array = []
	for pid: String in avail.slice(0, mini(CHOICES, avail.size())):
		var d: Dictionary = pool[pid]
		out.append({
			"cat": "aux_pool", "aux": id, "key": pid, "action": "pool",
			"name": String(d.get("name", pid)),
			"def_id": "",
			"color": col,
			"effect": String(d.get("per", "")),
			"desc": String(d.get("desc", "")),
			"rank": int(ax.call("aux_pool_rank", id, pid)) if ax != null else 0,
			"maxr": int(d.get("max", 0)),
			"level": 0,
		})
	return out

# ── Capstone (level-6 evolve) ─────────────────────────────────────────────────────
func _pick_capstone(c: Dictionary) -> void:
	# Aux evolutions have no slot cost — set + finish.
	if bool(c.get("is_aux", false)):
		var ax := get_tree().get_first_node_in_group("arena_aux")
		if ax != null:
			ax.call("aux_set_capstone", String(c["weapon"]), String(c["key"]))
		_finish_capstone()
		return
	# Weapon evolve is PERMANENT — it locks the weapon out of fusion forever. Warn before committing.
	_confirm_evolve(c)

## The actual weapon-capstone application, run only after the player confirms the "no more fusion" warning.
func _apply_weapon_capstone(c: Dictionary) -> void:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	var wk := String(c["weapon"])
	var cap := String(c["key"])
	# All-In costs a slot: if you're full, you must destroy a weapon first.
	if cap == "all_in" and aw != null and bool(aw.call("weapons_full")):
		_capstone_weapon = wk
		_show_destroy_choice(wk)
		return
	if aw != null:
		aw.call("pool_set_capstone", wk, cap)
	_finish_capstone()

## Modal warning: evolving forfeits the ability to fuse this weapon. Yes → evolve; No → back to the evolve choices.
func _confirm_evolve(c: Dictionary) -> void:
	var wk := String(c["weapon"])
	var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(wk, {})
	var wname := String(info.get("label", wk))
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks to the cards behind
	add_child(overlay)

	var panel := Panel.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5; panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	var pw := 540.0; var ph := 220.0
	panel.offset_left = -pw * 0.5; panel.offset_right = pw * 0.5
	panel.offset_top = -ph * 0.5; panel.offset_bottom = ph * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.07, 0.06, 0.98)
	sb.set_border_width_all(2); sb.border_color = Color(1.0, 0.55, 0.2, 0.95); sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 22; vb.offset_top = 18; vb.offset_right = -22; vb.offset_bottom = -18
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "⚠  EVOLVE IS PERMANENT"
	title.add_theme_font_override("font", load(FONT_PATH))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var msg := Label.new()
	msg.text = "Evolving %s locks it in — it can NEVER be fused again.\nProceed?" % wname
	msg.add_theme_font_override("font", load(FONT_PATH))
	msg.add_theme_font_size_override("font_size", 16)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(msg)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	vb.add_child(row)

	var yes := Button.new()
	yes.text = "Yes, evolve"
	yes.custom_minimum_size = Vector2(170, 46)
	yes.pressed.connect(func() -> void:
		overlay.queue_free()
		_apply_weapon_capstone(c))
	row.add_child(yes)

	var no := Button.new()
	no.text = "No, keep it fusable"
	no.custom_minimum_size = Vector2(170, 46)
	no.pressed.connect(func() -> void:
		overlay.queue_free()
		_show_capstone(wk))   # back to the evolve choices
	row.add_child(no)

	_play_sfx("res://assets/audio/sfx/uialert.wav")

func _finish_capstone() -> void:
	_options_back = false
	_pending -= 1
	if _pending > 0:
		_show_cards()
	else:
		_finish()

func _show_capstone(kind: String) -> void:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	if aw == null:
		_finish_capstone()
		return
	var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {})
	var def_id := String(info.get("def_id", ""))
	_current = []
	for d: Dictionary in aw.call("weapon_capstones", kind):
		_current.append({
			"cat": "capstone", "weapon": kind, "key": String(d["id"]), "action": "capstone",
			"name": String(d["name"]), "def_id": def_id, "color": WEAPON_FALLBACK_COLOR,
			"effect": String(d.get("desc", "")), "desc": String(d.get("desc", "")), "level": 0,
		})
	_capstone_weapon = kind
	_options_back = false
	_title.text = "%s — EVOLVE" % String(info.get("label", kind))
	_render_options()
	_play_sfx("res://assets/audio/sfx/uialert.wav")

## Aux evolve screen — the 3 capstones for a pooled passive (Reinforcement Plate). Cards carry is_aux=true.
func _show_aux_capstone(id: String) -> void:
	var ax := get_tree().get_first_node_in_group("arena_aux")
	if ax == null:
		_finish_capstone()
		return
	var d: Dictionary = ax.call("def_for", id)
	var col: Color = d.get("color", Color.GRAY)
	_current = []
	for cap: Dictionary in ax.call("aux_capstones", id):
		_current.append({
			"cat": "capstone", "weapon": id, "key": String(cap["id"]), "action": "capstone",
			"name": String(cap["name"]), "def_id": "", "color": col,
			"effect": String(cap.get("desc", "")), "desc": String(cap.get("desc", "")),
			"level": 0, "is_aux": true,
		})
	_capstone_weapon = id
	_options_back = false
	_title.text = "%s — EVOLVE" % String(d.get("name", id))
	_render_options()
	_play_sfx("res://assets/audio/sfx/uialert.wav")

## All-In's "choose a weapon to destroy" screen (back arrow → returns to the evolve choice).
func _show_destroy_choice(evolve_kind: String) -> void:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	if aw == null:
		_finish_capstone()
		return
	_current = []
	for k: String in aw.call("acquired_weapons"):
		if k == evolve_kind:
			continue   # can't sacrifice the weapon you're evolving
		var info: Dictionary = (ArenaWeapons.WEAPON_INFO as Dictionary).get(k, {})
		_current.append({
			"cat": "destroy", "weapon": k, "key": k, "action": "destroy",
			"name": String(info.get("label", k)), "def_id": String(info.get("def_id", "")),
			"color": Color(0.9, 0.3, 0.3), "effect": "DESTROY", "desc": "Sacrifice this weapon.", "level": 0,
		})
	_options_back = true
	_title.text = "ALL-IN — destroy a weapon"
	_render_options()
	_play_sfx("res://assets/audio/sfx/uiclick.wav")

## Fusion pick: hide the cards (tree stays paused), play the Yu-Gi-Oh cutscene, THEN perform the fuse.
func _pick_fusion(c: Dictionary) -> void:
	_root.hide()
	_board_show(false)
	var cut := get_tree().get_first_node_in_group("arena_fusion_cutscene")
	if cut != null and cut.has_method("play"):
		cut.call("play", String(c.get("def_a", "")), String(c.get("def_b", "")), String(c.get("def_id", "")))
		await cut.finished
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	if aw != null:
		aw.call("fuse", String(c["key"]))
	_pending -= 1
	if _pending > 0:
		_show_cards()
	else:
		_finish()

func _finish() -> void:
	_showing = false
	_root.hide()
	_board_clear_all()
	_board_show(false)
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if not _showing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_1: _pick(0)
			KEY_2: _pick(1)
			KEY_3: _pick(2)

# ── Apply ─────────────────────────────────────────────────────────────────────────
func _apply(c: Dictionary) -> void:
	match String(c["cat"]):
		"weapon":
			var aw := get_tree().get_first_node_in_group("arena_weapons")
			if aw == null:
				return
			if String(c["action"]) == "new":
				aw.call("acquire_weapon", String(c["key"]))
			else:
				aw.call("level_up_weapon", String(c["key"]))
		"aux":
			var ax := get_tree().get_first_node_in_group("arena_aux")
			if ax == null:
				return
			if String(c["action"]) == "new":
				ax.call("acquire_aux", String(c["key"]))
			else:
				ax.call("level_up_aux", String(c["key"]))

# ── Display text ────────────────────────────────────────────────────────────────────
func _default_text(c: Dictionary) -> String:
	var lvl := int(c.get("level", 0))
	if String(c["action"]) == "capstone" or String(c["action"]) == "destroy":
		return String(c.get("effect", ""))
	# 1st-tier card for a weapon that has a skill-point pool (Gatling): clicking opens the perk picker, so don't
	# show the old generic "+30% Damage".
	if String(c["cat"]) == "weapon" and not _weapon_pool(String(c.get("key", ""))).is_empty():
		if String(c["action"]) == "new":
			return "NEW\npick a perk"
		return "Lv %d\npick a perk" % lvl
	# 1st-tier aux with a pool (Reinforcement Plate): clicking opens its perk picker.
	if String(c["cat"]) == "aux" and not _aux_pool(String(c.get("key", ""))).is_empty():
		if String(c["action"]) == "new":
			return "NEW\npick a perk"
		return "Lv %d\npick a perk" % lvl
	if String(c["action"]) == "pool":
		var rank := int(c.get("rank", 0))
		var maxr := int(c.get("maxr", 0))
		var rt := ("Rank %d/%d" % [rank, maxr]) if maxr > 0 else ("Rank %d" % rank)
		return "%s\n%s" % [String(c.get("effect", "")), rt]
	if String(c["action"]) == "fuse":
		return String(c.get("effect", "FUSE"))
	if String(c["action"]) == "new":
		# A new weapon is conveyed by its icon + name; aux items also show what the passive grants.
		if String(c["cat"]) == "weapon":
			return "Acquired"
		return "Acquired\n%s" % String(c.get("effect", ""))
	return "Lv %d → %d\n%s" % [lvl, lvl + 1, String(c.get("effect", ""))]

func _current_text(c: Dictionary) -> String:
	if String(c.get("action", "")) in ["pool", "capstone", "destroy"]:
		return String(c.get("desc", ""))
	if String(c.get("action", "")) == "fuse":
		return "Both at MAX"
	var lvl := int(c.get("level", 0))
	if lvl <= 0:
		return "Not own\nyet"
	return "Owned  Lv %d" % lvl

# ── SFX helper ──────────────────────────────────────────────────────────────────
func _play_sfx(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = linear_to_db(0.8)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# ── UI build ────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.03, 0.06, 0.97)   # near-opaque: the level-up takes the whole screen
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	# Title strip (full width, top).
	_title = Label.new()
	_title.text = "LEVEL UP — choose an item"
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_font_override("font", load(FONT_PATH))
	_title.add_theme_color_override("font_color", Color("#E5792A"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.anchor_left = 0.0; _title.anchor_right = 1.0
	_title.anchor_top = 0.012; _title.anchor_bottom = 0.07
	_root.add_child(_title)

	# Left column: 3 stacked slots.
	_slot_nodes.clear()
	var avail := CONTENT_BOTTOM - CONTENT_TOP
	var slot_h := (avail - SLOT_GAP * 2.0) / 3.0
	for i in 3:
		var slot := _make_panel()
		slot.anchor_left = COL_L_LEFT; slot.anchor_right = COL_L_RIGHT
		slot.anchor_top = CONTENT_TOP + float(i) * (slot_h + SLOT_GAP)
		slot.anchor_bottom = slot.anchor_top + slot_h
		_root.add_child(slot)
		_slot_nodes.append(slot)

	# Center column: selected-item panel (top) + options box (bottom).
	_selected_box = _make_panel()
	_selected_box.anchor_left = COL_C_LEFT; _selected_box.anchor_right = COL_C_RIGHT
	_selected_box.anchor_top = CONTENT_TOP; _selected_box.anchor_bottom = SEL_BOTTOM
	_root.add_child(_selected_box)

	_options_box = Control.new()
	_options_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options_box.anchor_left = COL_C_LEFT; _options_box.anchor_right = COL_C_RIGHT
	_options_box.anchor_top = OPT_TOP; _options_box.anchor_bottom = CONTENT_BOTTOM
	_root.add_child(_options_box)

	# Right column: curated stats list.
	var stats_panel := _make_panel()
	_stats_panel = stats_panel
	stats_panel.anchor_left = COL_R_LEFT; stats_panel.anchor_right = COL_R_RIGHT
	stats_panel.anchor_top = CONTENT_TOP; stats_panel.anchor_bottom = CONTENT_BOTTOM
	_root.add_child(stats_panel)
	var stats_head := Label.new()
	stats_head.text = "STATS"
	stats_head.add_theme_font_override("font", load(FONT_PATH))
	stats_head.add_theme_font_size_override("font_size", 20)
	stats_head.add_theme_color_override("font_color", Color("#E5792A"))
	stats_head.anchor_left = 0.0; stats_head.anchor_right = 1.0
	stats_head.anchor_top = 0.01; stats_head.anchor_bottom = 0.07
	stats_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_panel.add_child(stats_head)
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 4)
	_stats_box.anchor_left = 0.06; _stats_box.anchor_right = 0.94
	_stats_box.anchor_top = 0.08; _stats_box.anchor_bottom = 0.98
	stats_panel.add_child(_stats_box)

## A bordered translucent panel used for slots / the selected box / the stats column.
func _make_panel() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.85)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.45, 0.70, 0.9)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p

## Build the curated, read-only global-stat rows. Each entry is rendered only if its value resolves
## (so stats not yet wired in GameManager are omitted rather than shown as 0). Refreshed on every open.
func _refresh_stats() -> void:
	if _stats_box == null:
		return
	for c in _stats_box.get_children():
		c.free()
	_fill_stat_rows(_stats_box)

## Build the curated, read-only global-stat rows into `box` (shared by the built-in panel + the board's
## StatDisplay). Each entry renders only if its value resolves. `preview` (row id → {row, amt, pct}) comes
## from the board's currently-selected-but-unconfirmed card (see _preview_map) — the built-in fallback panel
## never passes one, so it always renders plain (no delta suffix).
func _fill_stat_rows(box: Container, preview: Dictionary = {}) -> void:
	var gm := GameManager
	if gm.has_method("get_damage_mult"):
		box.add_child(_make_stat_row("Damage", "x%.2f" % gm.get_damage_mult(), "damage", preview))
	if gm.has_method("get_fire_rate_mult"):
		box.add_child(_make_stat_row("Fire rate", "x%.2f" % gm.get_fire_rate_mult(), "fire_rate", preview))
	if gm.has_method("get_crit_chance"):
		box.add_child(_make_stat_row("Crit chance", "%d%%" % int(round(gm.get_crit_chance() * 100.0)), "crit_chance", preview))
	if gm.has_method("get_crit_damage"):
		box.add_child(_make_stat_row("Crit damage", "x%.2f" % gm.get_crit_damage(), "crit_damage", preview))
	if gm.has_method("get_move_speed_mult"):
		box.add_child(_make_stat_row("Move speed", "x%.2f" % gm.get_move_speed_mult(), "move_speed", preview))
	if gm.has_method("get_pickup_radius"):
		box.add_child(_make_stat_row("Pickup", "%d" % int(round(gm.get_pickup_radius())), "pickup", preview))
	if gm.has_method("get_base_defense"):
		box.add_child(_make_stat_row("Armor (flat)", "%d" % gm.get_base_defense(), "armor", preview))
	if gm.has_method("get_momentum_mult"):
		box.add_child(_make_stat_row("Momentum", "x%.2f" % gm.get_momentum_mult(), "momentum", preview))
	# Probe optional stats that may not exist yet (HP, AOE, armor pen). Add rows only if present.
	if gm.has_method("get_max_hp"):
		box.add_child(_make_stat_row("HP", "%d" % int(gm.get_max_hp()), "hp", preview))
	if gm.has_method("get_aoe_mult"):
		box.add_child(_make_stat_row("AOE", "x%.2f" % gm.get_aoe_mult(), "aoe", preview))
	if gm.has_method("get_armor_pen_pct"):
		box.add_child(_make_stat_row("Armor pen %", "%d%%" % int(round(gm.get_armor_pen_pct() * 100.0)), "armor_pen_pct", preview))
	if gm.has_method("get_armor_pen_flat"):
		box.add_child(_make_stat_row("Armor pen flat", "%d" % int(gm.get_armor_pen_flat()), "armor_pen_flat", preview))
	# Newer aux-granted stats: hidden at their baseline (not yet owned) unless the pending preview would
	# grant them — then they show up early as "<base> +<delta>" so the player sees what they're about to gain.
	if float(gm.upg_hp_regen) != 0.0 or preview.has("hp_regen"):
		box.add_child(_make_stat_row("HP Regen", "%.1f/s" % gm.upg_hp_regen, "hp_regen", preview))
	if float(gm.upg_force_shield_max) != 0.0 or preview.has("shield"):
		box.add_child(_make_stat_row("Shield", "%d" % int(round(gm.upg_force_shield_max)), "shield", preview))
	if float(gm.upg_dodge) != 0.0 or preview.has("dodge"):
		box.add_child(_make_stat_row("Dodge", "%d%%" % int(round(gm.upg_dodge * 100.0)), "dodge", preview))
	if float(gm.run_coin_mult) != 1.0 or preview.has("coin"):
		box.add_child(_make_stat_row("Coin", "x%.2f" % gm.run_coin_mult, "coin", preview))
	if float(gm.upg_xp_gain_mult) != 1.0 or preview.has("xp"):
		box.add_child(_make_stat_row("XP", "x%.2f" % gm.upg_xp_gain_mult, "xp", preview))
	if float(gm.upg_spawn_rate_mult) != 1.0 or preview.has("spawn"):
		box.add_child(_make_stat_row("Spawn Rate", "x%.2f" % gm.upg_spawn_rate_mult, "spawn", preview))
	if float(gm.upg_retaliation) != 0.0 or preview.has("retaliation"):
		box.add_child(_make_stat_row("Retaliation", "%d" % int(round(gm.upg_retaliation)), "retaliation", preview))

## row_id identifies this row for the `preview` delta lookup (see _preview_map): when present, a coloured
## "+N" / "-N" suffix (green/red) is appended after the value — green when the change is an increase.
func _make_stat_row(label: String, value: String, row_id: String = "", preview: Dictionary = {}) -> Control:
	var row := HBoxContainer.new()
	var lead := Control.new()                        # left column shifted right 10px
	lead.custom_minimum_size = Vector2(10.0, 0.0)
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lead)
	var l := Label.new()
	l.text = label
	l.add_theme_font_override("font", load(FONT_PATH))
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", load(FONT_PATH))
	v.add_theme_font_size_override("font_size", 15)
	v.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	if row_id != "" and preview.has(row_id):
		var d: Dictionary = preview[row_id]
		var amt := float(d.get("amt", 0.0))
		var dl := Label.new()
		dl.text = " " + _fmt_stat_delta(amt, bool(d.get("pct", false)))
		dl.add_theme_font_override("font", load(FONT_PATH))
		dl.add_theme_font_size_override("font_size", 15)
		dl.add_theme_color_override("font_color", Color(0.45, 0.85, 0.45) if amt >= 0.0 else Color(0.95, 0.35, 0.35))
		row.add_child(dl)
	var trail := Control.new()                       # right column shifted left 10px
	trail.custom_minimum_size = Vector2(10.0, 0.0)
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(trail)
	return row

## "+15%" / "-2.5%" / "+0.2" style suffix for a stat-row delta (sign always shown; percent vs flat per the
## entry). No rounding — shows up to 2 decimals exactly, trimming only trailing zeros (never drops precision
## the way int(round(...)) did, e.g. "-2.5% fire rate" no longer collapses to "-2%"/"-3%").
func _fmt_stat_delta(amt: float, pct: bool) -> String:
	var sign := "+" if amt >= 0.0 else "-"
	var mag := absf(amt) * (100.0 if pct else 1.0)
	var s := "%.2f" % mag
	if s.ends_with("00"):
		s = s.substr(0, s.length() - 3)
	elif s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	return "%s%s%s" % [sign, s, ("%" if pct else "")]
