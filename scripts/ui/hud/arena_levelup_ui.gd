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

const TEX_FRAME := preload("res://assets/hud/lvupframe.png")
const TEX_GREEN := preload("res://assets/hud/lvgreen.png")
const TEX_RED   := preload("res://assets/hud/lvred.png")
const TEX_BLUE  := preload("res://assets/hud/lvblue.png")

const CHOICES := 3
# Chance a given card slot rolls from the owned-upgrade pool (vs the full new+owned pool). Higher = the player
# sees upgrades for what they already own more often, so picked items keep showing up. (Pivot §5 suggests this
# could scale with player_level — early lower, late higher; kept a flat tunable for now.)
const OWNED_UPGRADE_CHANCE := 0.65

# Weapon spawn weights for the NEW-weapon roll (rarer/special weapons → lower weight). Upgrade weight reuses these.
const WEAPON_WEIGHTS := {
	"gatling": 100, "lasgun": 80, "arc": 80, "gauss": 70,
	"orbital": 50, "void": 40, "red_x": 30, "chemtrail": 40,
	"nuke": 20, "sonic": 60, "zsword": 50, "ionize": 70,
	"boomerang": 50, "parasite": 50, "moroboshi": 30, "swarm": 40, "snake": 30,
	"homing": 60,
}
const WEAPON_FALLBACK_COLOR := Color(0.55, 0.62, 0.72)   # placeholder swatch if a weapon icon fails to load

var _pending: int = 0
var _showing: bool = false
var _current: Array = []   # the OPTIONS-row array that _pick() acts on (pool / capstone / destroy / single confirm)
var _choices: Array = []   # left-column offered items (tier-1), persistent for this screen
var _selected_idx: int = -1   # which left slot is currently selected
var _options_back: bool = false   # true while the All-In "destroy a weapon" sub-view shows (offers a back affordance)
var _capstone_weapon: String = ""    # the weapon being evolved (for the capstone / destroy screens)

# Node refs (full-screen layout).
var _root: Control = null
var _slot_nodes: Array = []        # the 3 left-column slot Controls
var _selected_box: Control = null  # center-top big-sprite panel
var _options_box: Control = null   # center-bottom options container
var _stats_box: VBoxContainer = null
var _title: Label = null

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
	_root.hide()
	if GameManager.has_signal("leveled_up"):
		GameManager.leveled_up.connect(_on_leveled_up)

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
	_show_cards()

func _show_cards() -> void:
	_choices = _generate_choices(CHOICES)
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
	_play_sfx("res://assets/audio/sfx/uialert.wav")
	_select_item(0)

## Legacy card-row render — stubbed; the full-screen path renders via _render_left/_render_options.
func _render_current() -> void:
	pass

## A centered sprite for a weapon/fusion def_id, or a colour swatch fallback (aux items have no art).
## The TextureRect keeps the texture's aspect (never stretched).
func _sprite_or_swatch(def_id: String, color: Color) -> Control:
	var tex: Texture2D = InventoryManager.get_icon(def_id) if def_id != "" else null
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
		slot_specs.append({"def": String(c.get("def_id", "")), "name": c["name"], "color": c.get("color", Color.GRAY), "idx": _choices.find(c), "fusion": false})
	for i in mini(slot_specs.size(), 3):
		_make_slot(_slot_nodes[i], slot_specs[i])

func _make_slot(slot: Control, spec: Dictionary) -> void:
	slot.visible = true
	var idx := int(spec["idx"])
	var is_fusion := bool(spec["fusion"])
	# Centered sprite (upper band of the slot).
	var spr := _sprite_or_swatch(String(spec["def"]), spec.get("color", Color.GRAY))
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
	var c: Dictionary = _choices[idx]
	if String(c.get("cat", "")) == "fusion":
		_select_fusion(c)   # bespoke A-top / FUSION / B-bottom view
		return
	_set_selected_display(String(c.get("def_id", "")), String(c["name"]), c.get("color", Color.GRAY))
	_title.text = String(c["name"])
	_route_options(c)
	_play_sfx("res://assets/audio/sfx/uiclick.wav")

## Fill the center-top panel with a big centered sprite + the item name.
func _set_selected_display(def_id: String, item_name: String, color: Color) -> void:
	for ch in _selected_box.get_children():
		ch.free()
	var spr := _sprite_or_swatch(def_id, color)
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

## Decide the bottom-row content for the selected choice and render it. Sets _current = the array _pick() acts on.
func _route_options(c: Dictionary) -> void:
	var cat := String(c.get("cat", ""))
	var key := String(c.get("key", ""))
	if cat == "weapon" and not _weapon_pool(key).is_empty():
		var aw := get_tree().get_first_node_in_group("arena_weapons")
		# Maxed weapon → its capstones become the options (EVOLVE). _show_capstone sets _current + renders.
		if aw != null and bool(aw.call("weapon_needs_capstone", key)):
			_show_capstone(key)
			return
		var pool_choices := _gen_pool_choices(key)
		_current = pool_choices if not pool_choices.is_empty() else [c]
		_render_options()
		return
	if cat == "aux" and not _aux_pool(key).is_empty():
		var ax := get_tree().get_first_node_in_group("arena_aux")
		if ax != null and bool(ax.call("aux_needs_capstone", key)):
			_show_aux_capstone(key)
			return
		var aux_choices := _gen_aux_pool_choices(key)
		_current = aux_choices if not aux_choices.is_empty() else [c]
		_render_options()
		return
	# New weapon / poolless weapon / simple aux → a single Confirm panel.
	_current = [c]
	_render_options()

## Render _current into _options_box: 1 item → full-width confirm; N → N equal boxes. Adds a Back box in the
## All-In destroy sub-view (_options_back).
func _render_options() -> void:
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

# Card layout constants — keep in sync with custom_minimum_size in _make_card().
const _CW    := 160.0   # card width
const _CH    := 208.0   # card height
const _CGAP  := 10.0    # gap between cards
const _CSHIFT := 20.0   # left card shifts left / right card shifts right by this amount

func _position_cards() -> void:
	pass   # legacy card positioning — superseded by anchor-based full-screen layout (removed in cleanup)

func _bg_tex(cat: String) -> Texture2D:
	# Weapons use the red frame; aux items the green. (Blue kept for any future third class.)
	match cat:
		"weapon": return TEX_RED
		"pool":   return TEX_RED   # weapon sub-upgrade → red frame like its weapon
		"capstone": return TEX_BLUE   # evolve → blue (gold-tinted + pulsed in _make_card)
		"destroy":  return TEX_RED
		"aux":    return TEX_GREEN
		"aux_pool": return TEX_GREEN   # aux sub-upgrade → green frame like its item
		"fusion": return TEX_BLUE   # the (otherwise-unused) blue frame, gold-tinted + pulsed in _make_card
		_:        return TEX_BLUE

func _make_card(c: Dictionary, idx: int) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(160, 208)

	# Background texture (fills entire card)
	var bg := TextureRect.new()
	bg.texture = _bg_tex(String(c["cat"]))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(bg)

	# Icon — weapons load their inventory icon; aux items show a placeholder colour swatch (no art yet).
	var icon_node := _make_icon(c)
	icon_node.anchor_left   = 0.255
	icon_node.anchor_right  = 0.745
	icon_node.anchor_top    = 0.158
	icon_node.anchor_bottom = 0.473
	card.add_child(icon_node)
	card.set_meta("icon_tex", icon_node)

	# Name label — always visible (items have no recognisable art, so the name carries the card).
	var lbl_name := _styled_label(String(c["name"]), 15)
	lbl_name.anchor_left   = 0.05
	lbl_name.anchor_right  = 0.95
	lbl_name.anchor_top    = 0.26
	lbl_name.anchor_bottom = 0.38
	card.add_child(lbl_name)

	# Effect label — action + effect by default (e.g. "NEW\n+20 Max HP" or "Lv 2 → 3\n+10% Damage").
	var lbl_effect := _styled_label(_default_text(c), 14)
	lbl_effect.anchor_left   = 0.05
	lbl_effect.anchor_right  = 0.95
	lbl_effect.anchor_top    = 0.70
	lbl_effect.anchor_bottom = 0.92
	card.add_child(lbl_effect)
	card.set_meta("lbl_effect", lbl_effect)

	# Current-status label — shown on hover (e.g. "Owned Lv 2" / "Not owned yet").
	var lbl_current := _styled_label(_current_text(c), 14)
	lbl_current.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	lbl_current.anchor_left   = 0.05
	lbl_current.anchor_right  = 0.95
	lbl_current.anchor_top    = 0.70
	lbl_current.anchor_bottom = 0.92
	lbl_current.visible = false
	card.add_child(lbl_current)
	card.set_meta("lbl_current", lbl_current)

	# Invisible button — full-rect click capture
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(_pick.bind(idx))
	btn.mouse_entered.connect(_on_card_hover.bind(card))
	btn.mouse_exited.connect(_on_card_unhover.bind(card))
	card.add_child(btn)

	# FUSION cards look distinct + alive: gold tint on the blue frame, a special title, and a slow pulse.
	if String(c["cat"]) == "fusion":
		bg.modulate = Color(1.6, 1.25, 0.5)
		lbl_name.text = "✦ %s ✦" % String(c["name"])
		lbl_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		var pulse := card.create_tween().set_loops()
		pulse.tween_property(bg, "modulate", Color(2.0, 1.6, 0.7), 0.6).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(bg, "modulate", Color(1.6, 1.25, 0.5), 0.6).set_trans(Tween.TRANS_SINE)

	return card

func _make_icon(c: Dictionary) -> Control:
	# Fusion card: until the fused icon art lands, show the two source icons side-by-side with a "+".
	if String(c["cat"]) == "fusion":
		var box := HBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 2)
		box.add_child(_icon_rect(String(c.get("def_a", ""))))
		var plus := Label.new()
		plus.text = "+"
		plus.add_theme_font_override("font", load("res://assets/fonts/Good Old DOS.ttf"))
		plus.add_theme_font_size_override("font_size", 20)
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(plus)
		box.add_child(_icon_rect(String(c.get("def_b", ""))))
		return box
	if String(c["cat"]) in ["weapon", "pool", "capstone", "destroy"]:
		var def_id := String(c.get("def_id", ""))
		var tex: Texture2D = InventoryManager.get_icon(def_id) if def_id != "" else null
		if tex != null:
			var icon_tex := TextureRect.new()
			icon_tex.texture = tex
			icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return icon_tex
	# Aux item (or missing weapon icon) → coloured placeholder swatch.
	var swatch := ColorRect.new()
	swatch.color = c.get("color", Color.GRAY)
	return swatch

## A single weapon icon (used for the fusion card's two source icons). Falls back to a gold swatch.
func _icon_rect(def_id: String) -> Control:
	var tex: Texture2D = InventoryManager.get_icon(def_id) if def_id != "" else null
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(40, 40)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tr
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(40, 40)
	sw.color = Color(1.0, 0.82, 0.30)
	return sw

func _styled_label(text: String, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_font_override("font", load("res://assets/fonts/Good Old DOS.ttf"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl

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
			if bool(aw.call("weapon_needs_capstone", wk)):
				_show_capstone(wk)   # the weapon just hit max level → evolve! (don't consume the level-up yet)
				return
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
	if kind == "gatling":
		return ArenaWeapons.GATLING_POOL
	if kind == "lasgun":
		return ArenaWeapons.LASGUN_POOL
	if kind == "arc":
		return ArenaWeapons.ARC_POOL
	if kind == "gauss":
		return ArenaWeapons.GAUSS_POOL
	if kind == "orbital":
		return ArenaWeapons.ORBITAL_POOL
	if kind == "red_x":
		return ArenaWeapons.DRAGON_POOL
	if kind == "chemtrail":
		return ArenaWeapons.CHEMTRAIL_POOL
	if kind == "zsword":
		return ArenaWeapons.ZSWORD_POOL
	if kind == "sonic":
		return ArenaWeapons.SONIC_POOL
	return {}

## Show 3 random, not-maxed upgrades from `kind`'s pool, reusing the card layout. A back arrow returns here.
func _show_pool(kind: String) -> void:
	var pool_choices := _gen_pool_choices(kind)
	if pool_choices.is_empty():
		# Everything maxed → just spend the point (level progress) and move on.
		var aw := get_tree().get_first_node_in_group("arena_weapons")
		if aw != null:
			aw.call("spend_weapon_point", kind)
		_pending -= 1
		if _pending > 0:
			_show_cards()
		else:
			_finish()
		return
	_current = pool_choices
	_title.text = "%s — choose an upgrade" % String((ArenaWeapons.WEAPON_INFO as Dictionary).get(kind, {}).get("label", kind))
	_render_current()
	_play_sfx("res://assets/audio/sfx/uiclick.wav")

func _gen_pool_choices(kind: String) -> Array:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	var pool := _weapon_pool(kind)
	var avail: Array = []
	for id: String in pool.keys():
		var maxr := int(pool[id]["max"])
		var rank: int = int(aw.call("pool_rank", kind, id)) if aw != null else 0
		if maxr > 0 and rank >= maxr:
			continue   # this upgrade is maxed → don't offer it
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

## Show 3 random, not-maxed perks from the aux item's pool. A back arrow returns to the 1st tier.
func _show_aux_pool(id: String) -> void:
	var pool_choices := _gen_aux_pool_choices(id)
	if pool_choices.is_empty():
		# Everything maxed → just spend the point (level progress) and move on.
		var ax := get_tree().get_first_node_in_group("arena_aux")
		if ax != null:
			ax.call("spend_aux_point", id)
		_advance()
		return
	_current = pool_choices
	var ax2 := get_tree().get_first_node_in_group("arena_aux")
	var nm: String = String((ax2.call("def_for", id) as Dictionary).get("name", id)) if ax2 != null else id
	_title.text = "%s — choose an upgrade" % nm
	_render_current()
	_play_sfx("res://assets/audio/sfx/uiclick.wav")

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

func _finish_capstone() -> void:
	_back_target = "tier1"
	if _back_btn != null:
		_back_btn.visible = false
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
			return "NEW WEAPON"
		return "NEW\n%s" % String(c.get("effect", ""))
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

# ── Hover effects ───────────────────────────────────────────────────────────────
func _on_card_hover(card: Control) -> void:
	card.scale    = Vector2(1.03, 1.03)
	card.modulate = Color(1.03, 1.03, 1.03)
	_play_sfx("res://assets/audio/sfx/uiclick.wav")
	if card.has_meta("icon_tex"):
		(card.get_meta("icon_tex") as CanvasItem).modulate.a = 0.35
	if card.has_meta("lbl_effect"):
		(card.get_meta("lbl_effect") as CanvasItem).visible = false
	if card.has_meta("lbl_current"):
		(card.get_meta("lbl_current") as CanvasItem).visible = true

func _on_card_unhover(card: Control) -> void:
	card.scale    = Vector2.ONE
	card.modulate = Color.WHITE
	if card.has_meta("icon_tex"):
		(card.get_meta("icon_tex") as CanvasItem).modulate.a = 1.0
	if card.has_meta("lbl_effect"):
		(card.get_meta("lbl_effect") as CanvasItem).visible = true
	if card.has_meta("lbl_current"):
		(card.get_meta("lbl_current") as CanvasItem).visible = false

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

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.06, 0.97)   # near-opaque: the level-up takes the whole screen
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

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
	var gm := GameManager
	if gm.has_method("get_damage_mult"):
		_stats_box.add_child(_make_stat_row("Damage", "x%.2f" % gm.get_damage_mult()))
	if gm.has_method("get_fire_rate_mult"):
		_stats_box.add_child(_make_stat_row("Fire rate", "x%.2f" % gm.get_fire_rate_mult()))
	if gm.has_method("get_crit_chance"):
		_stats_box.add_child(_make_stat_row("Crit chance", "%d%%" % int(round(gm.get_crit_chance() * 100.0))))
	if gm.has_method("get_crit_damage"):
		_stats_box.add_child(_make_stat_row("Crit damage", "x%.2f" % gm.get_crit_damage()))
	if gm.has_method("get_move_speed_mult"):
		_stats_box.add_child(_make_stat_row("Move speed", "x%.2f" % gm.get_move_speed_mult()))
	if gm.has_method("get_pickup_radius"):
		_stats_box.add_child(_make_stat_row("Pickup", "%d" % int(round(gm.get_pickup_radius()))))
	if gm.has_method("get_base_defense"):
		_stats_box.add_child(_make_stat_row("Armor (flat)", "%d" % gm.get_base_defense()))
	if gm.has_method("get_momentum_mult"):
		_stats_box.add_child(_make_stat_row("Momentum", "x%.2f" % gm.get_momentum_mult()))
	# Probe optional stats that may not exist yet (HP, AOE, armor pen). Add rows only if present.
	if gm.has_method("get_max_hp"):
		_stats_box.add_child(_make_stat_row("HP", "%d" % int(gm.get_max_hp())))
	if gm.has_method("get_aoe_mult"):
		_stats_box.add_child(_make_stat_row("AOE", "x%.2f" % gm.get_aoe_mult()))
	if gm.has_method("get_armor_pen_pct"):
		_stats_box.add_child(_make_stat_row("Armor pen %", "%d%%" % int(round(gm.get_armor_pen_pct() * 100.0))))
	if gm.has_method("get_armor_pen_flat"):
		_stats_box.add_child(_make_stat_row("Armor pen flat", "%d" % int(gm.get_armor_pen_flat())))

func _make_stat_row(label: String, value: String) -> Control:
	var row := HBoxContainer.new()
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
	return row
