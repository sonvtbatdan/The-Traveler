extends RefCounted
class_name ArcticConfig
## Shared tunables for the Arctic map's ground biome split. Both arctic_ground.gdshader (GPU, paints the zone)
## and arctic_trees.gd (CPU, decides which biome an asset scatter cell falls in) read the SAME frequency/
## threshold so asset placement agrees with the ground color underneath. If you retune one, retune both by
## changing here (shader still needs its own copies passed in as uniforms — see arctic_ground.gd/_make_material()).
##
## Values start identical to MechanicConfig's — this map is "tương tự map mechanic" (2026-08-19, on request),
## same terrain architecture, tune independently later via the Terrain Edit panel.

const NOISE_FREQ := 0.0035        # world-space frequency fed into ArcticNoise.fbm()
const BLUE_THRESHOLD := 0.5       # fbm() output above this = "blue" zone, below = "sand" zone
const BLEND_SOFTNESS := 0.06      # smoothstep half-width around the threshold (soft, blotchy edges)

## River shape: the river runs along the canopy-blend seam lines (arctic_ground.gdshader's river_dist,
## ArcticNoise.is_river()) — see MechanicConfig's own doc comment for the full history (3 redesigns before
## landing here). What's left to configure here is only the CORRIDOR gate — a much-lower-frequency field that
## restricts the seam-following river down to one long meandering path instead of the whole seam mesh (which
## includes small closed loops around local mottle extrema). Fixed/not exposed as a slider; both
## arctic_ground.gdshader (GPU) and ArcticNoise.is_river() (CPU) read the SAME values.
const RIVER_CORRIDOR_FREQ := 0.001        # world-space frequency
const RIVER_CORRIDOR_LEVEL := 0.5         # which contour becomes the corridor's centerline
const RIVER_CORRIDOR_HALF_WIDTH := 0.15   # must match arctic_ground.gdshader's RIVER_CORRIDOR_HALF_WIDTH

## Altitude model, single source of truth (world-px, not literal Blender-meter units):
##   terrain  = TERRAIN_HEIGHT_PX (ground + every scattered asset's own base)
##   clouds   = CLOUD_MIN_PX..CLOUD_MAX_PX band
##   ship/creep = SHIP_HEIGHT_PX (always above the cloud band)
const TERRAIN_HEIGHT_PX := 0.0
const CLOUD_MIN_PX := 120.0
const CLOUD_MAX_PX := 130.0
const SHIP_HEIGHT_PX := 200.0
