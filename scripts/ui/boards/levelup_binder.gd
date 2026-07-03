extends BoardBinder
class_name LevelUpBinder
## RUNTIME index for the authored LEVEL-UP board. The board is authored with the shared editor as named
## GROUPS holding indicator sprites + sentinel texts; `arena_levelup_ui.gd` keeps ALL its choice-generation
## / pick / apply logic and renders into these role nodes (weapon sprites on the frames, the option name/
## desc texts, the selected-item display, the stats list). If the board is empty the UI falls back to its
## built-in full-screen layout, so the working level-up is unchanged until the board is authored.
##
## Roles (Q: "sprite theo filename + text theo nội dung", scoped by group name — case-insensitive):
##   Group Weapon1/2/3   : item sprites "WeaponFrame" (anchor for the choice's weapon sprite) + "CodeName"
##                         (anchor to horizontally centre the "Codename" text on). Both stay VISIBLE in
##                         gameplay (real frame/name-plate art, not hidden placeholders) — see FRAME_LAYERS.
##   Group Upgrade1/2/3  : text "Upgrade Name" (filled per option) + item sprites "UpgradeName" (wrap box,
##                         visible in gameplay) / "UpgradeIcon" (the option's icon/swatch rect, visible in
##                         gameplay). No per-slot desc anymore — details for the currently-selected option
##                         render into the single UpgradeDesc box.
##   Group WeaponDisplay : item "WeaponDisplay" (indicator, hidden in gameplay) + texts "Codename" / "Full
##                         Name" / "Item Lore" + item "LoreDisplay" (wrap box, visible in gameplay — real
##                         lore-panel art, the Item Lore runtime label draws on top of it).
##   Group StatDisplay   : text "Weapon Stat" (replaced by the stats list) + text "Upgrade Desc" / item
##                         "UpgradeDesc" (wrap box, visible in gameplay — the selected option's stat text
##                         runtime label draws on top of it).
##   Group Confirm       : item sprites "confirm" (normal) / "confirmpress" (pressed) — 2-state commit button.
## Indicator sprites in INDICATORS are edit-only (hidden in gameplay, replaced by runtime content) — see
## is_band_file(). FRAME_LAYERS are the opposite: real decorative art that stays visible in gameplay AND
## doubles as an editor placement anchor — runtime content draws ON TOP of them, not instead of them.

const INDICATORS := {"WeaponDisplay": true, "StatDisplay": true}

# Resolved role nodes (rebuilt every build()).
var _wframes: Array = [null, null, null]        # Weapon1/2/3 → WeaponFrame node
var _wcode:   Array = [null, null, null]        # Weapon1/2/3 → "Codename" text node (per-choice code name)
var _wcode_ind: Array = [null, null, null]      # Weapon1/2/3 → "CodeName" sprite (centre the codename text on it)
var _uname:   Array = [null, null, null]        # Upgrade1/2/3 → "Upgrade Name" text node (style template + placement)
var _uname_sty: Array = [{}, {}, {}]            # Upgrade1/2/3 → style dict of the name text (font/size/color)
var _uname_ind: Array = [null, null, null]      # Upgrade1/2/3 → "UpgradeName" indicator sprite (wrap width / centre)
var _uicon_ind: Array = [null, null, null]      # Upgrade1/2/3 → "UpgradeIcon" indicator sprite (icon rect)
var _uicon_text: Array = [null, null, null]     # Upgrade1/2/3 → "Upgrade Icon" sentinel text (hidden; label only)
var _disp_frame = null
var _disp_codename = null
var _disp_fullname = null
var _disp_lore = null
var _disp_lore_frame = null                    # "LoreDisplay" indicator sprite → wrap box for Item Lore
var _disp_lore_sty: Dictionary = {}            # style template of the Item Lore text (for the wrapped runtime label)
var _main_display = null                       # "MainDisplay" sprite (WeaponDisplay group) — ambient VFX target
var _stat_text = null
var _stat_display_ind = null                   # "StatDisplay" sprite (StatDisplay group) — ambient VFX target
var _updesc_text = null                         # single "Upgrade Desc" sentinel text (style template; hidden)
var _updesc_ind = null                          # single "UpgradeDesc" indicator sprite → wrap box
var _updesc_sty: Dictionary = {}
var _confirm_on = null                          # "confirm" sprite (normal state)
var _confirm_press = null                       # "confirmpress" sprite (pressed state)
var _runtime: Array = []                         # runtime nodes the UI spawns onto the host (freed on clear)

## Indicator sprites are edit-only: the editor/host hides them in gameplay (their content is drawn by the UI).
func is_band_file(file: String) -> bool:
	return INDICATORS.has(file)

func build() -> void:
	_index()

func clear() -> void:
	clear_runtime()

func has_layout() -> bool:
	return _ed != null and not (_ed._groups as Array).is_empty()

# ── Role index ───────────────────────────────────────────────────────────────────────
func _index() -> void:
	_wframes = [null, null, null]; _wcode = [null, null, null]; _wcode_ind = [null, null, null]
	_uname = [null, null, null]
	_uname_sty = [{}, {}, {}]
	_uname_ind = [null, null, null]
	_uicon_ind = [null, null, null]; _uicon_text = [null, null, null]
	_disp_frame = null; _disp_codename = null; _disp_fullname = null; _disp_lore = null; _disp_lore_frame = null; _disp_lore_sty = {}
	_main_display = null
	_stat_text = null; _stat_display_ind = null
	_updesc_text = null; _updesc_ind = null; _updesc_sty = {}
	_confirm_on = null; _confirm_press = null
	if _ed == null:
		return
	for gi: int in (_ed._groups as Array).size():
		var g: Dictionary = _ed._groups[gi]
		var name := String(g.get("name", "")).strip_edges().to_lower()
		var children: Array = g.get("children", [])
		var wi := _slot_index(name, "weapon")
		var ui := _slot_index(name, "upgrade")
		if wi >= 0:
			_wframes[wi] = _item_node(children, "WeaponFrame")
			_wcode[wi] = _text_node(children, "Codename")
			_wcode_ind[wi] = _item_node(children, "CodeName")
		elif ui >= 0:
			_uname[ui] = _text_node(children, "Upgrade Name")
			_uname_sty[ui] = _text_dict(children, "Upgrade Name")
			_uname_ind[ui] = _item_node(children, "UpgradeName")
			_uicon_ind[ui] = _item_node(children, "UpgradeIcon")
			_uicon_text[ui] = _text_node(children, "Upgrade Icon")
		elif name == "weapondisplay":
			_disp_frame = _item_node(children, "WeaponDisplay")
			_disp_codename = _text_node(children, "Codename")
			_disp_fullname = _text_node(children, "Full Name")
			_disp_lore = _text_node(children, "Item Lore")
			_disp_lore_sty = _text_dict(children, "Item Lore")
			if _disp_lore == null:
				_disp_lore = _text_node(children, "Lore")
				_disp_lore_sty = _text_dict(children, "Lore")
			_disp_lore_frame = _item_node(children, "LoreDisplay")
			_main_display = _item_node(children, "MainDisplay")
		elif name == "statdisplay":
			_stat_text = _text_node(children, "Weapon Stat")
			_stat_display_ind = _item_node(children, "StatDisplay")
			_updesc_text = _text_node(children, "Upgrade Desc")
			_updesc_ind = _item_node(children, "UpgradeDesc")
			_updesc_sty = _text_dict(children, "Upgrade Desc")
		elif name == "confirm":
			_confirm_on = _item_node(children, "confirm")
			_confirm_press = _item_node(children, "confirmpress")

## "weapon1".."weapon3" / "upgrade1".."upgrade3" → 0..2, else -1.
func _slot_index(name: String, prefix: String) -> int:
	if not name.begins_with(prefix):
		return -1
	var tail := name.substr(prefix.length())
	if tail in ["1", "2", "3"]:
		return int(tail) - 1
	return -1

func _item_node(children: Array, fname: String):
	for ch: Dictionary in children:
		if String(ch.get("type", "")) == "item" and String(ch.get("file", "")) == fname:
			return _ed._nodes.get(int(ch.get("id", -1)))
	return null

## Normalize a sentinel for matching: lower-case + spaces removed, so "Code Name" == "Codename", etc.
func _norm(s: String) -> String:
	return s.strip_edges().to_lower().replace(" ", "")

func _text_node(children: Array, txt: String):
	var want := _norm(txt)
	for ch: Dictionary in children:
		if String(ch.get("type", "")) == "text" and _norm(String(ch.get("text", ""))) == want:
			return _ed._nodes.get(int(ch.get("id", -1)))
	return null

## The authored child DICT for a sentinel text (font/font_size/color/outline… used as a style template).
func _text_dict(children: Array, txt: String) -> Dictionary:
	var want := _norm(txt)
	for ch: Dictionary in children:
		if String(ch.get("type", "")) == "text" and _norm(String(ch.get("text", ""))) == want:
			return ch
	return {}

# ── Getters used by arena_levelup_ui ─────────────────────────────────────────────────
func weapon_frame(i: int):     return _wframes[i]     if i >= 0 and i < 3 else null
func weapon_codename(i: int):  return _wcode[i]       if i >= 0 and i < 3 else null
func weapon_codename_ind(i: int): return _wcode_ind[i] if i >= 0 and i < 3 else null
func upg_name_text(i: int):    return _uname[i]       if i >= 0 and i < 3 else null
func upg_name_style(i: int) -> Dictionary: return _uname_sty[i] if i >= 0 and i < 3 else {}
func upg_name_ind(i: int):     return _uname_ind[i]   if i >= 0 and i < 3 else null
func upg_icon_ind(i: int):     return _uicon_ind[i]   if i >= 0 and i < 3 else null
func upg_icon_text(i: int):    return _uicon_text[i]  if i >= 0 and i < 3 else null
func display_frame():          return _disp_frame
func display_codename():       return _disp_codename
func display_fullname():       return _disp_fullname
func display_lore():           return _disp_lore
func display_lore_frame():     return _disp_lore_frame
func display_lore_style() -> Dictionary: return _disp_lore_sty
func main_display():           return _main_display
func stat_text():              return _stat_text
func stat_display_ind():       return _stat_display_ind
func updesc_text():            return _updesc_text
func updesc_ind():             return _updesc_ind
func updesc_style() -> Dictionary: return _updesc_sty
func confirm_normal():         return _confirm_on
func confirm_press():          return _confirm_press

## Bounding box (screen coords) of a group by name, or empty Rect2.
func group_rect(name: String) -> Rect2:
	if _ed == null:
		return Rect2()
	var want := name.strip_edges().to_lower()
	for gi: int in (_ed._groups as Array).size():
		if String((_ed._groups[gi] as Dictionary).get("name", "")).strip_edges().to_lower() == want:
			return _ed._group_bbox(gi)
	return Rect2()

## Host container to parent runtime nodes onto (renders at the host's CanvasLayer, i.e. behind the cards).
func container() -> Control:
	return _ed._objects_container if _ed != null else null

func add_runtime(n: Node) -> void:
	if container() != null:
		container().add_child(n)
		_runtime.append(n)

func clear_runtime() -> void:
	for n in _runtime:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_runtime.clear()
