extends RefCounted
class_name AtlanticTerrainSettings
## Persisted "Terrain Edit" tuning — res://atlantic_terrain.cfg, mirrors volcanic/volcanic_terrain_settings.gd
## (same static load()/save() shape, same per-asset density/scale-range/blur/enabled convention). Loaded by
## atlantic_ground.gd / atlantic_clouds.gd / atlantic_trees.gd / atlantic_temple_layer.gd at their own _ready()
## and re-applied LIVE while the relevant dev panel is open.
##
## Deep-sea sunken-city theme (2026-08-06, on request): a blue/teal palette (dark silt / pale sand zone tint,
## current colors, sand-rim bank) instead of Volcanic's basalt/ash/lava.
##
## TWO plume KINDS — "bubble" (rising bubble columns, replaces "smoke") and "whirlpool" (a rotating
## vortex/water-spout funnel, replaces "flame") — every plume-related setting exists once per kind, with a
## `bubble_`/`whirlpool_` prefix, same shape as Volcanic's smoke_/flame_ split (see volcanic_terrain_settings.
## gd's header for the full rationale on why two independently-tunable kinds exist). Wind (here: CURRENT)
## stays a SINGLE shared setting — one current direction/strength affects both kinds' plumes together.
##
## LANDMARK marks (landmark_marks_bubble/whirlpool) are a SEPARATE concept from crater marks — see
## atlantic_temple_layer.gd's header: a point in the (reused Electric) TEMPLE MODEL's own local space (fraction
## of its bake-reference frame), placed by atlantic_landmark_mark.gd.

const CFG_PATH := "res://atlantic_terrain.cfg"

const DEFAULT_ASSET_DENSITY := 50.0
const DEFAULT_ASSET_SCALE_MIN := 0.8
const DEFAULT_ASSET_SCALE_MAX := 1.2
const DEFAULT_ASSET_SCALE_BIAS := 0.5
const DEFAULT_ASSET_BLUR := 0.0
const DEFAULT_ASSET_ENABLED := true

const DEFAULT_COLOR_A := Color(0.05, 0.10, 0.14)               # "dark silt" zone tint (near-black, cool blue)
const DEFAULT_COLOR_B := Color(0.20, 0.28, 0.26)               # "pale sand" zone tint (muted sea-green)
const DEFAULT_RIVER_WIDTH := 0.035      # half-width of the current band, noise-value space (0 = no current)
const DEFAULT_RIVER_BANK_WIDTH := 0.012 # noise-value half-width the sand rim extends beyond river_width
const DEFAULT_RIVER_EDGE_JAGGEDNESS := 0.55   # scour-edge perturbation strength, as a fraction of river_width
const DEFAULT_JITTER := 0.8
const DEFAULT_CANOPY_SIZE := 1600.0     # world-px spanned by one ground-photo tile
const DEFAULT_RIVER_BANK_COLOR := Color(0.55, 0.58, 0.48)      # pale current-swept sand rim (replaces
                                                                 # Volcanic's dark obsidian crust)
const DEFAULT_WATER_COLOR := Color(0.10, 0.55, 0.68)            # base current tone (bright teal)
const DEFAULT_WATER_WAVE_SIZE := 260.0
const DEFAULT_WATER_WAVE_SPEED := 10.0  # world-px/sec the current-shimmer texture scrolls
const DEFAULT_MAPTILE_SET := "ruins"    # subfolder of assets/map/atlantic/maptile/ — awaiting the 3 seabed/
                                         # ruin-floor "canopy" photos (user-supplied)
const DEFAULT_WATER_TILE_SET := "plain" # subfolder of assets/map/atlantic/watertile/
const DEFAULT_WATER_DISTORT_STRENGTH := 0.006   # whole-screen refraction amount (atlantic_water_surface.gd) —
                                                 # keep SMALL, this warps everything on screen including the ship
const DEFAULT_WATER_DISTORT_SPEED := 0.05       # how fast the refraction field drifts
const DEFAULT_WATER_SPARKLE_INTENSITY := 0.35   # brightness of the procedural caustic-sparkle overlay
const DEFAULT_WATER_SPARKLE_COLOR := Color(0.85, 0.97, 1.0)
const DEFAULT_WATER_SPARKLE_SPEED := 0.09       # how fast the caustic network dances
const DEFAULT_GROUND_LIGHT_ANGLE_DEG := 55.0   # ground normal-map lighting — compass direction of the
                                                # down-filtering "sun"
const DEFAULT_GROUND_LIGHT_HEIGHT := 0.6       # 0 = fully grazing (dramatic long shadows), 1 = fully overhead
const DEFAULT_GROUND_AMBIENT := 0.40           # floor brightness on the shadow side — a touch brighter than
                                                # Volcanic's 0.35 (light scatters more underwater than in ash)
const DEFAULT_GROUND_SPECULAR := 0.30
const DEFAULT_GROUND_CONTRAST := 1.05          # softer than Volcanic's 1.15 — underwater light is diffuse,
                                                # less harsh highlight/shadow split
const DEFAULT_GROUND_LIGHT_COLOR := Color(0.55, 0.85, 0.95)    # cool blue-green caustic "sun", not warm ember
const DEFAULT_SPARK_AMOUNT := 40.0             # floating bioluminescent motes/plankton (atlantic_sparks.gd)
const DEFAULT_SPARK_COLOR := Color(0.45, 0.95, 0.85)           # cyan-teal bioluminescence
const DEFAULT_SPARK_SPEED := 8.0                # motes drift slower than Volcanic's embers rise
const DEFAULT_SPARK_SIZE := 40.0
const DEFAULT_SPARK_DIRECTION_DEG := 270.0     # drifting upward (270 = straight up)
const DEFAULT_SPARK_BRIGHTNESS := 1.6
const DEFAULT_SPARK_OPACITY := 0.85

const DEFAULT_WIND_STRENGTH_MAX := 30.0   # px/s^2 ceiling for the shared "current" push on every plume of
                                           # either kind — atlantic_clouds.gd rolls the ACTUAL direction/
                                           # strength fresh every map load, this only caps how strong that
                                           # random roll can get; Plume Edit panel's "Current Strength" slider
                                           # + "REROLL CURRENT" button.

# ── BUBBLE plume defaults (replaces Volcanic's "smoke") ─────────────────────────────────────────────────
const DEFAULT_BUBBLE_OPACITY := 0.85
const DEFAULT_BUBBLE_BRIGHTNESS := 1.1
const DEFAULT_BUBBLE_DENSITY := 30.0    # "Bubble Rate" slider, 0..100 -> 0..10 bubbles/sec (2026-08-08 — was a
                                         # 0..1 ambient-vent CHANCE; see atlantic_clouds.gd's BUBBLE_RATE_DIVISOR)
const DEFAULT_BUBBLE_SPEED := 55.0      # px/s rise velocity, and — since 2026-08-08 — the bubble's actual stable
                                         # observed rise speed (KIND_RISE_ACCEL["bubble"] is now 0)
const DEFAULT_BUBBLE_HEIGHT := 1.6      # seconds of lifetime before a bubble column fully fades/pops
const DEFAULT_BUBBLE_MARK_REVEAL_PERCENT := 100.0
const DEFAULT_BUBBLE_COLOR_0 := Color(0.85, 0.95, 1.0)    # near-white bubble rim
const DEFAULT_BUBBLE_COLOR_1 := Color(0.65, 0.90, 0.95)   # pale cyan
const DEFAULT_BUBBLE_COLOR_2 := Color(0.55, 0.80, 0.90)   # soft blue
const DEFAULT_BUBBLE_COLOR_3 := Color(0.70, 0.95, 0.85)   # pale sea-green
const DEFAULT_BUBBLE_COLOR_4 := Color(0.60, 0.85, 1.0)    # bright sky-blue
const DEFAULT_BUBBLE_COLOR_5 := Color(0.90, 1.0, 0.95)    # bright white-green fizz
const DEFAULT_BUBBLE_CRATER_MARKS: Array = []

# ── WHIRLPOOL plume defaults — a rotating vortex/water-spout funnel, not a rising column (replaces
# Volcanic's "flame"): a ring-emission spiral pulled inward (tangential + centripetal accel) with a vertical
# stretch near the core suggesting a funnel drawing water up. Additive-blended for a shimmering foam
# highlight (see atlantic_clouds.gd's _make_plume). Ambient density defaults to 0 (off) — like flame, meant
# to be placed deliberately via crater/landmark marks.
const DEFAULT_WHIRLPOOL_OPACITY := 1.0
const DEFAULT_WHIRLPOOL_BRIGHTNESS := 1.3
const DEFAULT_WHIRLPOOL_DENSITY := 0.0
const DEFAULT_WHIRLPOOL_SPEED := 70.0     # tangential swirl speed, px/s at the ring's radius
const DEFAULT_WHIRLPOOL_SIZE_MIN := 0.8   # each whirlpool independently rolls a random size multiplier in
const DEFAULT_WHIRLPOOL_SIZE_MAX := 1.3   # [size_min, size_max] at creation and keeps it — 1.0 = WHIRL_RING_RADIUS
const DEFAULT_WHIRLPOOL_ROT_X_DEG := 0.0  # SHARED funnel-mesh tilt (all whirlpools), 0 = perfectly upright
const DEFAULT_WHIRLPOOL_ROT_Y_DEG := 0.0
const DEFAULT_WHIRLPOOL_ROT_Z_DEG := 0.0
# Funnel MESH dimensions (base world-px, before each whirlpool's own size_mult) — 2026-08-09, on request: direct
# control instead of the old fixed WHIRL_FUNNEL_RADIUS_MULT/THROAT_FRAC/DEPTH_MULT ratios off a single radius.
const DEFAULT_WHIRLPOOL_MOUTH_RADIUS := 105.0    # wide top — also the particle ring/spray emission radius
const DEFAULT_WHIRLPOOL_THROAT_RADIUS := 13.0    # narrow bottom (drain)
const DEFAULT_WHIRLPOOL_HEIGHT_PX := 115.0       # total funnel depth (world Y) — NOT the same as "whirlpool_
                                                  # height" (that key is the particle Lifetime, in seconds)
const DEFAULT_WHIRLPOOL_PROFILE_EXP := 0.45      # radius(t)=throat+(mouth-throat)*(1-t)^exp — <1 stays flared
                                                  # near the mouth, pinching to the throat only near the very
                                                  # end (a real whirlpool's "wide bowl" shape); 1.0 = straight cone
const DEFAULT_WHIRLPOOL_HEIGHT := 1.8     # seconds aloft before a swirl cycle fades
const DEFAULT_WHIRLPOOL_MARK_REVEAL_PERCENT := 100.0
const DEFAULT_WHIRLPOOL_COLOR_0 := Color(0.75, 0.95, 1.0)    # bright foam-white
const DEFAULT_WHIRLPOOL_COLOR_1 := Color(0.35, 0.75, 0.90)   # mid teal
const DEFAULT_WHIRLPOOL_COLOR_2 := Color(0.10, 0.40, 0.65)   # deep blue
const DEFAULT_WHIRLPOOL_COLOR_3 := Color(0.90, 1.0, 1.0)     # white-hot foam crest
const DEFAULT_WHIRLPOOL_COLOR_4 := Color(0.25, 0.60, 0.80)   # steel-blue
const DEFAULT_WHIRLPOOL_COLOR_5 := Color(0.05, 0.25, 0.45)   # dark abyssal-blue
const DEFAULT_WHIRLPOOL_CRATER_MARKS: Array = []

## Marked vent positions — see atlantic_crater_mark.gd. Each entry: {"tex": int (0/1/2 = which maptile-set
## photo), "u": float, "v": float (normalized 0..1 position clicked on that photo)}. atlantic_clouds.gd
## replicates every entry at EVERY world-space repetition of that texture — see VolcanicClouds' own header
## for the full mechanic. `bubble_crater_marks`/`whirlpool_crater_marks` are independent lists.

## Marked landmark plume points — see atlantic_landmark_mark.gd / atlantic_temple_layer.gd. Each entry:
## {"fx": float, "fz": float} — normalized position within the (reused Electric) temple model's own
## bake-reference frame, NOT a world position.
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
		"water_distort_strength": DEFAULT_WATER_DISTORT_STRENGTH,
		"water_distort_speed": DEFAULT_WATER_DISTORT_SPEED,
		"water_sparkle_intensity": DEFAULT_WATER_SPARKLE_INTENSITY,
		"water_sparkle_color": DEFAULT_WATER_SPARKLE_COLOR,
		"water_sparkle_speed": DEFAULT_WATER_SPARKLE_SPEED,
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
		"bubble_opacity": DEFAULT_BUBBLE_OPACITY,
		"bubble_brightness": DEFAULT_BUBBLE_BRIGHTNESS,
		"bubble_density": DEFAULT_BUBBLE_DENSITY,
		"bubble_speed": DEFAULT_BUBBLE_SPEED,
		"bubble_height": DEFAULT_BUBBLE_HEIGHT,
		"bubble_mark_reveal_percent": DEFAULT_BUBBLE_MARK_REVEAL_PERCENT,
		"bubble_color_0": DEFAULT_BUBBLE_COLOR_0,
		"bubble_color_1": DEFAULT_BUBBLE_COLOR_1,
		"bubble_color_2": DEFAULT_BUBBLE_COLOR_2,
		"bubble_color_3": DEFAULT_BUBBLE_COLOR_3,
		"bubble_color_4": DEFAULT_BUBBLE_COLOR_4,
		"bubble_color_5": DEFAULT_BUBBLE_COLOR_5,
		"bubble_crater_marks": DEFAULT_BUBBLE_CRATER_MARKS.duplicate(),
		"whirlpool_opacity": DEFAULT_WHIRLPOOL_OPACITY,
		"whirlpool_brightness": DEFAULT_WHIRLPOOL_BRIGHTNESS,
		"whirlpool_density": DEFAULT_WHIRLPOOL_DENSITY,
		"whirlpool_speed": DEFAULT_WHIRLPOOL_SPEED,
		"whirlpool_size_min": DEFAULT_WHIRLPOOL_SIZE_MIN,
		"whirlpool_size_max": DEFAULT_WHIRLPOOL_SIZE_MAX,
		"whirlpool_rot_x_deg": DEFAULT_WHIRLPOOL_ROT_X_DEG,
		"whirlpool_rot_y_deg": DEFAULT_WHIRLPOOL_ROT_Y_DEG,
		"whirlpool_rot_z_deg": DEFAULT_WHIRLPOOL_ROT_Z_DEG,
		"whirlpool_mouth_radius": DEFAULT_WHIRLPOOL_MOUTH_RADIUS,
		"whirlpool_throat_radius": DEFAULT_WHIRLPOOL_THROAT_RADIUS,
		"whirlpool_height_px": DEFAULT_WHIRLPOOL_HEIGHT_PX,
		"whirlpool_profile_exp": DEFAULT_WHIRLPOOL_PROFILE_EXP,
		"whirlpool_height": DEFAULT_WHIRLPOOL_HEIGHT,
		"whirlpool_mark_reveal_percent": DEFAULT_WHIRLPOOL_MARK_REVEAL_PERCENT,
		"whirlpool_color_0": DEFAULT_WHIRLPOOL_COLOR_0,
		"whirlpool_color_1": DEFAULT_WHIRLPOOL_COLOR_1,
		"whirlpool_color_2": DEFAULT_WHIRLPOOL_COLOR_2,
		"whirlpool_color_3": DEFAULT_WHIRLPOOL_COLOR_3,
		"whirlpool_color_4": DEFAULT_WHIRLPOOL_COLOR_4,
		"whirlpool_color_5": DEFAULT_WHIRLPOOL_COLOR_5,
		"whirlpool_crater_marks": DEFAULT_WHIRLPOOL_CRATER_MARKS.duplicate(),
		"landmark_marks_bubble": DEFAULT_LANDMARK_MARKS.duplicate(),
		"landmark_marks_whirlpool": DEFAULT_LANDMARK_MARKS.duplicate(),
		"asset_settings": {},   # type_name -> {density, scale, blur}; missing type = default_asset_entry()
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
