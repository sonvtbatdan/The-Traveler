extends Control

const DefensePanelScript        := preload("res://scripts/ui/defense/defense_panel.gd")
const DefenseVisualScript       := preload("res://scripts/ui/defense/defense_visual.gd")
const ScrollingBackgroundScript := preload("res://scripts/gameplay/scrolling_background.gd")
const OverlayScript             := preload("res://scripts/gameplay/overlay.gd")
const AsteroidLayerScript       := preload("res://scripts/gameplay/asteroid_layer.gd")
const GunSystemScript           := preload("res://scripts/gameplay/gun_system.gd")
const MaterialPanelScript       := preload("res://scripts/ui/hud/material_panel.gd")
const BoostButtonScript         := preload("res://scripts/ui/hud/boost_button.gd")
const ShipHpBarScript           := preload("res://scripts/ui/hud/ship_hp_bar.gd")
const BossEditScript            := preload("res://scripts/ui/boss_edit/boss_edit_mode.gd")
const BossFightScript           := preload("res://scripts/gameplay/boss_fight.gd")
const BossPanelScript           := preload("res://scripts/ui/hud/boss_panel.gd")
const BossHpBarScript           := preload("res://scripts/ui/hud/boss_hp_bar.gd")
const InventoryUIScript         := preload("res://scripts/ui/inventory/inventory_ui.gd")
const WeaponSystemScript        := preload("res://scripts/gameplay/weapon_system.gd")

@onready var edit_mode = $EditMode
@onready var visual_container: HBoxContainer = %VisualContainer

var _boss_edit_mode: Node = null
var _death_layer: CanvasLayer = null
var _victory_layer: CanvasLayer = null

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	DisplayServer.window_set_current_screen(DisplayServer.get_primary_screen())
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	UpgradeManager.upgrades_reset.connect(_on_upgrades_reset)
	GameManager.ship_destroyed.connect(_on_ship_destroyed)
	GameManager.boss_defeated.connect(_on_boss_defeated)
	_apply_title_fonts()
	_add_defense_panel()
	add_child(DefenseVisualScript.new())
	_add_scrolling_background()
	_add_scrolling_overlay()
	_add_asteroid_layers()
	_add_material_panel()
	add_child(InventoryUIScript.new())
	_add_boost_button()
	_add_ship_hp_bar()
	_add_boss_hp_bar()
	_add_boss_panel()
	GameManager.load_game()
	UpgradeManager.load_game()
	GameManager.game_loaded.emit()
	call_deferred("_apply_screen_layouts")
	call_deferred("_setup_boss_edit")

func _add_scrolling_background() -> void:
	var screen := get_node_or_null("StreamScreen") as Panel
	if screen == null:
		return

	var clip_style := StyleBoxFlat.new()
	clip_style.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	clip_style.corner_radius_top_left     = 8; clip_style.corner_radius_top_right    = 8
	clip_style.corner_radius_bottom_left  = 8; clip_style.corner_radius_bottom_right = 8
	screen.add_theme_stylebox_override("panel", clip_style)
	screen.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	screen.clip_contents = true

	var bg := ScrollingBackgroundScript.new()
	bg.add_to_group("scrolling_bg")
	bg.setup(screen.size.x, screen.size.y)
	screen.add_child(bg)

	var border := Panel.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index      = 10
	var bs := StyleBoxFlat.new()
	bs.bg_color            = Color(0.0, 0.0, 0.0, 0.0)
	bs.border_width_left   = 2; bs.border_width_right  = 2
	bs.border_width_top    = 2; bs.border_width_bottom = 2
	bs.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	bs.corner_radius_top_left     = 8; bs.corner_radius_top_right    = 8
	bs.corner_radius_bottom_left  = 8; bs.corner_radius_bottom_right = 8
	border.add_theme_stylebox_override("panel", bs)
	screen.add_child(border)

func _add_scrolling_overlay() -> void:
	var screen := get_node_or_null("StreamScreen") as Panel
	if screen == null:
		return
	var ov := OverlayScript.new()
	ov.add_to_group("scrolling_overlay")
	ov.setup(screen.size.x, screen.size.y)
	screen.add_child(ov)

func _apply_screen_layouts() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://default_layout.cfg") != OK:
		return
	var entries: Array = cfg.get_value("layout", "screen", [])
	for entry: Dictionary in entries:
		var path: String = entry.get("path", "")
		var pos: Vector2  = entry.get("pos",  Vector2.ZERO)
		var sz: Vector2   = entry.get("size", Vector2.ZERO)
		if sz.x <= 0.0 or sz.y <= 0.0:
			continue
		# ObjectsContainer is viewport-space; StreamScreen sits at (270, 8)
		var rel := Vector2(pos.x - 270.0, pos.y - 8.0)
		if path.ends_with("background.png"):
			var bg := get_tree().get_first_node_in_group("scrolling_bg")
			if is_instance_valid(bg) and bg.has_method("apply_layout_rect"):
				bg.apply_layout_rect(rel, sz)
		elif path.ends_with("overlay.png"):
			var ov := get_tree().get_first_node_in_group("scrolling_overlay")
			if is_instance_valid(ov) and ov.has_method("apply_layout_rect"):
				ov.apply_layout_rect(rel, sz)

func _add_asteroid_layers() -> void:
	var screen := get_node_or_null("StreamScreen") as Panel
	if screen == null:
		return
	var main_layer := AsteroidLayerScript.new()
	main_layer.setup(screen.size.x, screen.size.y, false)
	screen.add_child(main_layer)

	# Inventory-weapon firing + FX (sits on top of the asteroids, inside the screen).
	var weapons := WeaponSystemScript.new()
	weapons.setup()
	screen.add_child(weapons)

	var gun_sys := GunSystemScript.new()
	gun_sys.setup()

	# Add gun_system to ObjectsContainer (same as spaceship) with z_index just above spaceship
	var objects_container = edit_mode.get_node_or_null("ObjectsContainer")
	if objects_container != null:
		gun_sys.z_index = 7  # Spaceship z_index = 6
		objects_container.add_child(gun_sys)
	else:
		screen.add_child(gun_sys)
	# gun_system keeps running for ship float/movement + asteroid-vs-ship collision,
	# but its mount auto-fire is retired via MOUNT_AUTOFIRE in gun_system.gd
	# (inventory weapons are the player's guns now).

func _add_boost_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	layer.add_child(BoostButtonScript.new())

func _add_ship_hp_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	layer.add_child(ShipHpBarScript.new())

func _add_boss_hp_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	layer.add_child(BossHpBarScript.new())

func _add_boss_panel() -> void:
	var bp := BossPanelScript.new()
	bp.position = Vector2(1240.0, 318.0)
	add_child(bp)

func _on_ship_destroyed() -> void:
	GameManager.set_boost(false)
	# Exit the boss battle (hide boss, clear projectiles, restore normal asteroid play).
	var bf := get_tree().get_first_node_in_group("boss_fight")
	if bf != null and bf.has_method("kill_boss"):
		# Deferred: ship_destroyed can fire INSIDE boss_fight._tick_projectiles, and
		# kill_boss() clears _projectiles — mutating it mid-loop crashes. Run it after the frame.
		bf.call_deferred("kill_boss")
	_show_death_screen()
	get_tree().paused = true

func _show_death_screen() -> void:
	if _death_layer != null:
		return
	_death_layer = CanvasLayer.new()
	_death_layer.layer = 200
	_death_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_death_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_dismiss_death_screen())
	_death_layer.add_child(dim)

	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile

	var title := Label.new()
	title.text = "YOU DIED"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	_death_layer.add_child(title)

	var hint := Label.new()
	hint.text = "Click to continue"
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.offset_top = 60.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	_death_layer.add_child(hint)

func _dismiss_death_screen() -> void:
	get_tree().paused = false
	# Auto-respawn at full HP.
	GameManager.ship_hp = GameManager.SHIP_MAX_HP
	GameManager.ship_hp_changed.emit(GameManager.SHIP_MAX_HP)
	if _death_layer != null:
		_death_layer.queue_free()
		_death_layer = null

func _on_boss_defeated() -> void:
	GameManager.set_boost(false)
	_show_victory_screen()
	get_tree().paused = true

func _show_victory_screen() -> void:
	if _victory_layer != null:
		return
	_victory_layer = CanvasLayer.new()
	_victory_layer.layer = 200
	_victory_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_victory_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_dismiss_victory_screen())
	_victory_layer.add_child(dim)

	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile

	var title := Label.new()
	title.text = "DISASTER AVOIDED"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	_victory_layer.add_child(title)

	var hint := Label.new()
	hint.text = "Click to continue"
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.offset_top = 60.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	_victory_layer.add_child(hint)

func _dismiss_victory_screen() -> void:
	get_tree().paused = false
	if _victory_layer != null:
		_victory_layer.queue_free()
		_victory_layer = null

func _add_material_panel() -> void:
	var panel := MaterialPanelScript.new()
	panel.position = Vector2(1240.0, 8.0)
	panel.size     = Vector2(192.0, 160.0)
	add_child(panel)

func _add_defense_panel() -> void:
	var dp := DefensePanelScript.new()
	dp.z_index = 5
	dp.position = Vector2(10.0, 408.0)
	dp.size     = Vector2(250.0, 364.0)
	add_child(dp)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameManager.save_game()
		UpgradeManager.save_game()
		EquipmentManager.save_game()
		WeaponManager.save_game()
		DefenseManager.save_game()
		MaterialManager.save_game()
		InventoryManager.save_game()
		get_tree().quit()

func _apply_title_fonts() -> void:
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if not font:
		return
	$CommentColumn.visible = false
	var titles: Array[Label] = [
		$EquipmentColumn/EquipTitle,
	]
	for lbl: Label in titles:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.offset_top = 5.0

func _setup_boss_edit() -> void:
	var objects_container := edit_mode.get_node_or_null("ObjectsContainer") as Control
	if objects_container == null:
		return
	var bem := BossEditScript.new()
	add_child(bem)
	_boss_edit_mode = bem
	bem.setup(objects_container)
	var bf := BossFightScript.new()
	objects_container.add_child(bf)
	bf.setup(objects_container)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_edit_mode"):
		if _boss_edit_mode != null and _boss_edit_mode.is_open():
			_boss_edit_mode.show_toast("Bạn cần thoát mode F5 trước")
		else:
			edit_mode.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_boss_edit_mode"):
		if edit_mode.is_open():
			if _boss_edit_mode != null:
				_boss_edit_mode.show_toast("Bạn cần thoát mode F4 trước")
		else:
			if _boss_edit_mode != null:
				_boss_edit_mode.toggle()
		get_viewport().set_input_as_handled()

func _on_upgrades_reset() -> void:
	for child in visual_container.get_children():
		child.queue_free()

func _on_upgrade_purchased(upgrade_id: String) -> void:
	var path := "res://assets/upgrade/" + upgrade_id + ".png"
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(36, 36)
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visual_container.add_child(rect)
