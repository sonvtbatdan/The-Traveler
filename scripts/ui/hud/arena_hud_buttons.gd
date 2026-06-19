extends CanvasLayer
## Bottom-right HUD buttons: Setting (placeholder), Devon/devoff (toggle dev mode UI), Quit.
## Uses Image.load_from_file so assets work without .import files.

const BTN_SIZE   := 60.0
const BTN_SEP    :=  6.0
const MARGIN     :=  8.0

var _dev_mode: bool = true          # true = dev UI visible; matches initial state of arena_debug_spawn
var _devon_btn: TextureButton = null
var _tex_devon:  Texture2D = null
var _tex_devoff: Texture2D = null

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tex_devon  = _load_img("res://assets/hud/Devon.png")
	_tex_devoff = _load_img("res://assets/hud/devoff.png")
	_build_ui()

func _load_img(res_path: String) -> Texture2D:
	var abs_path := ProjectSettings.globalize_path(res_path)
	var img := Image.load_from_file(abs_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(BTN_SEP))
	var total_h := BTN_SIZE * 3.0 + BTN_SEP * 2.0
	vb.anchor_left   = 1.0
	vb.anchor_right  = 1.0
	vb.anchor_top    = 1.0
	vb.anchor_bottom = 1.0
	vb.offset_left   = -(BTN_SIZE + MARGIN)
	vb.offset_right  = -MARGIN
	vb.offset_top    = -(total_h + MARGIN)
	vb.offset_bottom = -MARGIN
	root.add_child(vb)

	# Setting — placeholder
	var btn_setting := _make_btn(_load_img("res://assets/hud/Setting.png"))
	btn_setting.pressed.connect(_on_setting)
	vb.add_child(btn_setting)

	# Devon / devoff toggle
	_devon_btn = _make_btn(_tex_devon)
	_devon_btn.pressed.connect(_on_devon)
	vb.add_child(_devon_btn)

	# Quit
	var btn_quit := _make_btn(_load_img("res://assets/hud/Quit.png"))
	btn_quit.pressed.connect(_on_quit)
	vb.add_child(btn_quit)

func _make_btn(tex: Texture2D) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	return btn

func _on_setting() -> void:
	pass   # placeholder — no function yet

func _on_devon() -> void:
	_dev_mode = !_dev_mode
	var ds := get_tree().get_first_node_in_group("arena_debug_spawn")
	if ds != null and ds.has_method("set_dev_ui_visible"):
		ds.set_dev_ui_visible(_dev_mode)
	if _devon_btn != null:
		_devon_btn.texture_normal = _tex_devon if _dev_mode else _tex_devoff

func _on_quit() -> void:
	get_tree().quit()
