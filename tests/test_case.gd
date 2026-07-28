extends RefCounted
## Base class for custom test files (no addon dependency). Extend this via
## `extends "res://tests/test_case.gd"`, name test methods `test_*()`, and use the assert_*
## helpers below. GDScript has no try/catch, so assertions RECORD a failure (set _failed +
## _fail_msg) instead of throwing — the runner checks _failed after each test call.
##
## Optional override points: setup() runs before each test_* method, teardown() runs after.

var tree: SceneTree = null   # set by the runner before setup(); use for add_child() etc. if a test needs the live tree
var _failed: bool = false
var _fail_msg: String = ""

func setup() -> void:
	pass

func teardown() -> void:
	pass

func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		_fail("expected true" + (" (%s)" % msg if msg != "" else ""))

func assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		_fail("expected false" + (" (%s)" % msg if msg != "" else ""))

func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		_fail("expected %s == %s%s" % [str(a), str(b), (" (%s)" % msg) if msg != "" else ""])

func assert_almost_eq(a: float, b: float, eps: float = 0.001, msg: String = "") -> void:
	if absf(a - b) > eps:
		_fail("expected %s ~= %s (eps %s)%s" % [str(a), str(b), str(eps), (" (%s)" % msg) if msg != "" else ""])

func assert_lt(a: Variant, b: Variant, msg: String = "") -> void:
	if not (a < b):
		_fail("expected %s < %s%s" % [str(a), str(b), (" (%s)" % msg) if msg != "" else ""])

func assert_not_null(v: Variant, msg: String = "") -> void:
	if v == null:
		_fail("expected non-null" + (" (%s)" % msg if msg != "" else ""))

func _fail(msg: String) -> void:
	_failed = true
	_fail_msg = msg if _fail_msg == "" else (_fail_msg + "; " + msg)
