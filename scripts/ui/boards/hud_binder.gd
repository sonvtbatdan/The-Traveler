extends BoardBinder
class_name HudBinder
## RUNTIME behaviour of the PLAYER HUD board. Drives the nodes authored in board_edit_mode from live game
## state: weapon/aux slot icons + charge overlays, HP/Shield/Level bar VFX (masked shader fills), the
## KILL/COIN/HP/Shield/LV sentinel texts, the Menu/Inv press buttons, and the four screen-edge "macro"
## regions with their shrink/pulse animations.
##
## Moved out of hud_edit_mode.gd so the editor stays board-agnostic. Reads the surface's authored data +
## helpers via `_ed` (`_ed._nodes`, `_ed._groups`, `_ed._objects_container`, `_ed._load_tex(...)`,
## `_ed._item_path(...)`, `_ed._load_font(...)`, `_ed._find_child(...)`, `_ed._child_visible(...)`).

const ArenaWeapons   := preload("res://scripts/gameplay/arena_weapons.gd")
const BAR_FILL_SHADER   := "res://assets/shaders/bar_fill.gdshader"
const HUD_BLEND_SHADER  := "res://assets/shaders/hud_blend.gdshader"
const SHIELDBAND1_VFX_SHADER := "res://assets/shaders/shieldband1_vfx.gdshader"
const SHIELDBAND1_FILE := "shieldband1"   # HUD 1.1 decorative sheen — independent of shieldband/_shield_fill
const WEAPON_HUD_ICON_DIR := "res://assets/inventory/icon/"   # dedicated per-kind weapon icons for HUD slot btns

# Bar VFX fill/glow tones per bar (level=green, HP=red, shield=blue).
const LV_FILL_COL := Color(0.18, 0.85, 0.32, 1.0)
const LV_GLOW_COL := Color(0.45, 1.00, 0.55, 1.0)
const HP_FILL_COL := Color(0.86, 0.15, 0.13, 1.0)
const HP_GLOW_COL := Color(1.00, 0.42, 0.34, 1.0)
const SH_FILL_COL := Color(0.13, 0.48, 0.86, 1.0)
const SH_GLOW_COL := Color(0.40, 0.78, 1.00, 1.0)
# Band sprites act as the crop-frame/mask for their bar VFX; they only show in the editor (indicators).
const BAR_BAND_FILES := {"levelband": true, "HPband": true, "shieldband": true}
const SLOT_ICON_FIT   := 0.72   # weapon/aux icon box = this fraction of the btn
const SLOT_ICON_BLEND := 0      # weapon/aux icon blend mode → "Normal"
# HUD 1.1 (2026-08-06, on request): every weapon/aux slot now ALWAYS shows a background — "btn" itself
# stays hidden (position-anchor only, same role it always had — see git history's old SHOW_SLOT_BTN/
# SHOW_CHARGE_FX TEMP flags, both retired here); btnblack is the always-visible base in its place. Exactly
# one of btnblack/btngreen/btnblue shows per slot: btnblack (empty slot, or a normal/non-fusable item),
# btngreen (this slot's item completes the FIRST currently-owned fusable pair), btnblue (completes the
# SECOND pair). Aux slots (Button6-10) never fuse — always btnblack. "Owned" is the whole bar here — no
# level/evolve gate, unlike the FUSE card itself (arena_levelup_ui.gd's available_fusions(), which additionally
# requires both ≥ FUSION_MIN_LEVEL and neither evolved) — this is meant to flag the pairing itself early, not
# mirror exactly when the FUSE card will appear. See _fusion_pair_colors().

# ── Macro groups (gameplay-only): 4 screen-edge regions built from the editor groups ────────────────
const MACRO_KEYS     := ["Weapon", "Aux", "KillCoin", "LV"]
const MACRO_EDGE     := {"Weapon": "left", "Aux": "right", "KillCoin": "top", "LV": "bottom"}
const MACRO_BEHAVIOR := {"Weapon": "shrink", "Aux": "shrink", "KillCoin": "pulse", "LV": "static"}
const GROUP_MACRO := {
	"Button1": "Weapon", "Button2": "Weapon", "Button3": "Weapon", "Button4": "Weapon", "Button5": "Weapon", "ActiveBar": "Weapon",
	"Button6": "Aux", "Button7": "Aux", "Button8": "Aux", "Button9": "Aux", "Button10": "Aux", "PassiveBar": "Aux",
	"KillBar": "KillCoin",
	"INV": "LV", "MENU": "LV", "LevelBarBg": "LV", "Level": "LV", "LevelBar": "LV",
}
const KILLCOIN_TEXTS := {"KILL": true, "COIN": true}
const MACRO_MARGIN := 0.0
const SHRINK_SCALE := 0.70
const SHRINK_DELAY := 5.0
const SHRINK_DUR   := 0.30
const PULSE_SCALE  := 1.03
const PULSE_DUR    := 0.05
# Unique-role sprite files resolved by filename anywhere in the layout (bar bands + press-button pairs).
const ROLE_FILES := {
	"levelband": true, "HPband": true, "shieldband": true,
	"menubtn": true, "menubtnpress": true, "invbtn": true, "invbtnpress": true,
	"inventory": true, "inventorypress": true,
	"menu1": true, "menu1press": true, "inv1": true, "inv1press": true,   # HUD 1.1 Menu/Inv art
}

# ── Runtime state ────────────────────────────────────────────────────────────────────
var _ready_flag: bool = false
var _text_bindings: Array = []        # [{node, kind, align, left, center, right, y}]
var _wslots: Array = []               # [{btn, red, green, icon}] index 0..4 → weapon slots 1..5
var _aslots: Array = []               # [{btn, yellow, icon}]      index 0..4 → aux slots 6..10
var _level_fill: TextureRect = null
var _hp_fill: TextureRect = null
var _shield_fill: TextureRect = null
var _shieldband1_vfx: TextureRect = null   # decorative sheen on HUD 1.1's shieldband1 — own shader/material, but follows the same shield % as _shield_fill
var _runtime_extras: Array = []        # runtime-only nodes to free on edit
var _weapons_node: Node = null
var _aux_node: Node = null
var _weapon_icon_cache: Dictionary = {}
var _aux_icon_cache: Dictionary = {}
var _macros: Dictionary = {}          # key -> {container, edge, anchor_local, behavior, tween}
var _last_acquired_n: int = -1
var _last_owned_n: int = -1
var _signals_hooked: bool = false

# ── Editor capability hook ───────────────────────────────────────────────────────────
func is_band_file(file: String) -> bool:
	return BAR_BAND_FILES.has(file)

# ── Lifecycle ────────────────────────────────────────────────────────────────────────
func setup(surface) -> void:
	super.setup(surface)
	_hook_stat_signals()

## Live-stat signals that drive the macro-region animations (connected once; handlers no-op if the
## targeted region isn't built, e.g. while the editor is open).
func _hook_stat_signals() -> void:
	if _signals_hooked:
		return
	_signals_hooked = true
	if GameManager.has_signal("kills_changed"):
		GameManager.kills_changed.connect(func(_k: int) -> void: _pulse_macro("KillCoin"))
	if GameManager.has_signal("money_changed"):
		GameManager.money_changed.connect(func(_m: int) -> void: _pulse_macro("KillCoin"))
	if GameManager.has_signal("player_stats_changed"):
		GameManager.player_stats_changed.connect(func() -> void: _trigger_shrink("Weapon"); _trigger_shrink("Aux"))

func update(_delta: float) -> void:
	if not _ready_flag:
		return
	_update_bindings()

## Resolve role nodes from the loaded layout and create the runtime-only extras (weapon/aux icons,
## bar fills, menu/inv press-buttons). Called on first setup and whenever the editor closes.
func build() -> void:
	clear()
	_ready_flag = false
	_text_bindings.clear()
	_wslots.clear(); _wslots.resize(5)
	_aslots.clear(); _aslots.resize(5)
	_weapons_node = get_tree().get_first_node_in_group("arena_weapons")
	_aux_node = get_tree().get_first_node_in_group("arena_aux")
	# First occurrence of each unique-role sprite file (bar bands + press-button pairs), any group.
	var roles: Dictionary = {}
	for g: Dictionary in _ed._groups:
		var gname := String(g.get("name", ""))
		var children: Array = g.get("children", [])
		if gname == "Text":
			for ch: Dictionary in children:
				if String(ch.get("type", "")) == "text":
					_bind_text(ch)
		elif gname.begins_with("Button"):
			var num := int(gname.substr(6))
			var brk := {}
			for ch: Dictionary in children:
				if String(ch.get("type", "")) == "item":
					brk[String(ch.get("file", ""))] = _ed._nodes.get(int(ch.get("id", -1)))
			if num >= 1 and num <= 5:
				var wbtn = brk.get("btn")
				_wslots[num - 1] = {
					"btn": wbtn, "red": brk.get("btnred"), "green": brk.get("btngreen"),
					"black": brk.get("btnblack"), "blue": brk.get("btnblue"),
					"icon": _make_slot_icon(wbtn, "Weapon"),
				}
			elif num >= 6 and num <= 10:
				var abtn = brk.get("btn")
				_aslots[num - 6] = {
					"btn": abtn, "yellow": brk.get("btnyellow"), "black": brk.get("btnblack"),
					"icon": _make_slot_icon(abtn, "Aux"),
				}
		# Collect unique-role item CHILDREN (bands / buttons) from every group, regardless of group name.
		for ch: Dictionary in children:
			if String(ch.get("type", "")) == "item":
				var f := String(ch.get("file", ""))
				if ROLE_FILES.has(f) and not roles.has(f):
					roles[f] = ch
	# Bar VFX — a masked shader fill in each band silhouette (level = green, HP = red, shield = blue).
	if roles.has("levelband"):
		_level_fill = _make_bar_fill(roles["levelband"], LV_FILL_COL, LV_GLOW_COL)
	if roles.has("HPband"):
		_hp_fill = _make_bar_fill(roles["HPband"], HP_FILL_COL, HP_GLOW_COL)
	if roles.has("shieldband"):
		_shield_fill = _make_bar_fill(roles["shieldband"], SH_FILL_COL, SH_GLOW_COL)
	# HUD 1.1 decorative sheen on shieldband1 — independent lookup, independent of the block above.
	var sb1 := _find_shieldband1()
	if not sb1.is_empty():
		_shieldband1_vfx = _make_shieldband1_vfx(sb1)
	# Menu / Inv buttons — normal sprite, "…press" while held, action on release.
	_setup_press_pair(_role_node(roles, "menubtn"), _role_node(roles, "menubtnpress"), _open_menu, "LV")
	_setup_press_pair(_role_node(roles, "invbtn"),  _role_node(roles, "invbtnpress"),  _open_inventory, "LV")
	# Legacy Equip pair (kept harmless if the layout still uses inventory/inventorypress sprites).
	_setup_press_pair(_role_node(roles, "inventory"), _role_node(roles, "inventorypress"), _open_inventory, "LV")
	# HUD 1.1 Menu / Inv buttons — normal sprite, "…press" ON HOVER (not click-hold), action on click.
	_setup_hover_pair(_role_node(roles, "menu1"), _role_node(roles, "menu1press"), _open_menu, "LV")
	_setup_hover_pair(_role_node(roles, "inv1"),  _role_node(roles, "inv1press"),  _open_inventory, "LV")
	_build_macros()   # reparent everything into the 4 edge-anchored regions (gameplay only)
	_ready_flag = true

## Free everything build() created + restore design text; leaves the authored nodes for editing.
func clear() -> void:
	_ready_flag = false
	_clear_macros()
	_clear_runtime_extras()
	_restore_design_text()

## Live node for a role child dict stored in `roles`, or null.
func _role_node(roles: Dictionary, key: String) -> Node:
	var ch = roles.get(key)
	if ch == null:
		return null
	return _ed._nodes.get(int((ch as Dictionary).get("id", -1)))

## A press-toggle button pair over a HUD sprite: show `normal`; while held show `press`; fire `action`
## on release inside. A transparent Button catches the input (the sprites themselves stay non-interactive).
func _setup_press_pair(normal, press, action: Callable, macro_key: String = "") -> void:
	if normal == null or not is_instance_valid(normal):
		return
	var nc := normal as Control
	_set_press_pair(normal, press, false)   # default: show normal, hide press
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	b.position = nc.position
	b.size = nc.size
	b.z_index = (normal as CanvasItem).z_index + 1
	b.button_down.connect(func() -> void: _set_press_pair(normal, press, true))
	b.button_up.connect(func() -> void: _set_press_pair(normal, press, false))
	if action.is_valid():
		b.pressed.connect(action)
	b.set_meta("macro_key", macro_key)   # ride along with its region (e.g. LV) when reparented
	_ed._objects_container.add_child(b)
	_runtime_extras.append(b)

## A hover-toggle button pair over a HUD sprite: show `normal`; while the mouse is over it show
## `press`; fire `action` on click (regardless of hover state). Same transparent-Button catch as
## `_setup_press_pair`, just driven by hover instead of click-hold — used by HUD 1.1's Menu/Inv art.
func _setup_hover_pair(normal, press, action: Callable, macro_key: String = "") -> void:
	if normal == null or not is_instance_valid(normal):
		return
	var nc := normal as Control
	_set_press_pair(normal, press, false)   # default: show normal, hide press
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	b.position = nc.position
	b.size = nc.size
	b.z_index = (normal as CanvasItem).z_index + 1
	b.mouse_entered.connect(func() -> void: _set_press_pair(normal, press, true))
	b.mouse_exited.connect(func() -> void: _set_press_pair(normal, press, false))
	if action.is_valid():
		b.pressed.connect(action)
	b.set_meta("macro_key", macro_key)
	_ed._objects_container.add_child(b)
	_runtime_extras.append(b)

func _set_press_pair(normal, press, pressed: bool) -> void:
	if normal != null and is_instance_valid(normal):
		(normal as CanvasItem).visible = not pressed
	if press != null and is_instance_valid(press):
		(press as CanvasItem).visible = pressed

## Menu button → open the shared Settings/Menu panel (group "settings_panel").
func _open_menu() -> void:
	var s := get_tree().get_first_node_in_group("settings_panel")
	if s != null and is_instance_valid(s) and s.has_method("open"):
		s.call("open")

## Inv button → open the inventory (the panel itself is implemented later; no-ops until then).
func _open_inventory() -> void:
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv != null and is_instance_valid(inv) and inv.has_method("toggle"):
		inv.call("toggle")

func _bind_text(ch: Dictionary) -> void:
	var node = _ed._nodes.get(int(ch.get("id", -1)))
	if node == null or not is_instance_valid(node):
		return
	var kind := ""
	match String(ch.get("text", "")):
		"300": kind = "hp_max"      # renders "current/max" — see _text_value()
		"100": kind = "sh_max"      # renders "current/max" — see _text_value()
		"KILL": kind = "kill"
		"COIN": kind = "coin"
		"LV. 3": kind = "level"
	if kind == "":
		return
	if node.has_method("apply"):
		node.call("apply", ch, _ed._load_font(String(ch.get("font", ""))))   # design text → measure anchor
	var pos: Vector2 = (node as Control).position
	var sz: Vector2 = (node as Control).size
	_text_bindings.append({
		"node": node, "kind": kind, "align": int(ch.get("align", 0)),
		"left": pos.x, "center": pos.x + sz.x * 0.5, "right": pos.x + sz.x, "y": pos.y,
	})

func _update_bindings() -> void:
	_update_macro_anchors()   # hold each region flush to its edge through the shrink/pulse scaling
	for b: Dictionary in _text_bindings:
		_set_text_binding(b, _text_value(String(b["kind"])))
	_update_weapons()
	_update_aux()
	var need := GameManager.xp_to_next(GameManager.player_level)
	_set_fill_progress(_level_fill, float(GameManager.player_xp), float(need))
	_set_fill_progress(_hp_fill, float(GameManager.ship_hp), float(GameManager.ship_max_hp))
	_set_fill_progress(_shield_fill, GameManager.ship_shield, GameManager.shield_capacity_total())
	_set_fill_progress(_shieldband1_vfx, GameManager.ship_shield, GameManager.shield_capacity_total())

## Drive a bar fill's shader `progress` from cur/maxv (clamped 0..1; 0 when maxv <= 0).
func _set_fill_progress(fill: TextureRect, cur: float, maxv: float) -> void:
	if fill == null or not is_instance_valid(fill):
		return
	var mat := fill.material as ShaderMaterial
	if mat == null:
		return
	var frac := clampf(cur / maxv, 0.0, 1.0) if maxv > 0.0 else 0.0
	mat.set_shader_parameter("progress", frac)

func _text_value(kind: String) -> String:
	match kind:
		"hp_max": return "%d/%d" % [GameManager.ship_hp, GameManager.ship_max_hp]
		"sh_max": return "%d/%d" % [int(round(GameManager.ship_shield)), int(round(GameManager.shield_capacity_total()))]
		"kill":   return str(GameManager.run_kills)
		"coin":   return str(GameManager.money)
		"level":  return "LV. %d" % GameManager.player_level
	return ""

func _set_text_binding(b: Dictionary, s: String) -> void:
	var node = b["node"]
	if node == null or not is_instance_valid(node) or not node.has_method("set_text_value"):
		return
	node.call("set_text_value", s)
	var w: float = (node as Control).size.x
	var x: float
	match int(b["align"]):
		1: x = float(b["center"]) - w * 0.5
		2: x = float(b["right"]) - w
		_: x = float(b["left"])
	(node as Control).position = Vector2(x, float(b["y"]))

func _update_weapons() -> void:
	if _weapons_node == null or not is_instance_valid(_weapons_node):
		_weapons_node = get_tree().get_first_node_in_group("arena_weapons")
	var acquired: Array = []
	if _weapons_node != null and is_instance_valid(_weapons_node) and _weapons_node.has_method("acquired_weapons"):
		acquired = _weapons_node.call("acquired_weapons")
	if _last_acquired_n >= 0 and acquired.size() > _last_acquired_n:
		_trigger_shrink("Weapon")   # a new weapon → pop the Weapon region to full, then re-shrink
	_last_acquired_n = acquired.size()
	var pair_color := _fusion_pair_colors(acquired)   # slot index -> "green"/"blue", see its own doc comment
	for i in _wslots.size():
		var s = _wslots[i]
		if s == null:
			continue
		var has: bool = i < acquired.size()
		_set_vis(s.get("btn"), false)   # anchor only — btnblack is the always-visible base now, not btn (2026-08-06)
		_set_vis(s.get("red"), false)   # charge-FX retired in favor of the fusion-pair highlight below
		var icon = s.get("icon")
		if has:
			var kind := String(acquired[i])
			if icon != null and is_instance_valid(icon):
				var tex := _weapon_icon_tex(kind)
				(icon as TextureRect).texture = tex
				(icon as TextureRect).visible = tex != null
			var col := String(pair_color.get(i, ""))
			_set_vis(s.get("green"), col == "green")
			_set_vis(s.get("blue"), col == "blue")
			_set_vis(s.get("black"), col == "")
		else:
			_set_vis(s.get("green"), false)
			_set_vis(s.get("blue"), false)
			_set_vis(s.get("black"), true)   # empty slot → black, same as a normal/non-fusable item
			if icon != null and is_instance_valid(icon):
				(icon as CanvasItem).visible = false

## HUD 1.1 fusion-pair highlight (2026-08-06, on request): which of the 5 weapon slots (by index into
## `acquired`) light up green (first ready pair) / blue (second ready pair). "Ready" here = BOTH of a
## FUSION_DEFS recipe's component kinds are somewhere in `acquired` — no level/evolve requirement (see the
## HUD 1.1 class-level doc comment for why this is deliberately looser than the FUSE card's own gate).
## Recipes are checked in FUSION_DEFS declaration order; a slot already claimed by an earlier pair can't be
## claimed again (matters for "gauss", which is a component of both "overcharger" and "singularities") — at
## most 2 disjoint pairs can exist across 5 slots anyway, matching the 2 colors available.
func _fusion_pair_colors(acquired: Array) -> Dictionary:
	var out := {}
	var claimed := {}   # slot index -> true
	var colors := ["green", "blue"]
	var color_i := 0
	for fid: String in ArenaWeapons.FUSION_DEFS:
		if color_i >= colors.size():
			break
		var rec: Dictionary = ArenaWeapons.FUSION_DEFS[fid]
		var a := String(rec["a"])
		var b := String(rec["b"])
		var ia := -1
		var ib := -1
		for i in acquired.size():
			if claimed.has(i):
				continue
			var k := String(acquired[i])
			if k == a and ia == -1:
				ia = i
			elif k == b and ib == -1:
				ib = i
		if ia != -1 and ib != -1:
			claimed[ia] = true
			claimed[ib] = true
			out[ia] = colors[color_i]
			out[ib] = colors[color_i]
			color_i += 1
	return out

func _update_aux() -> void:
	if _aux_node == null or not is_instance_valid(_aux_node):
		_aux_node = get_tree().get_first_node_in_group("arena_aux")
	var owned: Array = []
	if _aux_node != null and is_instance_valid(_aux_node) and _aux_node.has_method("owned_aux"):
		owned = _aux_node.call("owned_aux")
	if _last_owned_n >= 0 and owned.size() > _last_owned_n:
		_trigger_shrink("Aux")   # a new aux → pop the Aux region to full, then re-shrink
	_last_owned_n = owned.size()
	for i in _aslots.size():
		var s = _aslots[i]
		if s == null:
			continue
		_set_vis(s.get("yellow"), false)   # btnyellow unused → always hidden
		var has: bool = i < owned.size()
		_set_vis(s.get("btn"), false)    # anchor only — btnblack is the always-visible base now, not btn
		_set_vis(s.get("black"), true)   # aux never fuses — always black, filled or empty
		var icon = s.get("icon")
		if has:
			var id := String(owned[i])
			var d: Dictionary = {}
			if _aux_node.has_method("def_for"):
				d = _aux_node.call("def_for", id)
			if icon != null and is_instance_valid(icon):
				var tex := _aux_icon_tex(id, d)
				(icon as TextureRect).texture = tex
				(icon as TextureRect).visible = tex != null
		elif icon != null and is_instance_valid(icon):
			(icon as CanvasItem).visible = false

func _set_vis(n, v: bool) -> void:
	if n != null and is_instance_valid(n):
		(n as CanvasItem).visible = v

## A weapon/aux icon TextureRect over `btn`: sized to SLOT_ICON_FIT of the btn, aspect-kept + centered.
func _make_slot_icon(btn, macro_key: String) -> TextureRect:
	if btn == null or not is_instance_valid(btn):
		return null
	var bc := btn as Control
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := bc.size * SLOT_ICON_FIT
	tr.size = box
	tr.position = bc.position + (bc.size - box) * 0.5   # centered inside the btn
	tr.z_index = (btn as CanvasItem).z_index
	tr.visible = false
	tr.set_meta("macro_key", macro_key)   # follow its btn's region (Weapon/Aux)
	_apply_blend_to(tr, SLOT_ICON_BLEND)
	_ed._objects_container.add_child(tr)
	_runtime_extras.append(tr)
	return tr

func _apply_blend_to(tr: TextureRect, blend_id: int) -> void:
	match blend_id:
		4:
			var ma := CanvasItemMaterial.new()
			ma.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			tr.material = ma
		5:
			var mm := CanvasItemMaterial.new()
			mm.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
			tr.material = mm
		1, 2, 3:
			var sm := ShaderMaterial.new()
			sm.shader = load(HUD_BLEND_SHADER)
			sm.set_shader_parameter("mode", blend_id - 1)   # 1→Screen(0), 2→HardLight(1), 3→Overlay(2)
			tr.material = sm
		6:
			var sl := ShaderMaterial.new()
			sl.shader = load(HUD_BLEND_SHADER)
			sl.set_shader_parameter("mode", 3)               # Lighten
			tr.material = sl
		_:
			tr.material = null

## HUD-btn weapon icon: prefer assets/inventory/icon/<kind>.png, falling back to WEAPON_INFO/FUSION_DEFS icon.
func _weapon_icon_tex(kind: String) -> Texture2D:
	if _weapon_icon_cache.has(kind):
		return _weapon_icon_cache[kind]
	var tex: Texture2D = _ed._load_tex(WEAPON_HUD_ICON_DIR + kind + ".png")   # dedicated HUD icon set
	if tex == null:
		var info: Dictionary = ArenaWeapons.WEAPON_INFO.get(kind, ArenaWeapons.FUSION_DEFS.get(kind, {}))
		var icon_path := String(info.get("icon", ""))
		if icon_path != "":
			tex = load(icon_path) as Texture2D
		if tex == null:
			tex = InventoryManager.get_icon(String(info.get("def_id", "")))
	_weapon_icon_cache[kind] = tex
	return tex

func _aux_icon_tex(id: String, d: Dictionary) -> Texture2D:
	if _aux_icon_cache.has(id):
		return _aux_icon_cache[id]
	var tex: Texture2D = null
	var path := String(d.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_aux_icon_cache[id] = tex
	return tex

## A shader "fill" TextureRect that occupies the band's exact rect and is MASKED by the band texture's
## alpha (bar_fill.gdshader). The band itself is edit-only; this masked fill is the visible bar.
func _make_bar_fill(ch: Dictionary, fill_col: Color, glow_col: Color) -> TextureRect:
	var id := int(ch.get("id", -1))
	var band = _ed._nodes.get(id)
	if band == null or not is_instance_valid(band):
		return null
	var bc := band as Control
	var tr := TextureRect.new()
	tr.texture = _ed._load_tex(_ed._item_path(String(ch.get("file", ""))))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE   # texture fills the rect → shader UV spans 0..1 over the band
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = bc.position
	tr.size = bc.size
	tr.z_index = (band as CanvasItem).z_index
	tr.visible = _ed._child_visible(id)   # follow the band's eye-toggle (design intent), not its edit-only hide
	tr.set_meta("macro_key", "LV")    # bars live in the bottom LV region
	var mat := ShaderMaterial.new()
	mat.shader = load(BAR_FILL_SHADER)
	mat.set_shader_parameter("fill_color", fill_col)
	mat.set_shader_parameter("glow_color", glow_col)
	mat.set_shader_parameter("grow_dir", int(ch.get("grow", 0)))
	tr.material = mat
	_ed._objects_container.add_child(tr)
	_runtime_extras.append(tr)
	return tr

## Independent lookup for the HUD 1.1 decorative shieldband1 pair — first occurrence's rect, z = the
## HIGHER of the 2 layers' z (so the VFX draws above both). Scans on its own; does not touch/read
## `roles`, `shieldband`, or _shield_fill.
func _find_shieldband1() -> Dictionary:
	var first: Dictionary = {}
	var max_z := -2147483648
	for g: Dictionary in _ed._groups:
		for ch: Dictionary in g.get("children", []):
			if String(ch.get("type", "")) == "item" and String(ch.get("file", "")) == SHIELDBAND1_FILE:
				if first.is_empty():
					first = ch
				max_z = maxi(max_z, int(ch.get("z", 0)))
	if first.is_empty():
		return {}
	var out := first.duplicate()
	out["z"] = max_z + 1
	return out

## Decorative sheen TextureRect over shieldband1's rect (shieldband1_vfx.gdshader — additive, masked
## by the sprite's own alpha so it stays cropped to shieldband1's silhouette). Own shader/material,
## separate node from the shieldband/_shield_fill mask-fill system above — but `_update_bindings()`
## drives its `progress` uniform from the same shield %, via the same `_set_fill_progress()` helper.
func _make_shieldband1_vfx(ch: Dictionary) -> TextureRect:
	var sz: Vector2 = ch.get("size", Vector2.ZERO)
	if sz == Vector2.ZERO:
		return null
	var tr := TextureRect.new()
	tr.texture = _ed._load_tex(_ed._item_path(String(ch.get("file", ""))))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = ch.get("pos", Vector2.ZERO)
	tr.size = sz
	tr.z_index = int(ch.get("z", 0))
	tr.set_meta("macro_key", "LV")   # shieldband1 lives in the bottom LV region
	var mat := ShaderMaterial.new()
	mat.shader = load(SHIELDBAND1_VFX_SHADER)
	tr.material = mat
	_ed._objects_container.add_child(tr)
	_runtime_extras.append(tr)
	return tr

# ── Macro regions (gameplay only): edge-anchored, uniformly-scalable groups ──────────────────────────
func _build_macros() -> void:
	_clear_macros()
	if _ed._objects_container == null or not is_instance_valid(_ed._objects_container):
		return
	var members: Dictionary = {}
	for k: String in MACRO_KEYS:
		members[k] = []
	# Design nodes → region by their editor group (Text group split by sentinel).
	for id in _ed._nodes:
		var n = _ed._nodes[id]
		if n == null or not is_instance_valid(n):
			continue
		var mk := _macro_for_child(int(id))
		if members.has(mk):
			(members[mk] as Array).append(n)
	# Runtime extras (icons/fills/buttons) → region by the tag set when they were created.
	for ex in _runtime_extras:
		if ex == null or not is_instance_valid(ex):
			continue
		var mk2 := String((ex as Node).get_meta("macro_key", ""))
		if members.has(mk2):
			(members[mk2] as Array).append(ex)
	for k: String in MACRO_KEYS:
		var mem: Array = members[k]
		if mem.is_empty():
			continue
		var container := Control.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ed._objects_container.add_child(container)
		# Container starts at identity, so keep_global_transform=true makes local pos == design pos.
		for n in mem:
			(n as Node).reparent(container, true)
		var bbox := _members_local_bbox(mem)
		var edge := String(MACRO_EDGE[k])
		var anchor_local := _edge_anchor_local(bbox, edge)
		var base: float = SHRINK_SCALE if String(MACRO_BEHAVIOR[k]) == "shrink" else 1.0
		container.scale = Vector2(base, base)
		_macros[k] = {"container": container, "edge": edge, "anchor_local": anchor_local, "behavior": String(MACRO_BEHAVIOR[k]), "tween": null}
	_update_macro_anchors()   # place each region flush to its edge for the initial scale
	# Reset change-detect baselines so the first gameplay frame doesn't fire a spurious pop.
	_last_acquired_n = _weapon_count()
	_last_owned_n = _aux_count()

## Keep each region's anchor edge flush against the screen for its CURRENT scale (called every frame).
func _update_macro_anchors() -> void:
	if _macros.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	for k in _macros:
		var m: Dictionary = _macros[k]
		var c = m.get("container")
		if c == null or not is_instance_valid(c):
			continue
		var s: float = (c as Control).scale.x
		var al: Vector2 = m.get("anchor_local", Vector2.ZERO)
		(c as Control).position = _edge_anchor_screen(vp, String(m.get("edge", ""))) - al * s

## Take every container's children back to the objects_container at their design positions, free containers.
func _clear_macros() -> void:
	for k in _macros:
		var m: Dictionary = _macros[k]
		var tw = m.get("tween")
		if tw != null and is_instance_valid(tw):
			(tw as Tween).kill()
		var c = m.get("container")
		if c == null or not is_instance_valid(c):
			continue
		for kid in (c as Node).get_children():
			(kid as Node).reparent(_ed._objects_container, false)
		(c as Node).queue_free()
	_macros.clear()

## Public (2026-08-06, on request): current on-screen bounding rect of macro region `key` ("Weapon"=left/
## "Aux"=right/"KillCoin"=top/"LV"=bottom, see MACRO_KEYS/MACRO_EDGE) — merges every member's OWN global
## rect, since the container itself never sets a "size" (position + scale only, see _build_macros()). Empty
## Rect2() if that region doesn't currently exist (no weapons/aux owned yet, HUD Edit mode open and macros
## torn down, etc.) — callers must treat an empty/zero-size rect as "nothing to avoid". Used by
## arena_ruin_pointer.gd to keep its edge-of-screen icon clear of HUD chrome (Weapon/Aux/LV bars).
## 2026-08-06 bug report: the ruin-pointer icon was rendering INSIDE the Weapon/Aux HUD bars instead of
## dodging them. Root cause — Control.get_global_rect() reports `size` in the control's own LOCAL
## (unscaled) units; it does NOT fold in any ancestor's `scale`. Weapon/Aux macros animate their container's
## scale between SHRINK_SCALE (0.7, resting) and 1.0 (held briefly on pickup — see MACRO_BEHAVIOR/
## _trigger_shrink), so the old per-kid get_global_rect() misjudged their true on-screen footprint by that
## same ~30% every time they weren't at exactly 1.0 scale. Fixed the way HudEditRuntime already fixes the
## identical class of bug (_control_rect_global()) — build the local-space union of every member's rect
## first, THEN map its 4 corners through the container's own get_global_transform_with_canvas() once, which
## correctly folds in position + scale together.
func macro_global_rect(key: String) -> Rect2:
	var m = _macros.get(key)
	if m == null:
		return Rect2()
	var c = m.get("container")
	if c == null or not is_instance_valid(c):
		return Rect2()
	var local_rect := Rect2()
	var has := false
	for kid in (c as Node).get_children():
		if kid is Control:
			var k := kid as Control
			var r := Rect2(k.position, k.size * k.scale)
			local_rect = r if not has else local_rect.merge(r)
			has = true
	if not has:
		return Rect2()
	var xform := (c as Control).get_global_transform_with_canvas()
	var p0 := xform * local_rect.position
	var p1 := xform * Vector2(local_rect.end.x, local_rect.position.y)
	var p2 := xform * local_rect.end
	var p3 := xform * Vector2(local_rect.position.x, local_rect.end.y)
	var minv := p0.min(p1).min(p2).min(p3)
	var maxv := p0.max(p1).max(p2).max(p3)
	return Rect2(minv, maxv - minv)

## Which macro region a design child belongs to ("" = none). The "Text" group is split by sentinel.
func _macro_for_child(child_id: int) -> String:
	var loc: Vector2i = _ed._find_child(child_id)
	if loc.x < 0:
		return ""
	var g: Dictionary = _ed._groups[loc.x]
	var gname := String(g.get("name", ""))
	if gname == "Text":
		var ch: Dictionary = (g["children"] as Array)[loc.y]
		return "KillCoin" if KILLCOIN_TEXTS.has(String(ch.get("text", ""))) else "LV"
	return String(GROUP_MACRO.get(gname, ""))

## Union rect of member nodes in their (design) local coords; individual node scale is 1 here.
func _members_local_bbox(mem: Array) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for n in mem:
		var c := n as Control
		if c == null:
			continue
		var p := c.position
		var sz := c.size * c.scale
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x + sz.x); mx.y = maxf(mx.y, p.y + sz.y)
	if mn.x == INF:
		return Rect2()
	return Rect2(mn, mx - mn)

## The bbox point that pins to the screen edge (outer edge on the anchor axis, centre on the other).
func _edge_anchor_local(b: Rect2, edge: String) -> Vector2:
	match edge:
		"left":   return Vector2(b.position.x, b.position.y + b.size.y * 0.5)
		"right":  return Vector2(b.position.x + b.size.x, b.position.y + b.size.y * 0.5)
		"top":    return Vector2(b.position.x + b.size.x * 0.5, b.position.y)
		_:        return Vector2(b.position.x + b.size.x * 0.5, b.position.y + b.size.y)   # bottom

## Where that anchor lands on screen: flush to the edge (minus margin), centred on the other axis.
func _edge_anchor_screen(vp: Vector2, edge: String) -> Vector2:
	match edge:
		"left":   return Vector2(MACRO_MARGIN, vp.y * 0.5)
		"right":  return Vector2(vp.x - MACRO_MARGIN, vp.y * 0.5)
		"top":    return Vector2(vp.x * 0.5, MACRO_MARGIN)
		_:        return Vector2(vp.x * 0.5, vp.y - MACRO_MARGIN)   # bottom

## Weapon/Aux: snap to full size, hold 5s, then ease back to SHRINK_SCALE. Restarts on each trigger.
func _trigger_shrink(key: String) -> void:
	var m = _macros.get(key)
	if m == null or String((m as Dictionary).get("behavior", "")) != "shrink":
		return
	var c = (m as Dictionary).get("container")
	if c == null or not is_instance_valid(c):
		return
	var old = (m as Dictionary).get("tween")
	if old != null and is_instance_valid(old):
		(old as Tween).kill()
	(c as Control).scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_interval(SHRINK_DELAY)
	tw.tween_property(c, "scale", Vector2(SHRINK_SCALE, SHRINK_SCALE), SHRINK_DUR)
	(m as Dictionary)["tween"] = tw

## KillCoin: quick 0.1s pop to PULSE_SCALE and back on each value change.
func _pulse_macro(key: String) -> void:
	var m = _macros.get(key)
	if m == null:
		return
	var c = (m as Dictionary).get("container")
	if c == null or not is_instance_valid(c):
		return
	var old = (m as Dictionary).get("tween")
	if old != null and is_instance_valid(old):
		(old as Tween).kill()
	(c as Control).scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(PULSE_SCALE, PULSE_SCALE), PULSE_DUR)
	tw.tween_property(c, "scale", Vector2.ONE, PULSE_DUR)
	(m as Dictionary)["tween"] = tw

func _weapon_count() -> int:
	if _weapons_node != null and is_instance_valid(_weapons_node) and _weapons_node.has_method("acquired_weapons"):
		return (_weapons_node.call("acquired_weapons") as Array).size()
	return 0

func _aux_count() -> int:
	if _aux_node != null and is_instance_valid(_aux_node) and _aux_node.has_method("owned_aux"):
		return (_aux_node.call("owned_aux") as Array).size()
	return 0

func _clear_runtime_extras() -> void:
	for n in _runtime_extras:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_runtime_extras.clear()
	_level_fill = null
	_hp_fill = null
	_shield_fill = null
	_shieldband1_vfx = null

## Re-show the design sentinel text ("200", "KILL", …) on the text nodes while editing.
func _restore_design_text() -> void:
	for g: Dictionary in _ed._groups:
		if String(g.get("name", "")) != "Text":
			continue
		for ch: Dictionary in g.get("children", []):
			if String(ch.get("type", "")) == "text":
				var n = _ed._nodes.get(int(ch.get("id", -1)))
				if n != null and is_instance_valid(n) and n.has_method("apply"):
					n.call("apply", ch, _ed._load_font(String(ch.get("font", ""))))
