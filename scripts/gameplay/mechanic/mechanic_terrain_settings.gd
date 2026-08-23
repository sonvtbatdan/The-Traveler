extends RefCounted
class_name MechanicTerrainSettings
## Persisted "Terrain Edit" tuning — res://mechanic_terrain.cfg, sibling to electric_terrain.cfg (own file,
## not shared). Same static load()/save() shape as ElectricTerrainSettings. Loaded by mechanic_ground.gd /
## mechanic_clouds.gd / mechanic_trees.gd at their own _ready() and re-applied LIVE while the Terrain Edit
## panel (mechanic_terrain_edit.gd) is open.
##
## Density/Scale-range/Blur are PER-ASSET (asset_settings: type_name -> {density, scale_min, scale_max,
## blur}) — each discovered .glb (MechanicAssetScan) gets its own independent tuning (empty today, no .glb
## exists yet — see mechanic_trees.gd). Cloud and terrain-color knobs stay global.
##
## No landmark_ring_width — Mechanic has no landmark .glb yet (see mechanic_ground.gdshader's header), unlike
## Electric's equivalent settings file.

const CFG_PATH := "res://mechanic_terrain.cfg"

const DEFAULT_ASSET_DENSITY := 50.0
const DEFAULT_ASSET_SCALE_MIN := 0.8
const DEFAULT_ASSET_SCALE_MAX := 1.2
const DEFAULT_ASSET_SCALE_BIAS := 0.5
const DEFAULT_ASSET_BLUR := 0.0
const DEFAULT_ASSET_ENABLED := true

const DEFAULT_CLOUD_OPACITY := 1.0
const DEFAULT_CLOUD_BRIGHTNESS := 1.0
const DEFAULT_CLOUD_COLOR := Color(1.0, 1.0, 1.0)
const DEFAULT_CLOUD_WIND_STRENGTH := 15.0   # px/s the clouds continuously drift, independent of camera motion
                                             # — Terrain Edit panel's Cloud tab, see mechanic_clouds.gd's header
const DEFAULT_CLOUD_WIND_ANGLE_DEG := 0.0   # compass direction of that drift (0 = +X/east, 90 = +Y/south)
const DEFAULT_COLOR_A := Color(0.30, 0.56, 0.90)   # "blue" zone base color — same starting point as Electric
const DEFAULT_COLOR_B := Color(0.46, 0.36, 0.15)   # "sand" zone base color
const DEFAULT_RIVER_WIDTH := 0.035   # half-width in MOTTLE-value space (2026-08-19: river now runs along the
                                      # canopy blend's own seam lines, not an independent field — see
                                      # mechanic_ground.gdshader's header); seams sit 1/7≈0.143 apart, so this
                                      # stays well under that.
const DEFAULT_RIVER_COUNT := 3.0     # 0..6 — how many of the 7-way canopy blend's 6 seam lines carry a river
                                      # ("River Count") — Terrain Edit panel's River tab.
const DEFAULT_RIVER_BANK_WIDTH := 0.022   # extra noise-value half-width the sand fringe extends beyond
                                           # river_width — Terrain Edit panel's River tab "River Bank Width"
const DEFAULT_JITTER := 0.8
const DEFAULT_CANOPY_SIZE := 1600.0     # world-px spanned by one repeat of whichever photo is showing — see
                                         # mechanic_ground.gd's apply_canopy_size
const DEFAULT_CANOPY_MOTTLE_SCALE := 3200.0   # "Canopy Blend Sparseness" — world-px stretch on the region-
                                               # split field; bigger = transitions land farther apart, more of
                                               # any one photo shows intact — see apply_canopy_mottle_scale
const DEFAULT_CANOPY_BLEND_WIDTH := 0.04   # smoothstep half-width around each region-threshold crossing —
                                            # mirrors Electric's own fixed value; see mechanic_ground.gdshader
const DEFAULT_RIVER_BANK_COLOR := Color(0.87, 0.74, 0.40)
const DEFAULT_WATER_COLOR := Color(0.15, 0.45, 0.65)
const DEFAULT_WATER_WAVE_SIZE := 260.0
const DEFAULT_CLOUD_CLUMPINESS := 0.65
const DEFAULT_MAPTILE_SET := "default"   # subfolder of assets/map/mechanic/maptile/ — see mechanic_ground.gd
const DEFAULT_WATER_TILE_SET := ""       # no watertile set exists yet — apply_water_tile_set() no-ops on ""
const DEFAULT_CANOPY_LIGHT_ANGLE_DEG := 55.0
const DEFAULT_CANOPY_LIGHT_HEIGHT := 0.6
const DEFAULT_CANOPY_AMBIENT := 0.45
const DEFAULT_CANOPY_SPECULAR := 0.3
const DEFAULT_CANOPY_CONTRAST := 1.0
const DEFAULT_CANOPY_LIGHT_COLOR := Color(1.0, 0.95, 0.85)
const DEFAULT_SPARK_AMOUNT := 40.0
const DEFAULT_SPARK_COLOR := Color(1.0, 0.85, 0.6)
const DEFAULT_SPARK_SPEED := 12.0
const DEFAULT_SPARK_SIZE := 60.0
const DEFAULT_SPARK_DIRECTION_DEG := 270.0
const DEFAULT_SPARK_BRIGHTNESS := 1.6
const DEFAULT_SPARK_OPACITY := 1.0

# ── ENERGY BEAM vent defaults — a single kind (unlike Volcanic's smoke+flame split; see mechanic_plumes.gd's
# header for why), bright blue/cyan vertical pulses matching the canopy art's tech-circuit palette. Straight
# columns have no wind to drift with, so (unlike the first "steam puff" pass) there is no wind system here —
# see mechanic_plumes.gd's header for the 2026-08-19 redesign ───────────────────────────────────────────────
const DEFAULT_BEAM_STRENGTH := 1.0      # column thickness + brightness multiplier ("Beam Strength")
const DEFAULT_BEAM_DENSITY := 50.0      # 0..100 — drives BOTH the ambient-vent chance AND the marked-vent
                                         # reveal fraction — see mechanic_plumes.gd's apply_beam_settings
const DEFAULT_BEAM_SPEED := 1500.0      # px/s the column shoots upward ("Tốc độ bắn")
const DEFAULT_BEAM_DURATION := 1.5      # seconds fully risen/visible before fading ("Duration luồng bắn")
const DEFAULT_BEAM_COLOR_0 := Color(0.25, 0.55, 1.00)   # bright blue
const DEFAULT_BEAM_COLOR_1 := Color(0.40, 0.75, 1.00)   # cyan-blue
const DEFAULT_BEAM_COLOR_2 := Color(0.15, 0.40, 0.95)   # deep blue
const DEFAULT_BEAM_COLOR_3 := Color(0.60, 0.85, 1.00)   # pale sky blue
const DEFAULT_BEAM_COLOR_4 := Color(0.30, 0.90, 1.00)   # electric cyan
const DEFAULT_BEAM_COLOR_5 := Color(0.50, 0.60, 1.00)   # violet-blue
const DEFAULT_BEAM_MARKS: Array = []    # user-placed vent marks (mechanic_vent_mark.gd) — {"tex": 0..6, "u":
                                         # float, "v": float}, replicated at every world-space repeat of that
                                         # photo by mechanic_plumes.gd, same convention as Volcanic's craters

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

static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	var d := {
		"cloud_opacity": DEFAULT_CLOUD_OPACITY,
		"cloud_brightness": DEFAULT_CLOUD_BRIGHTNESS,
		"cloud_color": DEFAULT_CLOUD_COLOR,
		"cloud_clumpiness": DEFAULT_CLOUD_CLUMPINESS,
		"cloud_wind_strength": DEFAULT_CLOUD_WIND_STRENGTH,
		"cloud_wind_angle_deg": DEFAULT_CLOUD_WIND_ANGLE_DEG,
		"color_a": DEFAULT_COLOR_A,
		"color_b": DEFAULT_COLOR_B,
		"river_width": DEFAULT_RIVER_WIDTH,
		"river_count": DEFAULT_RIVER_COUNT,
		"river_bank_width": DEFAULT_RIVER_BANK_WIDTH,
		"jitter": DEFAULT_JITTER,
		"canopy_size": DEFAULT_CANOPY_SIZE,
		"canopy_mottle_scale": DEFAULT_CANOPY_MOTTLE_SCALE,
		"canopy_blend_width": DEFAULT_CANOPY_BLEND_WIDTH,
		"river_bank_color": DEFAULT_RIVER_BANK_COLOR,
		"water_color": DEFAULT_WATER_COLOR,
		"water_wave_size": DEFAULT_WATER_WAVE_SIZE,
		"maptile_set": DEFAULT_MAPTILE_SET,
		"water_tile_set": DEFAULT_WATER_TILE_SET,
		"canopy_light_angle_deg": DEFAULT_CANOPY_LIGHT_ANGLE_DEG,
		"canopy_light_height": DEFAULT_CANOPY_LIGHT_HEIGHT,
		"canopy_ambient": DEFAULT_CANOPY_AMBIENT,
		"canopy_specular": DEFAULT_CANOPY_SPECULAR,
		"canopy_contrast": DEFAULT_CANOPY_CONTRAST,
		"canopy_light_color": DEFAULT_CANOPY_LIGHT_COLOR,
		"spark_amount": DEFAULT_SPARK_AMOUNT,
		"spark_color": DEFAULT_SPARK_COLOR,
		"spark_speed": DEFAULT_SPARK_SPEED,
		"spark_size": DEFAULT_SPARK_SIZE,
		"spark_direction_deg": DEFAULT_SPARK_DIRECTION_DEG,
		"spark_brightness": DEFAULT_SPARK_BRIGHTNESS,
		"spark_opacity": DEFAULT_SPARK_OPACITY,
		"beam_strength": DEFAULT_BEAM_STRENGTH,
		"beam_density": DEFAULT_BEAM_DENSITY,
		"beam_speed": DEFAULT_BEAM_SPEED,
		"beam_duration": DEFAULT_BEAM_DURATION,
		"beam_color_0": DEFAULT_BEAM_COLOR_0,
		"beam_color_1": DEFAULT_BEAM_COLOR_1,
		"beam_color_2": DEFAULT_BEAM_COLOR_2,
		"beam_color_3": DEFAULT_BEAM_COLOR_3,
		"beam_color_4": DEFAULT_BEAM_COLOR_4,
		"beam_color_5": DEFAULT_BEAM_COLOR_5,
		"beam_marks": DEFAULT_BEAM_MARKS.duplicate(true),
		"asset_settings": {},
	}
	if cfg.load(CFG_PATH) != OK:
		return d
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
