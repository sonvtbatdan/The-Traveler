extends RefCounted
class_name VolcanicTerrainSettings
## Persisted "Terrain Edit" tuning — res://volcanic_terrain.cfg, mirrors electric/electric_terrain_settings.gd
## (same static load()/save() shape, same per-asset density/scale-range/blur/enabled convention). Loaded by
## volcanic_ground.gd / volcanic_clouds.gd / volcanic_trees.gd / volcanic_temple_layer.gd at their own _ready()
## and re-applied LIVE while the relevant dev panel is open.
##
## Deltas from Electric's defaults: a volcanic palette (dark basalt/ash zone tint, lava colors, obsidian bank).
##
## TWO plume KINDS — "smoke" and "flame" (user feedback: "thêm 1 loại plume nữa là flame plume... chia bảng
## plume thành 2 tab") — every plume-related setting exists once per kind, with a `smoke_`/`flame_` prefix.
## "smoke_*" are the RENAMED originals (were `cloud_opacity`/`cloud_brightness`/`cloud_clumpiness`/
## `plume_speed`/`plume_height`/`mark_reveal_percent`/`plume_color_0..5`/`crater_marks` before flame existed) —
## load_settings() migrates any already-saved values under the old names into their new "smoke_" home the
## first time this loads, so existing tuning/marks survive the rename. Wind (wind_strength_max) stays a SINGLE
## shared setting — one wind affects both kinds' plumes together (see volcanic_clouds.gd's header).
##
## LANDMARK marks (landmark_marks_smoke/flame) are a SEPARATE concept from crater marks — see
## volcanic_temple_layer.gd's header: a point in the TEMPLE MODEL's own local space (fraction of its
## bake-reference frame, not a UV on an infinitely-tiled ground photo), placed by volcanic_landmark_mark.gd.

const CFG_PATH := "res://volcanic_terrain.cfg"

const DEFAULT_ASSET_DENSITY := 50.0
const DEFAULT_ASSET_SCALE_MIN := 0.8
const DEFAULT_ASSET_SCALE_MAX := 1.2
const DEFAULT_ASSET_SCALE_BIAS := 0.5
const DEFAULT_ASSET_BLUR := 0.0
const DEFAULT_ASSET_ENABLED := true

const DEFAULT_COLOR_A := Color(0.10, 0.10, 0.14)               # "dark basalt" zone tint (near-black, cool)
const DEFAULT_COLOR_B := Color(0.30, 0.24, 0.20)               # "ash/dust" zone tint (warm charcoal-brown)
const DEFAULT_RIVER_WIDTH := 0.035      # half-width of the lava band, noise-value space (0 = no lava)
const DEFAULT_RIVER_BANK_WIDTH := 0.012 # noise-value half-width the obsidian rim extends beyond river_width —
                                         # user feedback: "thanh slider chỉnh viền river giống như của
                                         # electric" — Electric's own equivalent (RIVER_BANK_WIDTH) is actually
                                         # a hardcoded constant too, not a slider; exposing it here as one.
const DEFAULT_RIVER_EDGE_JAGGEDNESS := 0.55   # cracked-edge perturbation strength, as a fraction of
                                               # river_width — see volcanic_ground.gdshader's
                                               # river_detail_strength for the mechanic. The OTHER "viền
                                               # river" knob this slider addresses: how jagged/angular the
                                               # lava boundary reads, not just how wide its bank rim is.
const DEFAULT_JITTER := 0.8
const DEFAULT_CANOPY_SIZE := 1600.0     # world-px spanned by one ground-photo tile
const DEFAULT_RIVER_BANK_COLOR := Color(0.16, 0.05, 0.03)      # dark obsidian crust rim (replaces Electric's
                                                                 # golden sand fringe — a thin cracked edge,
                                                                 # not a beach)
const DEFAULT_WATER_COLOR := Color(0.95, 0.45, 0.05)            # base lava tone (bright orange)
const DEFAULT_WATER_WAVE_SIZE := 260.0
const DEFAULT_WATER_WAVE_SPEED := 10.0  # world-px/sec the lava wave texture scrolls — slower than the value
                                         # this started at (26.0) per user feedback ("dòng chảy chậm lại");
                                         # tunable via the Terrain Edit panel's "Lava Flow Speed" slider
const DEFAULT_MAPTILE_SET := "lava"     # subfolder of assets/map/volcanic/maptile/
const DEFAULT_WATER_TILE_SET := "crust" # subfolder of assets/map/volcanic/watertile/ — "crust" (lava_wave2)
                                         # has dark cracked-crust patches baked into the wave photo itself, so
                                         # the lava reads as molten rock instead of orange-tinted water (user
                                         # feedback); "plain" (the original lava_wave) is still selectable via
                                         # the Terrain Edit panel's "Lava Pattern" dropdown.
const DEFAULT_GROUND_LIGHT_ANGLE_DEG := 55.0   # ground normal-map lighting — compass direction of the "sun"
const DEFAULT_GROUND_LIGHT_HEIGHT := 0.6       # 0 = fully grazing (dramatic long shadows), 1 = fully overhead
const DEFAULT_GROUND_AMBIENT := 0.35           # floor brightness on the shadow side — lower than Electric's
                                                # 0.45 so the cracked rock reads darker/harsher
const DEFAULT_GROUND_SPECULAR := 0.35          # slightly glossier than Electric (wet-looking cooled rock)
const DEFAULT_GROUND_CONTRAST := 1.15          # a bit punchier than Electric — sharper highlight/shadow split
                                                # on the rock relief
const DEFAULT_GROUND_LIGHT_COLOR := Color(1.0, 0.75, 0.55)     # warm ember-tinted "sun", not neutral daylight
const DEFAULT_SPARK_AMOUNT := 40.0             # rising ember particle count (volcanic_sparks.gd) — 0 = off
const DEFAULT_SPARK_COLOR := Color(1.0, 0.5, 0.15)             # ember orange/red (Electric's default nudged redder)
const DEFAULT_SPARK_SPEED := 14.0
const DEFAULT_SPARK_SIZE := 55.0
const DEFAULT_SPARK_DIRECTION_DEG := 270.0     # rising embers (270 = straight up — already correct as-is)
const DEFAULT_SPARK_BRIGHTNESS := 1.8          # pushes past the arena's HDR glow threshold for a hot ember glow
const DEFAULT_SPARK_OPACITY := 1.0

const DEFAULT_WIND_STRENGTH_MAX := 40.0   # px/s^2 ceiling — user feedback: "hướng gió, cường độ gió random".
                                           # volcanic_clouds.gd rolls the ACTUAL direction (0..360°) and
                                           # strength (0..this) fresh every time the map loads, applied
                                           # uniformly to every plume of EITHER kind (one shared "wind today"),
                                           # this setting only caps how strong that random roll can get;
                                           # Plume Edit panel's "Wind Strength" slider + "REROLL WIND" button.

# ── SMOKE plume defaults (renamed from the pre-flame-split keys — see this file's header for migration) ────
const DEFAULT_SMOKE_OPACITY := 1.0
const DEFAULT_SMOKE_BRIGHTNESS := 1.0
const DEFAULT_SMOKE_DENSITY := 0.65     # ambient-vent chance (0..1) — see volcanic_clouds.gd's VENT_CHANCE_MAX
const DEFAULT_SMOKE_SPEED := 24.0       # px/s initial rise velocity
const DEFAULT_SMOKE_HEIGHT := 3.0       # seconds of lifetime before a plume fully fades
const DEFAULT_SMOKE_MARK_REVEAL_PERCENT := 100.0
const DEFAULT_SMOKE_COLOR_0 := Color(0.20, 0.19, 0.19)   # near-black soot
const DEFAULT_SMOKE_COLOR_1 := Color(0.42, 0.40, 0.39)   # mid ash-grey
const DEFAULT_SMOKE_COLOR_2 := Color(0.62, 0.60, 0.58)   # pale smoke
const DEFAULT_SMOKE_COLOR_3 := Color(0.45, 0.36, 0.30)   # warm ash-brown
const DEFAULT_SMOKE_COLOR_4 := Color(0.40, 0.42, 0.46)   # cool blue-grey
const DEFAULT_SMOKE_COLOR_5 := Color(0.55, 0.30, 0.20)   # hot ember-tinted brown-red
const DEFAULT_SMOKE_CRATER_MARKS: Array = []

# ── FLAME plume defaults — a fire/burning effect, not smoke: shorter-lived, faster, brighter, warm-hued,
# additive-blended (see volcanic_clouds.gd's _make_plume). Ambient density defaults to 0 (off) — random fire
# scattered everywhere by default would read as "the whole map is on fire"; flame is meant to be placed
# deliberately via crater/landmark marks, with ambient as an optional extra the user can dial in.
const DEFAULT_FLAME_OPACITY := 1.2
const DEFAULT_FLAME_BRIGHTNESS := 1.6
const DEFAULT_FLAME_DENSITY := 0.0
const DEFAULT_FLAME_SPEED := 45.0
const DEFAULT_FLAME_HEIGHT := 1.0
const DEFAULT_FLAME_MARK_REVEAL_PERCENT := 100.0
const DEFAULT_FLAME_COLOR_0 := Color(1.0, 0.85, 0.3)    # bright yellow core
const DEFAULT_FLAME_COLOR_1 := Color(1.0, 0.55, 0.1)    # orange
const DEFAULT_FLAME_COLOR_2 := Color(0.9, 0.2, 0.05)    # deep red
const DEFAULT_FLAME_COLOR_3 := Color(1.0, 0.95, 0.7)    # white-hot
const DEFAULT_FLAME_COLOR_4 := Color(0.85, 0.4, 0.05)   # amber
const DEFAULT_FLAME_COLOR_5 := Color(0.6, 0.1, 0.02)    # dark ember-red
const DEFAULT_FLAME_CRATER_MARKS: Array = []

## Marked crater positions — see volcanic_crater_mark.gd. Each entry: {"tex": int (0/1/2 = which maptile-set
## photo, matching VolcanicAssetScan.maptile_set_image_paths()' a/b/c order), "u": float, "v": float (normalized
## 0..1 position clicked on that photo)}. volcanic_clouds.gd replicates every entry at EVERY world-space
## repetition of that texture (see its header) — not a single fixed world position — so marking one crater
## once in the reference photo puts a plume above every recurrence of that same crater art anywhere on the map.
## `smoke_crater_marks`/`flame_crater_marks` are independent lists — a spot can be marked for one, the other,
## or both.

## Marked landmark plume points — see volcanic_landmark_mark.gd / volcanic_temple_layer.gd. Each entry:
## {"fx": float, "fz": float} — normalized position (-0.5..0.5 each axis) within the temple model's own
## bake-reference frame (tools/bake_volcanic_landmark.gd), NOT a world position — every currently-spawned
## temple landmark gets a plume at the equivalent LOCAL position on ITS OWN base (rotated/translated by that
## instance's own yaw/position), so one marking session covers every landmark instance, spawned wherever they
## end up on the map.
const DEFAULT_LANDMARK_MARKS: Array = []

## Per-asset defaults for a type that has no saved entry yet.
static func default_asset_entry() -> Dictionary:
	return {
		"density": DEFAULT_ASSET_DENSITY,
		"scale_min": DEFAULT_ASSET_SCALE_MIN,
		"scale_max": DEFAULT_ASSET_SCALE_MAX,
		"scale_bias": DEFAULT_ASSET_SCALE_BIAS,
		"blur": DEFAULT_ASSET_BLUR,
		"enabled": DEFAULT_ASSET_ENABLED,
	}

## Old key name (pre-flame-split) -> new "smoke_"-prefixed key name — see this file's header. Read once in
## load_settings() as a FALLBACK default for the new key, so a save made before flame existed still applies.
const SMOKE_KEY_MIGRATIONS := {
	"smoke_opacity": "cloud_opacity",
	"smoke_brightness": "cloud_brightness",
	"smoke_density": "cloud_clumpiness",
	"smoke_speed": "plume_speed",
	"smoke_height": "plume_height",
	"smoke_mark_reveal_percent": "mark_reveal_percent",
	"smoke_color_0": "plume_color_0",
	"smoke_color_1": "plume_color_1",
	"smoke_color_2": "plume_color_2",
	"smoke_color_3": "plume_color_3",
	"smoke_color_4": "plume_color_4",
	"smoke_color_5": "plume_color_5",
	"smoke_crater_marks": "crater_marks",
}

static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	var d := {
		"color_a": DEFAULT_COLOR_A,
		"color_b": DEFAULT_COLOR_B,
		"river_width": DEFAULT_RIVER_WIDTH,
		"river_bank_width": DEFAULT_RIVER_BANK_WIDTH,
		"river_edge_jaggedness": DEFAULT_RIVER_EDGE_JAGGEDNESS,
		"jitter": DEFAULT_JITTER,
		"canopy_size": DEFAULT_CANOPY_SIZE,
		"river_bank_color": DEFAULT_RIVER_BANK_COLOR,
		"water_color": DEFAULT_WATER_COLOR,
		"water_wave_size": DEFAULT_WATER_WAVE_SIZE,
		"water_wave_speed": DEFAULT_WATER_WAVE_SPEED,
		"maptile_set": DEFAULT_MAPTILE_SET,
		"water_tile_set": DEFAULT_WATER_TILE_SET,
		"ground_light_angle_deg": DEFAULT_GROUND_LIGHT_ANGLE_DEG,
		"ground_light_height": DEFAULT_GROUND_LIGHT_HEIGHT,
		"ground_ambient": DEFAULT_GROUND_AMBIENT,
		"ground_specular": DEFAULT_GROUND_SPECULAR,
		"ground_contrast": DEFAULT_GROUND_CONTRAST,
		"ground_light_color": DEFAULT_GROUND_LIGHT_COLOR,
		"spark_amount": DEFAULT_SPARK_AMOUNT,
		"spark_color": DEFAULT_SPARK_COLOR,
		"spark_speed": DEFAULT_SPARK_SPEED,
		"spark_size": DEFAULT_SPARK_SIZE,
		"spark_direction_deg": DEFAULT_SPARK_DIRECTION_DEG,
		"spark_brightness": DEFAULT_SPARK_BRIGHTNESS,
		"spark_opacity": DEFAULT_SPARK_OPACITY,
		"wind_strength_max": DEFAULT_WIND_STRENGTH_MAX,
		"smoke_opacity": DEFAULT_SMOKE_OPACITY,
		"smoke_brightness": DEFAULT_SMOKE_BRIGHTNESS,
		"smoke_density": DEFAULT_SMOKE_DENSITY,
		"smoke_speed": DEFAULT_SMOKE_SPEED,
		"smoke_height": DEFAULT_SMOKE_HEIGHT,
		"smoke_mark_reveal_percent": DEFAULT_SMOKE_MARK_REVEAL_PERCENT,
		"smoke_color_0": DEFAULT_SMOKE_COLOR_0,
		"smoke_color_1": DEFAULT_SMOKE_COLOR_1,
		"smoke_color_2": DEFAULT_SMOKE_COLOR_2,
		"smoke_color_3": DEFAULT_SMOKE_COLOR_3,
		"smoke_color_4": DEFAULT_SMOKE_COLOR_4,
		"smoke_color_5": DEFAULT_SMOKE_COLOR_5,
		"smoke_crater_marks": DEFAULT_SMOKE_CRATER_MARKS.duplicate(),
		"flame_opacity": DEFAULT_FLAME_OPACITY,
		"flame_brightness": DEFAULT_FLAME_BRIGHTNESS,
		"flame_density": DEFAULT_FLAME_DENSITY,
		"flame_speed": DEFAULT_FLAME_SPEED,
		"flame_height": DEFAULT_FLAME_HEIGHT,
		"flame_mark_reveal_percent": DEFAULT_FLAME_MARK_REVEAL_PERCENT,
		"flame_color_0": DEFAULT_FLAME_COLOR_0,
		"flame_color_1": DEFAULT_FLAME_COLOR_1,
		"flame_color_2": DEFAULT_FLAME_COLOR_2,
		"flame_color_3": DEFAULT_FLAME_COLOR_3,
		"flame_color_4": DEFAULT_FLAME_COLOR_4,
		"flame_color_5": DEFAULT_FLAME_COLOR_5,
		"flame_crater_marks": DEFAULT_FLAME_CRATER_MARKS.duplicate(),
		"landmark_marks_smoke": DEFAULT_LANDMARK_MARKS.duplicate(),
		"landmark_marks_flame": DEFAULT_LANDMARK_MARKS.duplicate(),
		"asset_settings": {},   # type_name -> {density, scale, blur}; missing type = default_asset_entry()
	}
	if cfg.load(CFG_PATH) != OK:
		return d
	for new_key: String in SMOKE_KEY_MIGRATIONS.keys():
		d[new_key] = cfg.get_value("terrain", String(SMOKE_KEY_MIGRATIONS[new_key]), d[new_key])
	for key: String in d.keys():
		d[key] = cfg.get_value("terrain", key, d[key])
	if not (d["asset_settings"] is Dictionary):
		d["asset_settings"] = {}
	var migrated := {}
	for type_name: String in (d["asset_settings"] as Dictionary).keys():
		migrated[type_name] = asset_entry(d, type_name)
	d["asset_settings"] = migrated
	return d

static func save_settings(d: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key: String in d.keys():
		cfg.set_value("terrain", key, d[key])
	cfg.save(CFG_PATH)

## Reads one asset's {density, scale, blur} out of a loaded settings dict, falling back to defaults for
## fields (or the whole entry) that aren't saved yet.
static func asset_entry(settings: Dictionary, type_name: String) -> Dictionary:
	var asset_settings: Dictionary = settings.get("asset_settings", {})
	var saved: Dictionary = asset_settings.get(type_name, {})
	var out := default_asset_entry()
	for key: String in out.keys():
		if saved.has(key):
			out[key] = saved[key]
	return out
