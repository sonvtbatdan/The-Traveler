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

const DEFAULT_ASSET_DENSITY := 1.0     # multiplier on that asset's spawn chance
const DEFAULT_ASSET_SCALE_MIN := 0.8   # random-scale range floor (matches the old fixed-scale ±20% jitter)
const DEFAULT_ASSET_SCALE_MAX := 1.2   # random-scale range ceiling
const DEFAULT_ASSET_SCALE_BIAS := 0.5  # 0=mostly small (near scale_min), 1=mostly large (near scale_max), 0.5=uniform
const DEFAULT_ASSET_BLUR := 0.0        # px blur radius on that asset's own composite (0..6)

const DEFAULT_CLOUD_OPACITY := 1.0      # multiplier on each cloud layer's max_alpha
const DEFAULT_CLOUD_BRIGHTNESS := 1.0   # multiplier on cloud color brightness
const DEFAULT_COLOR_A := Color(0.30, 0.56, 0.90)   # "blue" zone base color
const DEFAULT_COLOR_B := Color(0.46, 0.36, 0.15)   # "sand" zone base color
const DEFAULT_RIVER_WIDTH := 0.035      # half-width of the river band, noise-value space (0 = no rivers)

## Per-asset defaults for a type that has no saved entry yet.
static func default_asset_entry() -> Dictionary:
	return {
		"density": DEFAULT_ASSET_DENSITY,
		"scale_min": DEFAULT_ASSET_SCALE_MIN,
		"scale_max": DEFAULT_ASSET_SCALE_MAX,
		"scale_bias": DEFAULT_ASSET_SCALE_BIAS,
		"blur": DEFAULT_ASSET_BLUR,
	}

static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	var d := {
		"cloud_opacity": DEFAULT_CLOUD_OPACITY,
		"cloud_brightness": DEFAULT_CLOUD_BRIGHTNESS,
		"color_a": DEFAULT_COLOR_A,
		"color_b": DEFAULT_COLOR_B,
		"river_width": DEFAULT_RIVER_WIDTH,
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
