# Left 200×200 widget: location, weather, clock, elapsed, remaining.
# Hover → brightens. Click → expand/collapse floating timer/alarm panel.
class_name UserWeatherClock
extends Panel

const PANEL_SIZE       := Vector2(200.0, 200.0)
const WEATHER_INTERVAL := 600.0
const SAVE_PATH        := "user://session.cfg"
const COLLAPSE_DELAY   := 2.0

const WMO_LABELS: Dictionary = {
	0: "Clear", 1: "Mainly Clear", 2: "Partly Cloudy", 3: "Overcast",
	45: "Foggy", 48: "Icy Fog",
	51: "Light Drizzle", 53: "Drizzle", 55: "Heavy Drizzle",
	61: "Light Rain", 63: "Rain", 65: "Heavy Rain",
	71: "Light Snow", 73: "Snow", 75: "Heavy Snow",
	80: "Showers", 81: "Heavy Showers", 82: "Violent Showers",
	95: "Thunderstorm", 96: "Hail Storm", 99: "Heavy Hail Storm",
}

var _gameplay_font: FontFile = null

# ── Main panel UI ─────────────────────────────────────────────────────────────
var _panel_style:   StyleBoxFlat
var _city_lbl:      Label
var _weather_lbl:   Label
var _clock_lbl:     Label
var _elapsed_lbl:   Control = null   # _RunLabel
var _remaining_lbl: Control = null   # _RunLabel

var _http_geo:      HTTPRequest
var _http_weather:  HTTPRequest
var _lat:           float = 0.0
var _lon:           float = 0.0
var _weather_timer: float = 0.0

# ── Session ───────────────────────────────────────────────────────────────────
var _start_time:  float = 0.0   # always reset to now on launch
var _session_sec: float = 7200.0

var session_duration: float:
	get: return _session_sec
	set(v):
		_session_sec = maxf(60.0, v)
		_save_session()

# ── Hover / expand ────────────────────────────────────────────────────────────
var _hovering:    bool  = false
var _expanded:    bool  = false
var _hover_timer: float = 0.0

# ── Floating timer/alarm panel ────────────────────────────────────────────────
var _float_layer:    CanvasLayer   = null
var _float_panel:    PanelContainer = null
var _tab_mode:       String        = "timer"
var _tab_timer_btn:  Button        = null
var _tab_alarm_btn:  Button        = null
var _timer_box:      VBoxContainer = null
var _alarm_box:      VBoxContainer = null
var _timer_spin:     SpinBox       = null
var _timer_go_btn:   Button        = null
var _timer_lbl:      Label         = null
var _alarm_h_spin:   SpinBox       = null
var _alarm_m_spin:   SpinBox       = null
var _alarm_set_btn:  Button        = null
var _alarm_info_lbl: Label         = null
var _flash_lbl:      Label         = null

# ── Timer state ───────────────────────────────────────────────────────────────
enum TState { IDLE, RUNNING, FIRED }
var _tstate:     TState = TState.IDLE
var _timer_left: float  = 0.0

# ── Alarm state ───────────────────────────────────────────────────────────────
var _alarm_active: bool  = false
var _alarm_h:      int   = 0
var _alarm_m:      int   = 0
var _alarm_fired:  bool  = false
var _flash_t:      float = 0.0

# ── Audio ─────────────────────────────────────────────────────────────────────
var _alarm_player: AudioStreamPlayer = null

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	_gameplay_font = load("res://assets/fonts/mandalore/mandalore.ttf") as FontFile
	_apply_style()
	_build_ui()
	_build_float_panel()
	_build_alarm_audio()
	_load_session()
	_fetch_geo()

func _apply_style() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color            = UiPalette.SURFACE
	_panel_style.border_width_left   = 1
	_panel_style.border_width_right  = 1
	_panel_style.border_width_top    = 1
	_panel_style.border_width_bottom = 1
	_panel_style.border_color        = UiPalette.WIRE_2
	_panel_style.corner_radius_top_left     = 6
	_panel_style.corner_radius_top_right    = 6
	_panel_style.corner_radius_bottom_left  = 6
	_panel_style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", _panel_style)

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 10
	vbox.offset_top    = 10
	vbox.offset_right  = -10
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_city_lbl    = _make_lbl("---",  11, Color(0.75, 0.85, 1.0))
	_weather_lbl = _make_lbl("---",  11, Color(0.85, 0.95, 0.75))
	_clock_lbl   = _make_lbl("--:--", 50, Color(1.0, 1.0, 1.0))

	_clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_clock_lbl.size_flags_vertical  = Control.SIZE_EXPAND_FILL

	var el := _RunLabel.new()
	el.cfg(14, Color(0.65, 0.75, 0.65), _gameplay_font)
	el.set_text("ELAPSED: 00:00")
	_elapsed_lbl = el

	var rm := _RunLabel.new()
	rm.cfg(14, Color(0.75, 0.65, 0.65), _gameplay_font)
	rm.set_text("REMAINING: --:--")
	_remaining_lbl = rm

	vbox.add_child(_city_lbl)
	vbox.add_child(_weather_lbl)
	vbox.add_child(_clock_lbl)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_elapsed_lbl)
	vbox.add_child(_remaining_lbl)

	_http_geo     = HTTPRequest.new()
	_http_weather = HTTPRequest.new()
	add_child(_http_geo)
	add_child(_http_weather)
	_http_geo.request_completed.connect(_on_geo_done)
	_http_weather.request_completed.connect(_on_weather_done)

	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func _make_lbl(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = MandaloreText.a(txt)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if _gameplay_font:
		l.add_theme_font_override("font", _gameplay_font)
	return l

# ── Floating panel ────────────────────────────────────────────────────────────

func _build_float_panel() -> void:
	_float_layer = CanvasLayer.new()
	_float_layer.layer = 6

	_float_panel = PanelContainer.new()
	_float_panel.visible = false

	var ps := StyleBoxFlat.new()
	ps.bg_color            = UiPalette.SURFACE
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.border_color        = UiPalette.ACCENT_DIM
	ps.corner_radius_top_left     = 6; ps.corner_radius_top_right    = 6
	ps.corner_radius_bottom_left  = 6; ps.corner_radius_bottom_right = 6
	_float_panel.add_theme_stylebox_override("panel", ps)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_float_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# ── Tab row ─────────────────────────────────────────────────────────────
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	vbox.add_child(tab_row)

	_tab_timer_btn = _make_fbtn("TIMER")
	_tab_alarm_btn = _make_fbtn("ALARM")
	tab_row.add_child(_tab_timer_btn)
	tab_row.add_child(_tab_alarm_btn)
	_tab_timer_btn.pressed.connect(func(): _switch_tab("timer"))
	_tab_alarm_btn.pressed.connect(func(): _switch_tab("alarm"))

	vbox.add_child(HSeparator.new())

	# ── Timer container ──────────────────────────────────────────────────────
	_timer_box = VBoxContainer.new()
	_timer_box.add_theme_constant_override("separation", 5)
	vbox.add_child(_timer_box)

	var tm_row := HBoxContainer.new()
	tm_row.add_theme_constant_override("separation", 4)
	_timer_box.add_child(tm_row)

	var tm_lbl := Label.new()
	tm_lbl.text = MandaloreText.a("Minutes:")
	tm_lbl.add_theme_font_size_override("font_size", 11)
	tm_lbl.add_theme_color_override("font_color", UiPalette.MUTED)
	tm_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tm_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	if _gameplay_font: tm_lbl.add_theme_font_override("font", _gameplay_font)
	tm_row.add_child(tm_lbl)

	_timer_spin = SpinBox.new()
	_timer_spin.min_value = 1; _timer_spin.max_value = 999
	_timer_spin.step = 1; _timer_spin.value = 25
	_timer_spin.custom_minimum_size = Vector2(70, 0)
	tm_row.add_child(_timer_spin)

	_timer_go_btn = _make_fbtn("▶  START")
	_timer_box.add_child(_timer_go_btn)
	_timer_go_btn.pressed.connect(_on_timer_go)

	_timer_lbl = Label.new()
	_timer_lbl.text = MandaloreText.a("—")
	_timer_lbl.add_theme_font_size_override("font_size", 14)
	_timer_lbl.add_theme_color_override("font_color", UiPalette.INK)
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _gameplay_font: _timer_lbl.add_theme_font_override("font", _gameplay_font)
	_timer_box.add_child(_timer_lbl)

	# ── Alarm container ──────────────────────────────────────────────────────
	_alarm_box = VBoxContainer.new()
	_alarm_box.visible = false
	_alarm_box.add_theme_constant_override("separation", 5)
	vbox.add_child(_alarm_box)

	var al_row := HBoxContainer.new()
	al_row.add_theme_constant_override("separation", 4)
	al_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_alarm_box.add_child(al_row)

	_alarm_h_spin = SpinBox.new()
	_alarm_h_spin.min_value = 0; _alarm_h_spin.max_value = 23
	_alarm_h_spin.step = 1; _alarm_h_spin.value = 0
	_alarm_h_spin.custom_minimum_size = Vector2(60, 0)
	al_row.add_child(_alarm_h_spin)

	var colon_lbl := Label.new()
	colon_lbl.text = MandaloreText.a(":")
	colon_lbl.add_theme_font_size_override("font_size", 16)
	colon_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80))
	colon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _gameplay_font: colon_lbl.add_theme_font_override("font", _gameplay_font)
	al_row.add_child(colon_lbl)

	_alarm_m_spin = SpinBox.new()
	_alarm_m_spin.min_value = 0; _alarm_m_spin.max_value = 59
	_alarm_m_spin.step = 1; _alarm_m_spin.value = 0
	_alarm_m_spin.custom_minimum_size = Vector2(60, 0)
	al_row.add_child(_alarm_m_spin)

	_alarm_set_btn = _make_fbtn("SET ALARM")
	_alarm_box.add_child(_alarm_set_btn)
	_alarm_set_btn.pressed.connect(_on_alarm_toggle)

	_alarm_info_lbl = Label.new()
	_alarm_info_lbl.text = MandaloreText.a("No alarm set")
	_alarm_info_lbl.add_theme_font_size_override("font_size", 11)
	_alarm_info_lbl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.78))
	_alarm_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _gameplay_font: _alarm_info_lbl.add_theme_font_override("font", _gameplay_font)
	_alarm_box.add_child(_alarm_info_lbl)

	# ── Flash label (always in tree, empty when idle) ────────────────────────
	_flash_lbl = Label.new()
	_flash_lbl.text = MandaloreText.a("")
	_flash_lbl.add_theme_font_size_override("font_size", 12)
	_flash_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.20))
	_flash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _gameplay_font: _flash_lbl.add_theme_font_override("font", _gameplay_font)
	vbox.add_child(_flash_lbl)

	_float_layer.add_child(_float_panel)
	_update_tab_btns()

func _make_fbtn(txt: String) -> Button:
	var btn := Button.new()
	btn.text = MandaloreText.a(txt)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	if _gameplay_font:
		btn.add_theme_font_override("font", _gameplay_font)
	var mk := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = bc
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.content_margin_top = 3; s.content_margin_bottom = 3
		return s
	btn.add_theme_stylebox_override("normal",  mk.call(Color(0.09, 0.12, 0.18, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	btn.add_theme_stylebox_override("hover",   mk.call(Color(0.14, 0.18, 0.28, 0.9), Color(0.50, 0.65, 0.90, 0.9)))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(0.06, 0.08, 0.13, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	btn.add_theme_stylebox_override("focus",   mk.call(Color(0.09, 0.12, 0.18, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	return btn

# ── Alarm audio (880 Hz decaying beep, generated at runtime) ──────────────────

func _build_alarm_audio() -> void:
	var rate := 44100
	var dur  := 0.40
	var n    := int(rate * dur)
	var pcm  := PackedByteArray()
	pcm.resize(n * 2)
	for i: int in n:
		var t:   float = float(i) / float(rate)
		var env: float = exp(-5.0 * t / dur)
		var v:   int   = int(sin(t * 880.0 * TAU) * 28000.0 * env)
		v = clampi(v, -32768, 32767)
		pcm[i * 2]     = v & 0xFF
		pcm[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo   = false
	wav.mix_rate = rate
	wav.data     = pcm
	_alarm_player = AudioStreamPlayer.new()
	_alarm_player.stream = wav
	add_child(_alarm_player)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_clock()
	_weather_timer += delta
	if _weather_timer >= WEATHER_INTERVAL and _lat != 0.0:
		_weather_timer = 0.0
		_fetch_weather()

	# Hover detection
	var clock_over := Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())
	var panel_over := false
	if is_instance_valid(_float_panel) and _float_panel.visible and _float_panel.is_inside_tree():
		panel_over = _float_panel.get_global_rect().has_point(get_viewport().get_mouse_position())
	var over := clock_over or panel_over
	if over != _hovering:
		_hovering = over
		_hover_timer = 0.0
		_panel_style.bg_color = UiPalette.SURFACE_3 if over else UiPalette.SURFACE
	if not _hovering and _expanded:
		_hover_timer += delta
		if _hover_timer >= COLLAPSE_DELAY:
			_hover_timer = 0.0
			_set_expanded(false)

	# Reposition float panel to follow clock
	if _expanded and is_instance_valid(_float_panel) and _float_panel.visible:
		var panel_sz := _float_panel.size
		if panel_sz.x > 1.0:
			var gr := get_global_rect()
			var vp := get_viewport().get_visible_rect().size
			_float_panel.position = Vector2(
				clampf(gr.position.x, 4.0, vp.x - panel_sz.x - 4.0),
				clampf(gr.end.y + 4.0, 4.0, vp.y - panel_sz.y - 4.0)
			)

	# Timer countdown
	if _tstate == TState.RUNNING:
		_timer_left -= delta
		if _timer_left <= 0.0:
			_timer_left = 0.0
			_tstate = TState.FIRED
			_ring_alarm()
		_update_timer_display()

	# Alarm check — fires once per active setting
	if _alarm_active and not _alarm_fired:
		var t := Time.get_time_dict_from_system()
		if int(t["hour"]) == _alarm_h and int(t["minute"]) == _alarm_m:
			_alarm_fired = true
			_ring_alarm()

	# Flash pulse
	var firing := _tstate == TState.FIRED or (_alarm_active and _alarm_fired)
	if is_instance_valid(_flash_lbl):
		if firing:
			_flash_t += delta
			_flash_lbl.text = MandaloreText.a("⏰  TIME'S UP!")
			_flash_lbl.modulate.a = 0.55 + 0.45 * sin(_flash_t * 5.0)
		else:
			_flash_lbl.text = MandaloreText.a("")
			_flash_lbl.modulate.a = 1.0
			_flash_t = 0.0

func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	_clock_lbl.text = MandaloreText.a("%02d:%02d" % [t["hour"], t["minute"]])

	var elapsed := Time.get_unix_time_from_system() - _start_time
	if is_instance_valid(_elapsed_lbl):
		(_elapsed_lbl as _RunLabel).set_text("ELAPSED: " + _fmt_duration(elapsed))

	if is_instance_valid(_remaining_lbl):
		var remaining_text: String
		if _tstate == TState.RUNNING:
			remaining_text = "REMAINING: " + _fmt_duration(_timer_left)
		else:
			var session_rem := maxf(0.0, _session_sec - elapsed)
			remaining_text = "REMAINING: " + _fmt_duration(session_rem)
		(_remaining_lbl as _RunLabel).set_text(remaining_text)

func _update_timer_display() -> void:
	if not is_instance_valid(_timer_lbl):
		return
	match _tstate:
		TState.IDLE:
			_timer_lbl.text = MandaloreText.a("—")
			if is_instance_valid(_timer_go_btn): _timer_go_btn.text = MandaloreText.a("▶  START")
		TState.RUNNING:
			_timer_lbl.text = MandaloreText.a(_fmt_duration(_timer_left))
		TState.FIRED:
			_timer_lbl.text = MandaloreText.a("Done!")
			if is_instance_valid(_timer_go_btn): _timer_go_btn.text = MandaloreText.a("▶  START")

func _fmt_duration(sec: float) -> String:
	var s  := int(sec)
	var h  := s / 3600
	var m  := (s % 3600) / 60
	var ss := s % 60
	if h > 0:
		return "%02d:%02d:%02d" % [h, m, ss]
	return "%02d:%02d" % [m, ss]

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_expanded(not _expanded)
		get_viewport().set_input_as_handled()

func _set_expanded(val: bool) -> void:
	_expanded = val
	if val:
		if not _float_layer.is_inside_tree():
			get_tree().root.add_child(_float_layer)
		_float_panel.visible = true
		call_deferred("_reposition_float_panel")
	else:
		if is_instance_valid(_float_panel):
			_float_panel.visible = false

func _reposition_float_panel() -> void:
	if not is_instance_valid(_float_panel) or not _float_panel.visible:
		return
	var panel_sz := _float_panel.size
	if panel_sz.x < 1.0:
		panel_sz = _float_panel.get_combined_minimum_size()
	var gr := get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	_float_panel.position = Vector2(
		clampf(gr.position.x, 4.0, vp.x - panel_sz.x - 4.0),
		clampf(gr.end.y + 4.0, 4.0, vp.y - panel_sz.y - 4.0)
	)

# ── Tab ───────────────────────────────────────────────────────────────────────

func _switch_tab(tab: String) -> void:
	_tab_mode = tab
	if is_instance_valid(_timer_box): _timer_box.visible = tab == "timer"
	if is_instance_valid(_alarm_box): _alarm_box.visible = tab == "alarm"
	_update_tab_btns()

func _update_tab_btns() -> void:
	var active   := Color(0.45, 0.85, 1.0)
	var inactive := Color(0.50, 0.55, 0.65)
	if is_instance_valid(_tab_timer_btn):
		_tab_timer_btn.add_theme_color_override("font_color", active if _tab_mode == "timer" else inactive)
	if is_instance_valid(_tab_alarm_btn):
		_tab_alarm_btn.add_theme_color_override("font_color", active if _tab_mode == "alarm" else inactive)

# ── Timer ─────────────────────────────────────────────────────────────────────

func _on_timer_go() -> void:
	if _tstate == TState.RUNNING:
		_tstate = TState.IDLE
		_timer_left = 0.0
		_update_timer_display()
		return
	_tstate = TState.RUNNING
	_timer_left = float(_timer_spin.value) * 60.0
	if is_instance_valid(_timer_go_btn): _timer_go_btn.text = MandaloreText.a("■  STOP")
	_update_timer_display()

# ── Alarm ─────────────────────────────────────────────────────────────────────

func _on_alarm_toggle() -> void:
	if _alarm_active:
		_alarm_active = false
		_alarm_fired  = false
		if is_instance_valid(_alarm_set_btn):  _alarm_set_btn.text  = MandaloreText.a("SET ALARM")
		if is_instance_valid(_alarm_info_lbl): _alarm_info_lbl.text = MandaloreText.a("No alarm set")
	else:
		_alarm_active = true
		_alarm_fired  = false
		_alarm_h = int(_alarm_h_spin.value)
		_alarm_m = int(_alarm_m_spin.value)
		if is_instance_valid(_alarm_set_btn):  _alarm_set_btn.text  = MandaloreText.a("CLEAR ALARM")
		if is_instance_valid(_alarm_info_lbl):
			_alarm_info_lbl.text = MandaloreText.a("Alarm: %02d:%02d" % [_alarm_h, _alarm_m])

func _ring_alarm() -> void:
	if is_instance_valid(_alarm_player): _alarm_player.play()
	get_tree().create_timer(0.55).timeout.connect(
		func(): if is_instance_valid(_alarm_player): _alarm_player.play())
	get_tree().create_timer(1.10).timeout.connect(
		func(): if is_instance_valid(_alarm_player): _alarm_player.play())

# ── Weather ───────────────────────────────────────────────────────────────────

func _fetch_geo() -> void:
	_http_geo.request("http://ip-api.com/json?fields=city,regionName,lat,lon")

func _on_geo_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var j: Variant = JSON.parse_string(body.get_string_from_utf8())
	if j is Dictionary:
		_lat = float(j.get("lat", 0.0))
		_lon = float(j.get("lon", 0.0))
		var city:   String = j.get("city", "")
		var region: String = j.get("regionName", "")
		_city_lbl.text = MandaloreText.a(("%s, %s" % [city, region]).strip_edges())
		_fetch_weather()

func _fetch_weather() -> void:
	var url := ("https://api.open-meteo.com/v1/forecast"
		+ "?latitude=%.4f&longitude=%.4f" % [_lat, _lon]
		+ "&current=temperature_2m,weathercode&temperature_unit=celsius")
	_http_weather.request(url)

func _on_weather_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var j: Variant = JSON.parse_string(body.get_string_from_utf8())
	if j is Dictionary and j.has("current"):
		var cur: Dictionary = j["current"]
		var temp:  float = float(cur.get("temperature_2m", 0.0))
		var wcode: int   = int(cur.get("weathercode", 0))
		_weather_lbl.text = MandaloreText.a("%s — %.0f°C" % [WMO_LABELS.get(wcode, "Unknown"), temp])

# ── Session ───────────────────────────────────────────────────────────────────

func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "duration", _session_sec)
	cfg.save(SAVE_PATH)

func _load_session() -> void:
	_start_time = Time.get_unix_time_from_system()   # always reset on launch
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_session_sec = cfg.get_value("session", "duration", 7200.0)

func reset_session() -> void:
	_start_time = Time.get_unix_time_from_system()
	_save_session()

func get_session_elapsed() -> float:
	return Time.get_unix_time_from_system() - _start_time

func get_session_remaining() -> float:
	return maxf(0.0, _session_sec - get_session_elapsed())

func extend_session(extra_seconds: float) -> void:
	_session_sec += extra_seconds
	_save_session()

# ── Inner: scrolling label ────────────────────────────────────────────────────

class _RunLabel extends Control:
	const SPEED := 45.0
	const PAUSE := 1.5

	var _lbl:  Label
	var _ox:   float = 0.0
	var _dir:  float = -1.0
	var _wait: float = PAUSE

	func _init() -> void:
		size_flags_horizontal = SIZE_EXPAND_FILL
		_lbl = Label.new()
		_lbl.clip_text = false
		_lbl.mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		clip_contents = true
		add_child(_lbl)

	func cfg(fsize: int, col: Color, font: FontFile = null) -> void:
		_lbl.add_theme_font_size_override("font_size", fsize)
		_lbl.add_theme_color_override("font_color", col)
		if font:
			_lbl.add_theme_font_override("font", font)
		custom_minimum_size.y = float(fsize) + 4.0

	func set_text(t: String) -> void:
		if _lbl.text =MandaloreText.a(= t:)
			return
		_lbl.text = MandaloreText.a(t)
		_ox   = 0.0
		_dir  = -1.0
		_wait = PAUSE
		if is_node_ready():
			_lbl.position.x = 0.0

	func _process(delta: float) -> void:
		var text_w := _lbl.get_combined_minimum_size().x
		if text_w <= size.x:
			_lbl.position.x = 0.0
			_ox = 0.0
			return
		if _wait > 0.0:
			_wait -= delta
			return
		_ox += SPEED * _dir * delta
		var max_off := -(text_w - size.x)
		if _ox <= max_off:
			_ox = max_off; _dir = 1.0; _wait = PAUSE
		elif _ox >= 0.0:
			_ox = 0.0; _dir = -1.0; _wait = PAUSE
		_lbl.position.x = _ox
