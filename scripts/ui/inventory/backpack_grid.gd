extends Control
class_name InvBackpackGrid

## The grid backpack. Draws the cells, hosts item widgets, and is the drop
## target for re-arranging items / dragging equipped items back out.

var cols: int = 10
var rows: int = 6
var cell_size: int = 46

var _hover_origin: Vector2i = Vector2i(-1, -1)
var _hover_size: Vector2i = Vector2i.ZERO
var _hover_ok: bool = false

func setup(p_cols: int, p_rows: int, p_cell: int) -> void:
	cols = p_cols
	rows = p_rows
	cell_size = p_cell
	custom_minimum_size = Vector2(cols * cell_size, rows * cell_size)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	var line_col := UiPalette.WIRE_2
	draw_rect(Rect2(Vector2.ZERO, size), UiPalette.SURFACE, true)
	for c in range(cols + 1):
		var x := float(c * cell_size)
		draw_line(Vector2(x, 0), Vector2(x, rows * cell_size), line_col, 1.0)
	for r in range(rows + 1):
		var y := float(r * cell_size)
		draw_line(Vector2(0, y), Vector2(cols * cell_size, y), line_col, 1.0)
	if _hover_origin.x >= 0:
		var hc := Color(0.2, 0.8, 0.3, 0.35) if _hover_ok else Color(0.9, 0.25, 0.25, 0.35)
		draw_rect(Rect2(Vector2(_hover_origin) * cell_size, Vector2(_hover_size) * cell_size), hc, true)

func _origin_from(at: Vector2, data: Dictionary) -> Vector2i:
	var grab: Vector2i = data.get("grab", Vector2i.ZERO)
	var cell := Vector2i(int(at.x / cell_size), int(at.y / cell_size))
	return cell - grab

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("uid"):
		_clear_hover()
		return false
	var d: Dictionary = data
	# Block UNEQUIPPING (dragging an equipped item back) during a boss fight; allow plain rearranging.
	if String(d.get("slot", "")) != "" and GameManager.is_in_battle():
		_clear_hover()
		return false
	var size_cells: Vector2i = InventoryManager.def_size(String(d["def_id"]))
	var origin := _origin_from(at_position, d)
	var ok := InventoryManager.can_place(size_cells, origin, int(d["uid"]))
	_hover_origin = origin
	_hover_size = size_cells
	_hover_ok = ok
	queue_redraw()
	return ok

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var d: Dictionary = data
	InventoryManager.move_item(int(d["uid"]), _origin_from(at_position, d))
	_clear_hover()

func _clear_hover() -> void:
	_hover_origin = Vector2i(-1, -1)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_hover()
