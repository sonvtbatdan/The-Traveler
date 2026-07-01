extends Camera2D
## Arena follow-camera with screen-shake. Two distinct impact feels, both applied via `offset` (never rotation,
## so the top-down view stays upright):
##   • SHAKE — a chaotic random jolt driven by a decaying "trauma" value (the well-known Squirrel-Eiserloh model:
##     displacement ∝ trauma², so a big hit kicks hard then settles smoothly). add_trauma() / a heavy `impact()`.
##   • VIBRATION — a short, fast sinusoidal buzz (rhythmic, low-amplitude) — clearly different from the jolt.
## mortar_impact() = a heavy shake now + a vibration buzz 0.5s later (the Nuke's signature one-two punch).

const SHAKE_MAX   := Vector2(30.0, 24.0)   # max positional jolt (px) at full trauma
const SHAKE_DECAY := 1.8                    # trauma lost per second
const VIBE_AMP    := 6.0                    # vibration amplitude (px)
const VIBE_FREQ   := 58.0                   # vibration oscillations/sec (buzzy)
const VIBE_TIME   := 0.35                   # vibration duration (s)
const VIBE_DELAY  := 0.5                    # gap after the impact before the vibration kicks in

var _trauma: float = 0.0
var _vibe_t: float = 0.0

func _ready() -> void:
	add_to_group("camera_shake")

func _process(delta: float) -> void:
	var off := Vector2.ZERO
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
		var s := _trauma * _trauma
		off += Vector2(SHAKE_MAX.x * randf_range(-1.0, 1.0), SHAKE_MAX.y * randf_range(-1.0, 1.0)) * s
	if _vibe_t > 0.0:
		_vibe_t = maxf(0.0, _vibe_t - delta)
		var fade := _vibe_t / VIBE_TIME
		var ph := (VIBE_TIME - _vibe_t) * VIBE_FREQ * TAU
		off += Vector2(sin(ph), sin(ph * 1.31)) * VIBE_AMP * fade
	offset = off

## Add to the shake trauma (clamped 0..1). Use for any impact jolt.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Start (or restart) the vibration buzz now.
func start_vibration() -> void:
	_vibe_t = VIBE_TIME

## The Nuke's one-two: a heavy shake on detonation, then a vibration buzz VIBE_DELAY seconds later.
func mortar_impact() -> void:
	add_trauma(0.95)
	get_tree().create_timer(VIBE_DELAY).timeout.connect(start_vibration)
