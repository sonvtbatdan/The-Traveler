extends RefCounted
class_name AtlanticConfig
## Shared tunables for the Atlantic map's ground biome split. Both atlantic_ground.gdshader (GPU, paints the
## zone) and atlantic_trees.gd's biome check (once it has scatter assets) read the SAME frequency/threshold so
## asset placement agrees with the ground color underneath. Mirrors VolcanicConfig — see volcanic/
## volcanic_config.gd for the full rationale; only the numbers/theme differ where tuned for this map.
##
## Deep-sea sunken-city theme (2026-08-06, on request): the "river" concept becomes a CURRENT — a winding
## channel of pale, current-swept sand cutting through darker silt-covered ruin floor, instead of a lava flow.
## Same "extract a level-set from noise, perturb with a second higher-frequency field" trick either way.

const NOISE_FREQ := 0.0035        # world-space frequency fed into AtlanticNoise.fbm()
const BLUE_THRESHOLD := 0.5       # fbm() output above this = "dark silt" zone, below = "pale sand" zone
const BLEND_SOFTNESS := 0.06      # smoothstep half-width around the threshold (soft, blotchy edges)

## Current shape — same "extract a level-set from smooth noise" trick as the biome split above, but perturbed
## by a SECOND, higher-frequency cellular field so the channel's edge reads as an irregular current-scour line
## (drifted silt/rubble) instead of a perfectly smooth winding bank.
const RIVER_NOISE_FREQ := 0.001   # much lower than NOISE_FREQ -> a few big winding currents, not many blotches
const RIVER_LEVEL := 0.5          # which contour of the noise field becomes the current centerline

## Altitude model, single source of truth (world-px) — own constants so this map's systems never accidentally
## read Electric's/Volcanic's.
const TERRAIN_HEIGHT_PX := 0.0
const CLOUD_MIN_PX := 120.0
const CLOUD_MAX_PX := 130.0
const SHIP_HEIGHT_PX := 200.0
