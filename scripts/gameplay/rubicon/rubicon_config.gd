extends RefCounted
class_name RubiconConfig
## Shared tunables for the Rubicon map's ground biome split. Both rubicon_ground.gdshader (GPU, paints the
## zone) and rubicon_trees.gd (CPU, decides which biome an asset scatter cell falls in) read the SAME
## frequency/threshold so asset placement agrees with the ground color underneath. If you retune one,
## retune both by changing here (shader still needs its own copies passed in as uniforms — see
## rubicon_ground.gd/_make_material()).

const NOISE_FREQ := 0.0035        # world-space frequency fed into RubiconNoise.fbm()
const BLUE_THRESHOLD := 0.5       # fbm() output above this = "blue" zone, below = "sand" zone
const BLEND_SOFTNESS := 0.06      # smoothstep half-width around the threshold (soft, blotchy edges)

## River shape: a single low-frequency noise field's near-RIVER_LEVEL contour forms winding "river" bands —
## same "extract a level-set from smooth noise" trick as the biome split above, just at a much lower
## frequency (a handful of big winding lines instead of many blotches) and with an ADJUSTABLE half-width
## (river_width, exposed in the Terrain Edit panel / RubiconTerrainSettings) instead of a fixed one, so
## thicker width = more of the map counts as river. Both rubicon_ground.gdshader (GPU paint) and
## rubicon_trees.gd (CPU spawn-avoidance) read this same frequency/level so rivers and "no assets on rivers"
## agree with each other, same as the biome split above.
const RIVER_NOISE_FREQ := 0.001   # much lower than NOISE_FREQ -> a few big winding rivers, not many blotches
                                  # (matches rubicon_ground.gd's baked tex_river: RIVER_TILE_CYCLES/river tile size)
const RIVER_LEVEL := 0.5          # which contour of the noise field becomes the river centerline

## Altitude model, single source of truth (world-px, not literal Blender-meter units):
##   terrain  = TERRAIN_HEIGHT_PX (ground + every scattered asset's own base)
##   clouds   = CLOUD_MIN_PX..CLOUD_MAX_PX band
##   ship/creep = SHIP_HEIGHT_PX (always above the cloud band — they're a separate 2D layer drawn on top of
##                the whole Rubicon background, so this is structural, not a per-frame height check)
## rubicon_trees.gd's per-instance "above/below cloud" split compares each instance's effective rendered
## height against CLOUD_MAX_PX (the top of the band) — see its CLOUD_ALTITUDE_PX const.
const TERRAIN_HEIGHT_PX := 0.0
const CLOUD_MIN_PX := 120.0
const CLOUD_MAX_PX := 130.0
const SHIP_HEIGHT_PX := 200.0
