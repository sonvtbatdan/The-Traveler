extends BoardBinder
class_name LevelUpBinder
## RUNTIME index for the authored LEVEL-UP board. The board is authored with the shared editor as named
## GROUPS holding indicator sprites + sentinel texts; `arena_levelup_ui.gd` keeps ALL its choice-generation
## / pick / apply logic and renders into these role nodes (weapon sprites on the frames, the option name/
## desc texts, the selected-item display, the stats list). If the board is empty the UI falls back to its
## built-in full-screen layout, so the working level-up is unchanged until the board is authored.
##
## Roles (Q: "sprite theo filename + text theo nội dung", scoped by group name — case-insensitive):
##   Group Weapon1/2/3   : item sprite file "WeaponFrame"  (indicator) — anchor for the choice's weapon sprite.
##   Group Upgrade1/2/3  : text "Upgrade Name" + "Upgrade Desc" (filled per option), item sprites
##                         "UpgradeName" + "UpgradeDesc" (indicators — define the text wrap width / centre).
##   Group WeaponDisplay : item "WeaponDisplay" (indicator) + texts "Codename" / "Full Name" / "Item Lore".
##   Group StatDisplay   : text "Weapon Stat" — replaced by the stats list.
## The indicator sprites are edit-only (hidden in gameplay) — see is_band_file().

const INDICATORS := {"WeaponFrame": true, "WeaponDisplay": true, "UpgradeName": true, "UpgradeDesc": true, "StatDisplay": true, "LoreDisplay": true}

# Resolved role nodes (rebuilt every build()).
var _wframes: Array = [null, null, null]        # Weapon1/2/3 → WeaponFrame node
var _wcode:   Array = [null, null, null]        # Weapon1/2/3 → "Codename" text node (per-choice code name)
var _uname:   Array = [null, null, null]        # Upgrade1/2/3 → "Upgrade Name" text node (style template + placement)
var _udesc:   Array = [null, null, null]        # Upgrade1/2/3 → "Upgrade Desc" text node
var _uname_sty: Array = [{}, {}, {}]            # Upgrade1/2/3 → style dict of the name text (font/size/color)
var _udesc_sty: Array = [{}, {}, {}]            # Upgrade1/2/3 → style dict of the desc text
var _uname_ind: Array = [null, null, null]      # Upgrade1/2/3 → "UpgradeName" indicator sprite (wrap width / centre)
var _udesc_ind: Array = [null, null, null]      # Upgrade1/2/3 → "UpgradeDesc" indicator sprite
var _disp_frame = null
var _disp_codename = null
var _disp_fullname = null
var _disp_lore = null
var _disp_lore_frame = null                    # "LoreDisplay" indicator sprite → wrap box for Item Lore
var _disp_lore_sty: Dictionary = {}            # style template of the Item Lore text (for the wrapped runtime label)
var _stat_text = null
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
	_wframes = [null, null, null]; _wcode = [null, null, null]
	_uname = [null, null, null]; _udesc = [null, null, null]
	_uname_sty = [{}, {}, {}]; _udesc_sty = [{}, {}, {}]
	_uname_ind = [null, null, null]; _udesc_ind = [null, null, null]
	_disp_frame = null; _disp_codename = null; _disp_fullname = null; _disp_lore = null; _disp_lore_frame = null; _disp_lore_sty = {}
	_stat_text = null
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
		elif ui >= 0:
			_uname[ui] = _text_node(children, "Upgrade Name")
			_udesc[ui] = _text_node(children, "Upgrade Desc")
			_uname_sty[ui] = _text_dict(children, "Upgrade Name")
			_udesc_sty[ui] = _text_dict(children, "Upgrade Desc")
			_uname_ind[ui] = _item_node(children, "UpgradeName")
			_udesc_ind[ui] = _item_node(children, "UpgradeDesc")
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
		elif name == "statdisplay":
			_stat_text = _text_node(children, "Weapon Stat")

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
func upg_name_text(i: int):    return _uname[i]       if i >= 0 and i < 3 else null
func upg_desc_text(i: int):    return _udesc[i]       if i >= 0 and i < 3 else null
func upg_name_style(i: int) -> Dictionary: return _uname_sty[i] if i >= 0 and i < 3 else {}
func upg_desc_style(i: int) -> Dictionary: return _udesc_sty[i] if i >= 0 and i < 3 else {}
func upg_name_ind(i: int):     return _uname_ind[i]   if i >= 0 and i < 3 else null
func upg_desc_ind(i: int):     return _udesc_ind[i]   if i >= 0 and i < 3 else null
func display_frame():          return _disp_frame
func display_codename():       return _disp_codename
func display_fullname():       return _disp_fullname
func display_lore():           return _disp_lore
func display_lore_frame():     return _disp_lore_frame
func display_lore_style() -> Dictionary: return _disp_lore_sty
func stat_text():              return _stat_text

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
