extends Panel

const ICON_PATHS: Dictionary = {
	"liquid":   "res://assets/stat/Liquid.png",
	"metal":    "res://assets/stat/metal.png",
	"nonmetal": "res://assets/stat/non-metal.png",
	"organic":  "res://assets/stat/organic.png",
}

var _count_lbls: Dictionary = {}
var _icons: Dictionary = {}  # key -> TextureRect
var _money_lbl: Label = null  # green-$ balance

func _ready() -> void:
	_apply_style()
	_build_ui()
	MaterialManager.materials_changed.connect(_refresh)
	MaterialManager.material_added.connect(_on_material_added)
	GameManager.money_changed.connect(_on_money_changed)
	MaterialManager.load_game()
	_refresh()
	_on_money_changed(GameManager.money)

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8; vbox.offset_right  = -8
	vbox.offset_top  = 6; vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title := Label.new()
	title.text = "MATERIALS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	var gf := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if gf:
		title.add_theme_font_override("font", gf)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Green-$ balance row (styled to match the material rows)
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 5)
	money_row.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(money_row)

	var dollar := Label.new()
	dollar.text = "$"
	dollar.custom_minimum_size = Vector2(24, 0)
	dollar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dollar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dollar.add_theme_font_size_override("font_size", 14)
	dollar.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	if gf:
		dollar.add_theme_font_override("font", gf)
	money_row.add_child(dollar)

	var money_name := Label.new()
	money_name.text = "Balance"
	money_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	money_name.add_theme_font_size_override("font_size", 10)
	money_name.add_theme_color_override("font_color", Color(0.72, 0.80, 0.95))
	money_row.add_child(money_name)

	_money_lbl = Label.new()
	_money_lbl.text = "0"
	_money_lbl.custom_minimum_size = Vector2(36, 0)
	_money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_lbl.add_theme_font_size_override("font_size", 10)
	_money_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	money_row.add_child(_money_lbl)

	vbox.add_child(HSeparator.new())

	var items: Array = [
		["liquid",   "Chemical Liquid"],
		["metal",    "Metal Material"],
		["nonmetal", "Non-metal Material"],
		["organic",  "Organic Material"],
	]
	for item: Array in items:
		var key: String = item[0]
		var lbl_text: String = item[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.custom_minimum_size = Vector2(0, 28)
		vbox.add_child(row)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_path: String = ICON_PATHS.get(key, "")
		if icon_path != "":
			var raw_tex := load(icon_path) as Texture2D
			if raw_tex:
				var src: Image = raw_tex.get_image()
				var img := src.duplicate()
				img.resize(24, 24, Image.INTERPOLATE_BILINEAR)
				icon.texture = ImageTexture.create_from_image(img)
		_icons[key] = icon
		row.add_child(icon)

		var name_lbl := Label.new()
		name_lbl.text = lbl_text
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.72, 0.80, 0.95))
		row.add_child(name_lbl)

		var count_lbl := Label.new()
		count_lbl.text = "0"
		count_lbl.custom_minimum_size = Vector2(36, 0)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_lbl.add_theme_font_size_override("font_size", 10)
		count_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.60))
		row.add_child(count_lbl)
		_count_lbls[key] = count_lbl

func _on_money_changed(amount: int) -> void:
	if is_instance_valid(_money_lbl):
		_money_lbl.text = str(amount)

func _on_material_added(type: String) -> void:
	var icon: TextureRect = _icons.get(type)
	if not is_instance_valid(icon):
		return
	icon.pivot_offset = icon.size / 2.0
	var t := create_tween()
	t.tween_property(icon, "scale", Vector2(1.03, 1.03), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(icon, "modulate", Color(1.5, 1.5, 1.5), 0.1)
	t.tween_property(icon, "scale", Vector2.ONE, 0.2)
	t.parallel().tween_property(icon, "modulate", Color.WHITE, 0.2)

func _refresh() -> void:
	if _count_lbls.is_empty():
		return
	var lbl_liquid: Label   = _count_lbls["liquid"]
	var lbl_metal: Label    = _count_lbls["metal"]
	var lbl_nonmetal: Label = _count_lbls["nonmetal"]
	var lbl_organic: Label  = _count_lbls["organic"]
	lbl_liquid.text   = str(MaterialManager.liquid)
	lbl_metal.text    = str(MaterialManager.metal)
	lbl_nonmetal.text = str(MaterialManager.nonmetal)
	lbl_organic.text  = str(MaterialManager.organic)
