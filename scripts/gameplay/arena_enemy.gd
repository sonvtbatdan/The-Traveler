extends CharacterBody2D
## Arena enemy — chases the player in world space and deals contact damage to the ship. Dies via the new
## universal damage contract take_damage(amount). Placeholder shape for now; real art ports later.

# ── TUNABLES ──────────────────────────────────────────────────────────────────
const MAX_HP           := 30.0
const MOVE_SPEED       := 95.0     # px/s toward the player
const CONTACT_DAMAGE   := 6        # HP dealt to the ship per contact tick
const CONTACT_INTERVAL := 0.5      # seconds between contact-damage ticks while overlapping
const CONTACT_DIST     := 30.0     # centre-to-centre distance counted as "touching" the player
const ENEMY_SIZE       := 16.0     # placeholder diamond half-extent / collision radius
const ENEMY_COLOR      := Color(0.95, 0.35, 0.30)

var _hp: float = MAX_HP
var _target: Node2D = null
var _contact_cd: float = 0.0

func _ready() -> void:
	add_to_group("arena_enemy")
	# No physics collisions this phase — enemies overlap freely; contact is distance-based.
	collision_layer = 0
	collision_mask = 0
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0.0, -ENEMY_SIZE), Vector2(ENEMY_SIZE, 0.0), Vector2(0.0, ENEMY_SIZE), Vector2(-ENEMY_SIZE, 0.0)])
	poly.color = ENEMY_COLOR
	add_child(poly)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = ENEMY_SIZE
	col.shape = shape
	add_child(col)
	_target = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")
		if _target == null:
			return
	var to := _target.global_position - global_position
	velocity = (to.normalized() * MOVE_SPEED) if to.length() > 1.0 else Vector2.ZERO
	move_and_slide()
	# Contact damage on a fair interval while overlapping the ship (reuses GameManager.ship_take_damage).
	_contact_cd = maxf(0.0, _contact_cd - delta)
	if _contact_cd <= 0.0 and global_position.distance_to(_target.global_position) <= CONTACT_DIST:
		GameManager.ship_take_damage(CONTACT_DAMAGE)
		_contact_cd = CONTACT_INTERVAL

## Universal damage contract — call this to hurt the enemy; it frees itself at 0 HP.
func take_damage(amount: float) -> void:
	_hp -= amount
	if _hp <= 0.0:
		queue_free()
