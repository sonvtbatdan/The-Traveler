extends Button

signal pressed_id(upgrade_id: String)

@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label      = %NameLabel
@onready var price_label: Label     = %PriceLabel
@onready var count_label: Label     = %CountLabel

var upgrade_id: String = ""
var _desc_popup: PanelContainer = null
var _desc_layer: CanvasLayer    = null
var _desc_rtl:   RichTextLabel  = null

func setup(id: String) -> void:
	upgrade_id = id
	var data: Dictionary = UpgradeManager.UPGRADES[id]
	name_label.text = data["name"]

	if data.has("icon"):
		var folder: String = "res://assets/sprites/comments/" if data.get("tab") == "defense" else "res://assets/sprites/upgrades/"
		var tex := load(folder + String(data["icon"])) as Texture2D
		if tex:
			icon_rect.texture = tex

	_build_desc_popup()
	_apply_styles()
	GameManager.stable_views_changed.connect(_on_stable_views_changed)
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_state()

func _build_desc_popup() -> void:
	_desc_popup = PanelContainer.new()
	_desc_popup.visible = false
	_desc_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_popup.z_index = 100

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.10, 0.96)
	s.border_width_left   = 1; s.border_width_right  = 1
	s.border_width_top    = 1; s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.5, 0.7, 0.8)
	s.corner_radius_top_left    = 4; s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	s.content_margin_left = 8.0; s.content_margin_right  = 8.0
	s.content_margin_top  = 6.0; s.content_margin_bottom = 6.0
	_desc_popup.add_theme_stylebox_override("panel", s)

	_desc_rtl = RichTextLabel.new()
	_desc_rtl.bbcode_enabled = true
	_desc_rtl.fit_content    = true
	_desc_rtl.scroll_active  = false
	_desc_rtl.custom_minimum_size = Vector2(210.0, 0.0)
	_desc_rtl.add_theme_color_override("default_color", Color(0.82, 0.9, 1.0))
	_desc_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_rtl.add_theme_font_size_override("normal_font_size",       10)
	_desc_rtl.add_theme_font_size_override("italics_font_size",      10)
	_desc_rtl.add_theme_font_size_override("bold_font_size",         10)
	_desc_rtl.add_theme_font_size_override("bold_italics_font_size", 10)
	_desc_popup.add_child(_desc_rtl)

	_desc_layer = CanvasLayer.new()
	_desc_layer.layer = 15
	_desc_layer.add_child(_desc_popup)

func _update_desc() -> void:
	if _desc_rtl == null:
		return
	_desc_rtl.text = _build_desc_content()

func _hl(s: String) -> String:
	return "[b][color=#ffd84d]" + s + "[/color][/b]"

func _build_desc_content() -> String:
	var data: Dictionary = UpgradeManager.UPGRADES[upgrade_id]
	var tab       := String(data.get("tab", "weaponry"))
	var item_name := String(data["name"])
	var desc_txt  := String(data.get("desc", ""))
	var owned     := UpgradeManager.get_owned_count(upgrade_id)
	var spent     := _calc_views_spent()

	var lines: PackedStringArray = []
	lines.append("[b]" + item_name + "[/b]")
	lines.append("owned: " + _hl(str(owned)))
	lines.append(_hl(GameManager.format_views(spent)) + " fuel spent total")
	lines.append("[i]\"" + desc_txt + "\"[/i]")

	if tab == "weaponry":
		var global_mult := EquipmentManager.get_global_vps_multiplier()
		var total_vps   := GameManager.vps * global_mult
		if data.has("vps"):
			var eq_mult        := EquipmentManager.get_multiplier_for_upgrade(upgrade_id)
			var vps_each       := float(data["vps"]) * eq_mult
			var item_total_vps := float(owned) * vps_each * global_mult
			var pct            := (item_total_vps / total_vps * 100.0) if total_vps > 0.0 else 0.0
			var eq_tag         := (" [color=#aaddff](×%.4g eq)[/color]" % eq_mult) if eq_mult != 1.0 else ""
			lines.append("Each " + item_name + " produces " + _hl(GameManager.format_views(int(vps_each))) + " FPS" + eq_tag)
			lines.append(_hl(str(owned)) + " " + item_name + " producing " +
				_hl(GameManager.format_views(int(item_total_vps))) + " FPS (" + _hl("%.1f%%" % pct) + " of total)")
		var fuel_so_far := UpgradeManager.get_views_produced(upgrade_id)
		lines.append(_hl(GameManager.format_views(int(fuel_so_far))) + " fuel produced so far")

	return "\n".join(lines)

func _calc_views_spent() -> int:
	var data: Dictionary = UpgradeManager.UPGRADES[upgrade_id]
	var base  := float(data["cost"])
	var n     := UpgradeManager.get_owned_count(upgrade_id)
	var total := 0.0
	for i in n:
		total += ceil(base * pow(UpgradeManager.PRICE_SCALE, float(i)))
	return int(total)

func _apply_styles() -> void:
	var _make := func(bg: Color, border: Color, corner: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left   = 1
		s.border_width_right  = 1
		s.border_width_top    = 1
		s.border_width_bottom = 1
		s.border_color = border
		s.corner_radius_top_left     = corner
		s.corner_radius_top_right    = corner
		s.corner_radius_bottom_left  = corner
		s.corner_radius_bottom_right = corner
		return s

	add_theme_stylebox_override("normal",   _make.call(Color(0.07, 0.09, 0.13, 0.95), Color(0.35, 0.45, 0.65, 0.90), 6))
	add_theme_stylebox_override("hover",    _make.call(Color(0.10, 0.13, 0.20, 0.95), Color(0.50, 0.65, 0.85, 0.95), 6))
	add_theme_stylebox_override("pressed",  _make.call(Color(0.05, 0.07, 0.10, 0.95), Color(0.35, 0.45, 0.65, 0.80), 6))
	add_theme_stylebox_override("disabled", _make.call(Color(0.05, 0.06, 0.09, 0.70), Color(0.22, 0.28, 0.42, 0.45), 6))

func _on_mouse_entered() -> void:
	if _desc_popup == null:
		return
	if not _desc_layer.is_inside_tree():
		get_tree().root.add_child(_desc_layer)
	_update_desc()
	_desc_popup.global_position = global_position + Vector2(size.x + 4.0, 0.0)
	_desc_popup.visible = true

func _on_mouse_exited() -> void:
	if _desc_popup:
		_desc_popup.visible = false

func _exit_tree() -> void:
	if is_instance_valid(_desc_layer):
		_desc_layer.queue_free()
	_desc_layer = null
	_desc_popup = null

func _refresh_state() -> void:
	var price: int = UpgradeManager.get_current_price(upgrade_id)
	var cost_text := GameManager.format_views(price) + " views"
	if UpgradeManager.UPGRADES[upgrade_id].get("cost_type") == "per_credit":
		cost_text += "/credit"
	price_label.text = cost_text

	var count: int = UpgradeManager.get_owned_count(upgrade_id)
	count_label.text = "x%d" % count if count > 0 else ""

	var can_afford: bool = GameManager.stable_views >= price
	disabled = not can_afford

	if can_afford:
		icon_rect.modulate = Color.WHITE
		name_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		price_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.95))
	else:
		icon_rect.modulate = Color(0.45, 0.45, 0.45, 0.65)
		name_label.add_theme_color_override("font_color", Color(0.35, 0.37, 0.40))
		price_label.add_theme_color_override("font_color", Color(0.50, 0.12, 0.12))

func _on_stable_views_changed(_v: int) -> void:
	_refresh_state()

func _on_pressed() -> void:
	print("[ToolsList] pressed id=%s disabled=%s price=%d stable_views=%d" % [
		upgrade_id, str(disabled),
		UpgradeManager.get_current_price(upgrade_id),
		GameManager.stable_views,
	])
	if UpgradeManager.try_purchase(upgrade_id):
		print("[ToolsList]   purchase OK")
		_refresh_state()
		pressed_id.emit(upgrade_id)
	else:
		print("[ToolsList]   purchase FAILED")
