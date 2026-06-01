extends Button

signal pressed_id(item_id: String)

@onready var icon_rect:   TextureRect = %IconRect
@onready var name_label:  Label       = %NameLabel
@onready var price_label: Label       = %PriceLabel
@onready var count_label: Label       = %CountLabel

var item_id: String = ""
var _desc_popup: PanelContainer = null
var _desc_layer: CanvasLayer    = null

func setup(id: String) -> void:
	item_id = id
	var data: Dictionary = EquipmentManager.ITEMS[id]
	name_label.text = data["name"]

	var icon_path: String = "res://assets/upgrades/equipment/" + String(data["icon"])
	var tex := load(icon_path) as Texture2D
	if tex:
		icon_rect.texture = tex

	_build_popup()
	_apply_styles()
	GameManager.cash_changed.connect(_on_cash_changed)
	EquipmentManager.items_reset.connect(_refresh_state)
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_state()

func _build_popup() -> void:
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

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content    = true
	rtl.scroll_active  = false
	rtl.custom_minimum_size = Vector2(190.0, 0.0)
	rtl.add_theme_color_override("default_color", Color(0.82, 0.9, 1.0))
	rtl.add_theme_font_size_override("normal_font_size",       10)
	rtl.add_theme_font_size_override("bold_font_size",         10)
	rtl.add_theme_font_size_override("italics_font_size",      10)
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.text = _build_popup_text()
	rtl.name = "RTL"
	_desc_popup.add_child(rtl)

	_desc_layer = CanvasLayer.new()
	_desc_layer.layer = 15
	_desc_layer.add_child(_desc_popup)

func _build_popup_text() -> String:
	if not EquipmentManager.ITEMS.has(item_id):
		return ""
	var data: Dictionary = EquipmentManager.ITEMS[item_id]
	var price := float(data["price"])
	var desc  := String(data.get("desc", ""))
	var owned := EquipmentManager.get_owned(item_id)

	var lines: PackedStringArray = []
	lines.append("[b]" + String(data["name"]) + "[/b]")
	lines.append("[b][color=#ffd84d]$" + _fmt_cash(price) + "[/color][/b]")
	lines.append("")
	lines.append(desc)
	if owned >= 1:
		lines.append("")
		lines.append("[color=#88ff88]✓ Purchased[/color]")
	return "\n".join(lines)

func _fmt_cash(v: float) -> String:
	if v < 1_000_000.0:
		return GameManager.format_grouped_float(v, 0)
	return GameManager.format_cash(v)

func _apply_styles() -> void:
	var _make := func(bg: Color, border: Color, corner: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left   = 1; s.border_width_right  = 1
		s.border_width_top    = 1; s.border_width_bottom = 1
		s.border_color = border
		s.corner_radius_top_left     = corner; s.corner_radius_top_right    = corner
		s.corner_radius_bottom_left  = corner; s.corner_radius_bottom_right = corner
		return s
	add_theme_stylebox_override("normal",   _make.call(Color(0.07, 0.09, 0.13, 0.95), Color(0.35, 0.45, 0.65, 0.90), 6))
	add_theme_stylebox_override("hover",    _make.call(Color(0.10, 0.13, 0.20, 0.95), Color(0.50, 0.65, 0.85, 0.95), 6))
	add_theme_stylebox_override("pressed",  _make.call(Color(0.05, 0.07, 0.10, 0.95), Color(0.35, 0.45, 0.65, 0.80), 6))
	add_theme_stylebox_override("disabled", _make.call(Color(0.05, 0.06, 0.09, 0.70), Color(0.22, 0.28, 0.42, 0.45), 6))

func _refresh_state() -> void:
	var owned: int = EquipmentManager.get_owned(item_id)
	if owned >= 1:
		price_label.text = ""
		count_label.text = "Bought"
		disabled = true
		modulate = Color(0.55, 0.55, 0.55, 0.75)
	else:
		var price: float = float(EquipmentManager.ITEMS[item_id]["price"])
		price_label.text = "$" + _fmt_cash(price)
		count_label.text = ""
		disabled = not (GameManager.cash >= price)
		modulate = Color.WHITE
	# Refresh popup text (owned status may have changed)
	if is_instance_valid(_desc_popup):
		var rtl := _desc_popup.get_node_or_null("RTL") as RichTextLabel
		if rtl:
			rtl.text = _build_popup_text()

func _on_cash_changed(_c: float) -> void:
	_refresh_state()

func _on_mouse_entered() -> void:
	if _desc_popup == null:
		return
	if not _desc_layer.is_inside_tree():
		get_tree().root.add_child(_desc_layer)
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

func _on_pressed() -> void:
	if EquipmentManager.try_purchase(item_id):
		_refresh_state()
		pressed_id.emit(item_id)
