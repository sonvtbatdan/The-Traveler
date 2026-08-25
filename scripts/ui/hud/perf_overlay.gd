extends CanvasLayer

## Perf readout, pinned to the upper-right corner. Shows FPS, this frame's time, a rolling 2s PEAK
## frame-time (so brief hitches are visible), and the live scene node count (rises as bullets
## accumulate). Turns red when the peak frame-time crosses ~20ms (≈ below 50 FPS). Use it to tell a
## real frame drop apart from a visual jitter at a steady 60.
## (No F8 toggle — F8 is Godot's editor "Stop" shortcut and would close the running game.)
##
## Toggled by the Settings panel's FPS switch (group "perf_overlay", see set_shown()/is_shown()) — persisted
## to disk on Save (2026-07-28), same as Dev Mode: a saved "on" re-arms itself at the START of every arena
## load (see _ready() below), not just for the rest of the current session.

const SettingsScript := preload("res://scripts/ui/settings/settings_panel.gd")
const HITCH_MS := 20.0   # peak frame-ms above this = a real dip → shown red
const ENEMY_LIST_CAP := 15   # max distinct enemy types listed (keeps the panel from growing off-screen)

var _label: Label
var _enemy_label: Label
var _peak_ms: float = 0.0
var _win_t: float = 0.0
var _ui_t: float = 0.0     # refresh-the-readout accumulator (the text update is throttled, see _process)
var _red: bool = false
var _play_t: float = 0.0   # seconds of actual play time since this arena run started (frozen while paused)
var _v2_checked: bool = false
var _v2_active: bool = false   # spawn_mode_2 status, resolved once (director doesn't change mid-run)

func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep measuring even if the tree pauses
	add_to_group("perf_overlay")   # so the Settings panel's FPS switch can find this instance
	visible = bool(SettingsScript.load_cfg().get("fps_shown", false))   # re-arm a saved "FPS: on"
	_label = Label.new()
	# Pin to the upper-right corner, right-aligned.
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -360
	_label.offset_right = -10
	_label.offset_top = 8
	_label.offset_bottom = 130
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

	# Live enemy type/count breakdown, pinned right below the perf readout (same font, default theme).
	_enemy_label = Label.new()
	_enemy_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_label.offset_left = -360
	_enemy_label.offset_right = -10
	_enemy_label.offset_top = 134
	_enemy_label.offset_bottom = 134 + 18.0 * (ENEMY_LIST_CAP + 3)   # capped list → bounded height (+1 row for the Total HP line)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_label.add_theme_font_size_override("font_size", 12)
	_enemy_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_enemy_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_enemy_label.add_theme_constant_override("outline_size", 3)
	add_child(_enemy_label)

## Public: toggled by the Settings panel's FPS switch (the overlay has no on-screen button of its own).
func is_shown() -> bool:
	return visible

func set_shown(v: bool) -> void:
	visible = v

func _process(delta: float) -> void:
	# Counts from the moment the arena starts regardless of whether the FPS switch is on — the clock
	# keeps running while hidden, it just isn't drawn until the Settings panel's FPS switch shows it.
	if not get_tree().paused:
		_play_t += delta   # run-clock: counts actual play time, frozen while the game is paused (level-up, menus)
	if not visible:
		return
	if not _v2_checked:
		# Resolved once (lazily — the wave director may not exist yet the first frame) via duck-typing: only
		# arena_wave_director_v2.gd implements player_velocity(). Avoids a preload cycle with arena.gd.
		var wd := get_tree().get_first_node_in_group("wave_director")
		if wd != null:
			_v2_checked = true
			_v2_active = wd.has_method("player_velocity")
	var ms := delta * 1000.0
	_peak_ms = maxf(_peak_ms, ms)   # track the peak every frame (cheap) so brief hitches still register
	# Refresh the on-screen text at 5 Hz, NOT every frame: get_tree().get_node_count() walks the entire scene
	# tree, which at 500 enemies (+ plumes, bullets, orbs) is thousands of nodes — too costly 60×/sec.
	_ui_t += delta
	if _ui_t >= 0.2:
		_ui_t = 0.0
		var mins := int(_play_t) / 60
		var secs := int(_play_t) % 60
		var creeps := get_tree().get_node_count_in_group("arena_enemy")   # cheap group count, not a full tree walk
		var agony_txt := ""
		if _v2_active:
			var wd := get_tree().get_first_node_in_group("wave_director")
			if wd != null and wd.has_method("agony_rank"):
				agony_txt = "   Agony %d" % int(wd.call("agony_rank"))
		_label.text = "FPS %d   frame %.1f ms\npeak(2s) %.1f ms   nodes %d\nSpawn Mode 2: %s   Time %02d:%02d   Creep %d%s" % [
			Engine.get_frames_per_second(), ms, _peak_ms, get_tree().get_node_count(),
			"ON" if _v2_active else "OFF", mins, secs, creeps, agony_txt]
		var red := _peak_ms > HITCH_MS
		if red != _red:   # only touch the theme override when the state actually flips
			_red = red
			_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45) if red else Color(0.7, 1.0, 0.7))
		_refresh_enemy_list(creeps)
	_win_t += delta
	if _win_t >= 2.0:
		_win_t = 0.0
		_peak_ms = ms   # start a fresh 2s window

## Live breakdown of alive enemies by type (e.g. "Fly: 12"), sorted by count descending, capped to
## ENEMY_LIST_CAP entries so the panel can't grow past the screen even with the full ~30-type roster alive.
##
## The "Total HP" line (2026-08-24, on request) sums every live creep's CURRENT hp, with the field's combined
## MAX hp next to it — a raw head-count doesn't say whether the field is actually oppressive (300 flies and
## 12 fleet carriers both read as "300 creeps"), so this is the number to watch for "is the player being
## asked to chew through more HP than their DPS can clear". Summed in the same single pass that already walks
## the group for the per-type counts, so it costs two extra property reads per creep at the same 5 Hz.
func _refresh_enemy_list(total: int) -> void:
	var counts: Dictionary = {}
	var hp_sum := 0.0
	var hp_max_sum := 0.0
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		# .get() rather than a typed read: "arena_enemy" also holds non-arena_enemy.gd members (batched
		# proxies, landmark stand-ins), and a member without an `hp`/`hp_max` property returns null here
		# instead of erroring — same defensive shape the `_type` read just below already uses.
		var ehp: Variant = e.get("hp")
		if ehp != null:
			hp_sum += float(ehp)
		var emax: Variant = e.get("hp_max")
		if emax != null:
			hp_max_sum += float(emax)
		var t := String(e.get("_type"))
		if t == "":
			continue
		counts[t] = int(counts.get(t, 0)) + 1
	var pairs: Array = []
	for k in counts.keys():
		pairs.append([k, counts[k]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	var lines: PackedStringArray = []
	var shown := mini(ENEMY_LIST_CAP, pairs.size())
	for i in range(shown):
		lines.append("%s: %d" % [String(pairs[i][0]).capitalize(), pairs[i][1]])
	var txt := "Enemies alive (%d, %d types):\nTotal HP %s / %s\n%s" % [
		total, pairs.size(), _short_num(hp_sum), _short_num(hp_max_sum), "\n".join(lines)]
	if pairs.size() > shown:
		txt += "\n+%d more type%s" % [pairs.size() - shown, "s" if pairs.size() - shown > 1 else ""]
	_enemy_label.text = txt

## Compact readout for a big HP total — 12345 → "12.3k", 2400000 → "2.40M". The exact figure isn't the point
## (it moves every frame); the magnitude and which way it's trending are, and a full-length integer would push
## this right-aligned line past the panel's 350px column.
func _short_num(v: float) -> String:
	if v >= 1000000.0:
		return "%.2fM" % (v / 1000000.0)
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return "%d" % int(round(v))
