extends RefCounted
class_name MechanicConfig
## Shared tunables for the Mechanic map's ground biome split. Both mechanic_ground.gdshader (GPU, paints the
## zone) and mechanic_trees.gd (CPU, decides which biome an asset scatter cell falls in) read the SAME
## frequency/threshold so asset placement agrees with the ground color underneath. If you retune one,
## retune both by changing here (shader still needs its own copies passed in as uniforms — see
## mechanic_ground.gd/_make_material()).
##
## Values start identical to ElectricConfig's — "kết cấu ban đầu giống electric" (initial structure like
## Electric), on request — tune independently later via the Terrain Edit panel.

const NOISE_FREQ := 0.0035        # world-space frequency fed into MechanicNoise.fbm()
const BLUE_THRESHOLD := 0.5       # fbm() output above this = "blue" zone, below = "sand" zone
const BLEND_SOFTNESS := 0.06      # smoothstep half-width around the threshold (soft, blotchy edges)

## River shape (2026-08-19, 2 redesigns): the river itself now runs along the SAME 6 canopy-blend seam lines
## as the mottle-based region split above (mechanic_ground.gdshader's river_dist, MechanicNoise.is_river()).
## What's left to configure here is only the CORRIDOR gate — a much-lower-frequency field that restricts the
## seam-following river down to one long meandering path instead of the whole seam mesh (which includes small
## closed loops around local mottle extrema — "sai quy tắc river trong thực tế"). Fixed/not exposed as a
## slider; both mechanic_ground.gdshader (GPU) and MechanicNoise.is_river() (CPU) read the SAME values.
const RIVER_CORRIDOR_FREQ := 0.001        # world-space frequency — mechanic_ground.gdshader's tex_river @
                                           # RIVER_TILE_CYCLES=4 baked then sampled at UV_SCALE=1/4000 is
                                           # equivalent to this raw frequency (no baked-texture indirection
                                           # needed on the CPU side)
const RIVER_CORRIDOR_LEVEL := 0.5         # which contour becomes the corridor's centerline — must match
                                           # mechanic_ground.gdshader's RIVER_CORRIDOR_LEVEL
const RIVER_CORRIDOR_HALF_WIDTH := 0.15   # must match mechanic_ground.gdshader's RIVER_CORRIDOR_HALF_WIDTH

## Altitude model, single source of truth (world-px, not literal Blender-meter units):
##   terrain  = TERRAIN_HEIGHT_PX (ground + every scattered asset's own base)
##   clouds   = CLOUD_MIN_PX..CLOUD_MAX_PX band
##   ship/creep = SHIP_HEIGHT_PX (always above the cloud band)
const TERRAIN_HEIGHT_PX := 0.0
const CLOUD_MIN_PX := 120.0
const CLOUD_MAX_PX := 130.0
const SHIP_HEIGHT_PX := 200.0
