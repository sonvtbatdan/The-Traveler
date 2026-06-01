extends HBoxContainer

@onready var view_label: Label = %ViewLabel

func _ready() -> void:
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if font:
		view_label.add_theme_font_override("font", font)
		view_label.add_theme_font_size_override("font_size", 18)
	view_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	view_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))

	GameManager.views_changed.connect(_on_views_changed)
	_on_views_changed(GameManager.views)

func _on_views_changed(n: int) -> void:
	view_label.text = "VIEWS  " + GameManager.format_grouped_int(n)
