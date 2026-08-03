extends RefCounted
class_name RubiconTerrainSettings
## Persisted "Terrain Edit" tuning — res://rubicon_terrain.cfg, same static load()/save() shape as
## creep_info_panel.gd's overrides file. Loaded by rubicon_ground.gd / rubicon_clouds.gd / rubicon_trees.gd
## at their own _ready() (mirrors creep_info_panel's "each system applies overrides at its own _ready()"
## convention) and re-applied LIVE while the Terrain Edit panel (rubicon_terrain_edit.gd) is open.
##
## Density/Scale-range/Blur are PER-ASSET (asset_settings: type_name -> {density, scale_min, scale_max,
## blur}) — each discovered .glb (RubiconAssetScan) gets its own independent tuning, selected via the
## panel's asset list. Every SCATTERED INSTANCE of that type rolls its own random scale in [scale_min,
## scale_max] (replaces the old fixed Scale + hidden +/-20% jitter with a directly user-controlled range).
## Cloud and terrain-color knobs stay global (they're not tied to any one asset).

const CFG_PATH := "res://rubicon_terrain.cfg"

const DEFAULT_ASSET_DENSITY := 50.0    # 0..100 — direct % chance per candidate cell this type spawns
                                        # independently of every other type (see rubicon_trees.gd's
                                        # _maybe_place); 0 = never, 100 = tries every cell (skips only where
                                        # there's genuinely no room left, via the footprint no-overlap check)
const DEFAULT_ASSET_SCALE_MIN := 0.8   # random-scale range floor (matches the old fixed-scale ±20% jitter)
const DEFAULT_ASSET_SCALE_MAX := 1.2   # random-scale range ceiling
const DEFAULT_ASSET_SCALE_BIAS := 0.5  # 0=mostly small (near scale_min), 1=mostly large (near scale_max), 0.5=uniform
const DEFAULT_ASSET_BLUR := 0.0        # px blur radius on that asset's own composite (0..6)
const DEFAULT_ASSET_ENABLED := true    # false = never spawn this type at all, independent of its density value

const DEFAULT_CLOUD_OPACITY := 1.0      # multiplier on each cloud layer's max_alpha
const DEFAULT_CLOUD_BRIGHTNESS := 1.0   # multiplier on cloud color intensity
const DEFAULT_CLOUD_COLOR := Color(1.0, 1.0, 1.0)   # base cloud tint (brightness_mult scales its intensity)
const DEFAULT_COLOR_A := Color(0.30, 0.56, 0.90)   # "blue" zone base color
const DEFAULT_COLOR_B := Color(0.46, 0.36, 0.15)   # "sand" zone base color
const DEFAULT_RIVER_WIDTH := 0.035      # half-width of the river band, noise-value space (0 = no rivers)
const DEFAULT_JITTER := 0.8             # scatter jitter, fraction of CELL_SIZE (0 = rigid grid, higher = more organic)
const DEFAULT_CANOPY_SIZE := 1600.0     # world-px spanned by one canopy-photo tile — see rubicon_ground.gd
const DEFAULT_RIVER_BANK_COLOR := Color(0.87, 0.74, 0.40)   # golden sand fringe between canopy and water
const DEFAULT_WATER_COLOR := Color(0.15, 0.45, 0.65)         # base river water tone — see rubicon_ground.gd
const DEFAULT_WATER_WAVE_SIZE := 260.0  # world-px spanned by one wave-texture tile — see rubicon_ground.gd
const DEFAULT_CLOUD_CLUMPINESS := 0.65  # 0=soft misty veil, 1=distinct chunky masses w/ clear gaps — see
                                         # rubicon_clouds.gd/rubicon_trees.gd's cloud occluder
const DEFAULT_MAPTILE_SET := "green"    # subfolder of assets/map/rubicon/maptile/ — see rubicon_ground.gd
const DEFAULT_WATER_TILE_SET := "B"     # subfolder of assets/map/rubicon/watertile/ — see rubicon_ground.gd
const DEFAULT_LANDMARK_RING_WIDTH := 32.0   # world-px width of the worn-clearing band around each landmark
                                             # (e.g. the temple boss) — see rubicon_ground.gd/.gdshader
const DEFAULT_CANOPY_LIGHT_ANGLE_DEG := 55.0   # canopy normal-map lighting (rubicon_ground.gd's
                                                # apply_canopy_lighting / tools/generate_canopy_normal.py) —
                                                # compass direction of the "sun" across the ground plane
const DEFAULT_CANOPY_LIGHT_HEIGHT := 0.6       # 0 = fully grazing (dramatic long shadows), 1 = fully overhead (flat)
const DEFAULT_CANOPY_AMBIENT := 0.45           # floor brightness on the shadow side (0 = can go pure black)
const DEFAULT_CANOPY_SPECULAR := 0.3           # glossy highlight strength (0 = none)
const DEFAULT_CANOPY_CONTRAST := 1.0           # pivot-at-0.5 contrast on the diffuse term — 1 = unchanged,
                                                # >1 = punchier highlight/shadow separation, <1 = flatter
const DEFAULT_CANOPY_LIGHT_COLOR := Color(1.0, 0.95, 0.85)   # "sun" tint — see rubicon_ground.gdshader's
                                                               # canopy_light_color
const DEFAULT_SPARK_AMOUNT := 40.0             # floating spark/dust-mote particle count (rubicon_sparks.gd) — 0 = off
const DEFAULT_SPARK_COLOR := Color(1.0, 0.85, 0.6)   # spark tint — independent of canopy_light_color
const DEFAULT_SPARK_SPEED := 12.0              # direct px/s drift speed (0 = stationary, 100 = ~100px/s)
const DEFAULT_SPARK_SIZE := 60.0               # direct on-screen px size (0 = invisible, 100 = ~100px)
const DEFAULT_SPARK_DIRECTION_DEG := 270.0     # drift direction (0=right, 90=down, 180=left, 270=up — screen
                                                # angle convention, Y+ down); 270 = straight up (rising motes)
const DEFAULT_SPARK_BRIGHTNESS := 1.6          # >1 by default — pushes spark color past the arena's HDR glow
                                                # threshold (arena.gd's glow_hdr_threshold 1.0) for a slight bloom
const DEFAULT_SPARK_OPACITY := 1.0             # overall max-alpha cap on top of the fade-in/out color_ramp

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
		"color_a": DEFAULT_COLOR_A,
		"color_b": DEFAULT_COLOR_B,
		"river_width": DEFAULT_RIVER_WIDTH,
		"jitter": DEFAULT_JITTER,
		"canopy_size": DEFAULT_CANOPY_SIZE,
		"river_bank_color": DEFAULT_RIVER_BANK_COLOR,
		"water_color": DEFAULT_WATER_COLOR,
		"water_wave_size": DEFAULT_WATER_WAVE_SIZE,
		"maptile_set": DEFAULT_MAPTILE_SET,
		"water_tile_set": DEFAULT_WATER_TILE_SET,
		"landmark_ring_width": DEFAULT_LANDMARK_RING_WIDTH,
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
		"asset_settings": {},   # type_name -> {density, scale, blur}; missing type = default_asset_entry()
	}
	if cfg.load(CFG_PATH) != OK:
		return d
	for key: String in d.keys():
		d[key] = cfg.get_value("terrain", key, d[key])
	if not (d["asset_settings"] is Dictionary):
		d["asset_settings"] = {}
	# Migrate: a save from before scale_min/scale_max existed (or missing any future field) would have
	# entries lacking those keys — merge every saved entry against current defaults so callers can always
	# safely index entry["scale_min"]/etc. without checking .has() first.
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
