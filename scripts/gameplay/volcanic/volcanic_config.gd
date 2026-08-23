extends RefCounted
class_name VolcanicConfig
## Shared tunables for the Volcanic map's ground biome split. Both volcanic_ground.gdshader (GPU, paints the
## zone) and (a future) volcanic_trees.gd biome check read the SAME frequency/threshold so asset placement
## agrees with the ground color underneath. Mirrors ElectricConfig — see electric/electric_config.gd for the
## full rationale; only the numbers differ where tuned for this map.

const NOISE_FREQ := 0.0035        # world-space frequency fed into VolcanicNoise.fbm()
const BLUE_THRESHOLD := 0.5       # fbm() output above this = "dark basalt" zone, below = "ash" zone
const BLEND_SOFTNESS := 0.06      # smoothstep half-width around the threshold (soft, blotchy edges)

## River shape (here: the lava flow) — same "extract a level-set from smooth noise" trick as the biome split
## above, but VolcanicNoise bakes this field with CELLULAR/Voronoi noise instead of simplex (see that file's
## header) so the lava/rock contour reads as jagged cracked-crust facets instead of Electric's smooth winding
## river banks — the one deliberate visual departure from Electric requested for this map.
const RIVER_NOISE_FREQ := 0.001   # much lower than NOISE_FREQ -> a few big winding lava flows, not many blotches
const RIVER_LEVEL := 0.5          # which contour of the noise field becomes the lava flow centerline

## Altitude model, single source of truth (world-px) — see ElectricConfig for the full rationale; same values,
## own constants so this map's systems never accidentally read Electric's.
const TERRAIN_HEIGHT_PX := 0.0
const CLOUD_MIN_PX := 120.0
const CLOUD_MAX_PX := 130.0
const SHIP_HEIGHT_PX := 200.0
