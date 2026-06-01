extends Panel

signal transform_changed(pos: Vector2, sz: Vector2)
signal apply_requested

@onready var x_spin: SpinBox = $VBox/PosRow/XSpin
@onready var y_spin: SpinBox = $VBox/PosRow/YSpin
@onready var w_spin: SpinBox = $VBox/SizeRow/WSpin
@onready var h_spin: SpinBox = $VBox/SizeRow/HSpin

var _aspect_ratio := 1.0
var _syncing := false
var _last_center := Vector2.ZERO

func _ready() -> void:
	x_spin.value_changed.connect(_on_pos_changed)
	y_spin.value_changed.connect(_on_pos_changed)
	w_spin.value_changed.connect(_on_w_changed)
	h_spin.value_changed.connect(_on_h_changed)
	for spin: SpinBox in [x_spin, y_spin, w_spin, h_spin]:
		var le := spin.get_line_edit()
		le.focus_entered.connect(func(): le.call_deferred("select_all"))

func refresh(obj: EditableObjectNode) -> void:
	if obj == null or not is_instance_valid(obj):
		_syncing = true
		x_spin.value = 0
		y_spin.value = 0
		w_spin.value = 0
		h_spin.value = 0
		_syncing = false
		return
	_aspect_ratio = obj._aspect_ratio
	_syncing = true
	x_spin.value = snappedf(obj.position.x, 1.0)
	y_spin.value = snappedf(obj.position.y, 1.0)
	w_spin.value = snappedf(obj.size.x, 1.0)
	h_spin.value = snappedf(obj.size.y, 1.0)
	_last_center = obj.position + obj.size * 0.5
	_syncing = false

func _on_pos_changed(_value: float) -> void:
	if _syncing:
		return
	_last_center = Vector2(
		x_spin.value + w_spin.value * 0.5,
		y_spin.value + h_spin.value * 0.5
	)
	_emit_live()

func _on_w_changed(value: float) -> void:
	if _syncing or _aspect_ratio <= 0.0:
		return
	_syncing = true
	var new_h := snappedf(value / _aspect_ratio, 1.0)
	h_spin.value = new_h
	x_spin.value = snappedf(_last_center.x - value * 0.5, 1.0)
	y_spin.value = snappedf(_last_center.y - new_h * 0.5, 1.0)
	_syncing = false
	_emit_live()

func _on_h_changed(value: float) -> void:
	if _syncing or _aspect_ratio <= 0.0:
		return
	_syncing = true
	var new_w := snappedf(value * _aspect_ratio, 1.0)
	w_spin.value = new_w
	x_spin.value = snappedf(_last_center.x - new_w * 0.5, 1.0)
	y_spin.value = snappedf(_last_center.y - value * 0.5, 1.0)
	_syncing = false
	_emit_live()

func _emit_live() -> void:
	transform_changed.emit(
		Vector2(x_spin.value, y_spin.value),
		Vector2(w_spin.value, h_spin.value)
	)

func _on_apply_pressed() -> void:
	apply_requested.emit()
