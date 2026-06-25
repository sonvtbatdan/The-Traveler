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
var _root: Control = null
var _cards_box: Control = null
var _current: Array = []   # the choice dicts currently offered

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
	_current = _generate_choices(CHOICES)
	for c in _cards_box.get_children():
		if is_instance_valid(c):
			c.free()   # free immediately so _position_cards() only counts the new cards
	if _current.is_empty():
		# Nothing left to offer (everything owned + maxed) — silently skip this level-up.
		_pending -= 1
		if _pending > 0:
			_show_cards()
		else:
			_finish()
		return
	for i in _current.size():
		_cards_box.add_child(_make_card(_current[i], i))
	_position_cards()
	_root.show()
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
	var cards := _cards_box.get_children()
	# Use actual resolved size; fall back to anchor × panel size if layout not yet computed.
	var box_w := _cards_box.size.x if _cards_box.size.x > 1.0 else (_cards_box.anchor_right  - _cards_box.anchor_left) * 720.0
	var box_h := _cards_box.size.y if _cards_box.size.y > 1.0 else (_cards_box.anchor_bottom - _cards_box.anchor_top)  * 390.0
	var cluster_w := _CW * cards.size() + _CGAP * (cards.size() - 1)
	var base_x    := (box_w - cluster_w) * 0.5
	var base_y    := (box_h - _CH) * 0.5 - 22.0
	for i in cards.size():
		var x := base_x + i * (_CW + _CGAP)
		if i == 0:
			x -= _CSHIFT
		elif i == cards.size() - 1:
			x += _CSHIFT
		var c := cards[i] as Control
		c.position     = Vector2(x, base_y)
		c.size         = Vector2(_CW, _CH)
		c.pivot_offset = Vector2(_CW * 0.5, _CH * 0.5)   # scale from center on hover

func _bg_tex(cat: String) -> Texture2D:
	# Weapons use the red frame; aux items the green. (Blue kept for any future third class.)
	match cat:
		"weapon": return TEX_RED
		"aux":    return TEX_GREEN
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
	if String(c["cat"]) == "weapon":
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
	_apply(c)
	_pending -= 1
	if _pending > 0:
		_show_cards()   # next queued level-up
	else:
		_finish()

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
	if String(c["action"]) == "fuse":
		return String(c.get("effect", "FUSE"))
	if String(c["action"]) == "new":
		# A new weapon is conveyed by its icon + name; aux items also show what the passive grants.
		if String(c["cat"]) == "weapon":
			return "NEW WEAPON"
		return "NEW\n%s" % String(c.get("effect", ""))
	return "Lv %d → %d\n%s" % [lvl, lvl + 1, String(c.get("effect", ""))]

func _current_text(c: Dictionary) -> String:
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
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	# Fixed-size panel matching lvupframe proportions (~700×384 native)
	var panel := Control.new()
	panel.custom_minimum_size = Vector2(800, 433)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)

	# lvupframe as panel background (full-rect)
	var panel_bg := TextureRect.new()
	panel_bg.texture = TEX_FRAME
	panel_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_bg.stretch_mode = TextureRect.STRETCH_SCALE
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(panel_bg)

	# Title label — inside the teal bar slot at the top of lvupframe (~12%–88% wide, 3.5%–15% tall)
	var title := Label.new()
	title.text = "LEVEL UP — choose an item"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_font_override("font", load("res://assets/fonts/Good Old DOS.ttf"))
	title.add_theme_color_override("font_color", Color("#E5792A"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left   = 0.0
	title.anchor_right  = 1.0
	title.anchor_top    = 0.035
	title.anchor_bottom = 0.155
	title.offset_top    = 38
	title.offset_bottom = 38
	title.offset_left   = -10
	title.offset_right  = -10
	panel.add_child(title)

	# Cards area — plain Control so we can position each card manually
	_cards_box = Control.new()
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_box.anchor_left   = 0.025
	_cards_box.anchor_right  = 0.975
	_cards_box.anchor_top    = 0.19
	_cards_box.anchor_bottom = 0.97
	panel.add_child(_cards_box)
