extends RefCounted
class_name ArcticTerrainSettings
## Persisted "Terrain Edit" tuning — res://arctic_terrain.cfg, sibling to mechanic_terrain.cfg (own file, not
## shared). Same static load()/save() shape as MechanicTerrainSettings. Loaded by arctic_ground.gd /
## arctic_clouds.gd / arctic_trees.gd at their own _ready() and re-applied LIVE while the Terrain Edit panel
## (arctic_terrain_edit.gd) is open.
##
## Density/Scale-range/Blur are PER-ASSET (asset_settings: type_name -> {density, scale_min, scale_max, blur})
## — each discovered .glb (ArcticAssetScan) gets its own independent tuning (empty today, no scatter .glb
## exists yet — see arctic_trees.gd).
##
## No "canopy_count" key here — 2026-08-19, on request ("hệ thống blend dynamic tự động phát hiện"): unlike
## Mechanic's fixed 7, how many canopy photos blend together is auto-detected fresh from however many images
## sit in assets/map/arctic/maptile/<maptile_set>/ (ArcticAssetScan.canopy_count()) every time the map loads
## or the Tile Set dropdown changes — never a saved/user-set number, so there's nothing to persist for it.
## river_count's slider range in the Terrain Edit panel is likewise capped at the CURRENT canopy_count-1, not
## a fixed 6 the way Mechanic's is.
##
## No landmark_ring_width — Arctic's ground has no landmark ring/patch system yet (mirrors MechanicTerrainSettings'
## own omission for the same reason).

const CFG_PATH := "res://arctic_terrain.cfg"

const DEFAULT_ASSET_DENSITY := 50.0
const DEFAULT_ASSET_SCALE_MIN := 0.8
const DEFAULT_ASSET_SCALE_MAX := 1.2
const DEFAULT_ASSET_SCALE_BIAS := 0.5
const DEFAULT_ASSET_BLUR := 0.0
const DEFAULT_ASSET_ENABLED := true

const DEFAULT_CLOUD_OPACITY := 1.0
const DEFAULT_CLOUD_BRIGHTNESS := 1.0
const DEFAULT_CLOUD_COLOR := Color(1.0, 1.0, 1.0)
const DEFAULT_CLOUD_CLUMPINESS := 0.65
const DEFAULT_CLOUD_WIND_STRENGTH := 15.0   # px/s the clouds continuously drift, independent of camera motion
const DEFAULT_CLOUD_WIND_ANGLE_DEG := 0.0   # compass direction of that drift (0 = +X/east, 90 = +Y/south)
const DEFAULT_COLOR_A := Color(0.55, 0.75, 0.92)   # "blue" zone base color — icy pale blue, distinct from Mechanic's
const DEFAULT_COLOR_B := Color(0.85, 0.90, 0.95)   # "sand" zone base color — snow white, distinct from Mechanic's dark sand
const DEFAULT_RIVER_WIDTH := 0.035   # half-width in MOTTLE-value space — river runs along the canopy blend's
                                      # own seam lines, not an independent field
const DEFAULT_RIVER_COUNT := 3.0     # how many of the (canopy_count - 1) seams carry a river — Terrain Edit
                                      # panel's "River Count", clamped live to the current canopy_count - 1
const DEFAULT_RIVER_BANK_WIDTH := 0.022   # extra noise-value half-width the sand fringe extends beyond river_width
const DEFAULT_JITTER := 0.8
const DEFAULT_CANOPY_SIZE := 1600.0     # world-px spanned by one repeat of whichever photo is showing
const DEFAULT_CANOPY_MOTTLE_SCALE := 3200.0   # "Canopy Blend Sparseness" — world-px stretch on the region-split field
const DEFAULT_CANOPY_BLEND_WIDTH := 0.04   # smoothstep half-width around each region-threshold crossing
const DEFAULT_RIVER_BANK_COLOR := Color(0.90, 0.93, 0.97)   # pale icy sand/frost bank
const DEFAULT_WATER_COLOR := Color(0.25, 0.55, 0.72)         # cold blue-teal meltwater
const DEFAULT_WATER_WAVE_SIZE := 260.0
const DEFAULT_MAPTILE_SET := "default"   # subfolder of assets/map/arctic/maptile/ — see arctic_ground.gd
const DEFAULT_WATER_TILE_SET := ""       # no watertile set exists yet — apply_water_tile_set() no-ops on ""
const DEFAULT_CANOPY_LIGHT_ANGLE_DEG := 55.0
const DEFAULT_CANOPY_LIGHT_HEIGHT := 0.6
const DEFAULT_CANOPY_AMBIENT := 0.5
const DEFAULT_CANOPY_SPECULAR := 0.35
const DEFAULT_CANOPY_CONTRAST := 1.0
const DEFAULT_CANOPY_LIGHT_COLOR := Color(0.95, 0.97, 1.0)   # cool white sun, distinct from Mechanic's warm one
const DEFAULT_SPARK_AMOUNT := 40.0
const DEFAULT_SPARK_COLOR := Color(0.85, 0.92, 1.0)   # pale icy motes instead of Mechanic's amber
const DEFAULT_SPARK_SPEED := 12.0
const DEFAULT_SPARK_SIZE := 60.0
const DEFAULT_SPARK_DIRECTION_DEG := 270.0
const DEFAULT_SPARK_BRIGHTNESS := 1.6
const DEFAULT_SPARK_OPACITY := 1.0

# ── ENERGY BEAM vent defaults — same single-kind straight-column design as Mechanic's (see
# mechanic_plumes.gd's header), pale icy-blue/white palette to match Arctic's theme ─────────────────────────
const DEFAULT_BEAM_STRENGTH := 1.0
const DEFAULT_BEAM_DENSITY := 50.0
const DEFAULT_BEAM_SPEED := 1500.0
const DEFAULT_BEAM_DURATION := 1.5
const DEFAULT_BEAM_COLOR_0 := Color(0.70, 0.90, 1.00)   # pale ice blue
const DEFAULT_BEAM_COLOR_1 := Color(0.85, 0.95, 1.00)   # near-white frost
const DEFAULT_BEAM_COLOR_2 := Color(0.55, 0.80, 0.98)   # deeper sky blue
const DEFAULT_BEAM_COLOR_3 := Color(0.75, 0.98, 1.00)   # pale cyan
const DEFAULT_BEAM_COLOR_4 := Color(0.60, 0.95, 0.95)   # aurora teal
const DEFAULT_BEAM_COLOR_5 := Color(0.80, 0.85, 1.00)   # violet-frost
const DEFAULT_BEAM_MARKS: Array = []

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
