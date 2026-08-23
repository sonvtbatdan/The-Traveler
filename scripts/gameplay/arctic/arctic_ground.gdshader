shader_type canvas_item;

// Icy blue-white / frost ground for the Arctic map — ported from mechanic_ground.gdshader (same baked-noise-
// texture technique, same fragment() structure — see that file's header for the full rationale). Screen-
// filling rect (arctic_ground.gd), world_offset uniform makes the pattern scroll continuously with the player
// instead of the rect itself moving. Noise is BAKED into seamless textures at load time (FastNoiseLite/
// NoiseTexture2D, script side) — this shader only SAMPLES + tiles them via repeat wrap.
//
// ONE deliberate difference from mechanic_ground.gdshader (2026-08-19, on request — "hệ thống blend dynamic
// tự động phát hiện và blend dựa trên số ảnh có trong folder"): Mechanic hardcodes a 7-way blend (6 fixed
// thresholds, 7 fixed texture uniforms) because it always ships exactly 7 canopy photos meant to be used
// together. Arctic's canopy set size is NOT fixed — currently 4 photos, more may be dropped in later — so
// this shader instead reserves MAX_CANOPY (10) uniform slots and a `canopy_count` uniform (set from
// ArcticAssetScan.canopy_count() on the CPU side, arctic_ground.gd's apply_canopy_images()) that gates how
// many of those 10 slots actually participate in the blend chain each frame:
//   - each threshold t_k is computed at k/canopy_count (not a fixed k/7) — so however many photos are active,
//     the transitions land evenly spaced across the full 0..1 mottle range;
//   - a slot beyond canopy_count (k >= canopy_count) has its threshold hard-zeroed instead of computed at all
//     — mix(prev, canopy_k, 0.0) is an exact no-op, so an unused slot (which may hold stale/default texture
//     data) never contributes any color, regardless of what's bound there.
// Adding a 5th, 6th... photo later needs NO shader change up to MAX_CANOPY=10 — just drop the file into
// assets/map/arctic/maptile/default/ and reopen the map (or the Terrain Edit panel's Tile Set dropdown).
// Raise MAX_CANOPY (+ add matching uniform slots + one more unrolled threshold/mix step) only if the map ever
// needs more than 10 photos blended at once.
//
// River: same seam-following + low-frequency CORRIDOR-gate technique as Mechanic's own 5th (final) redesign —
// see mechanic_ground.gdshader's header for the full blow-by-blow. Runs along `river_count` of the
// (canopy_count - 1) live seam lines, using the SAME mottle sample the canopy split already computed —
// guaranteed pixel-perfect alignment, not an independent field that happens to cross near a seam.
//
// No landmark ring/patch system — Arctic has no landmark ring/patch yet (mirrors mechanic_ground.gdshader's
// same omission); port the block back from electric_ground.gdshader once one exists.

uniform sampler2D tex_zone : repeat_enable, filter_linear;     // blue-vs-white split (low frequency, big blotches)
uniform sampler2D tex_mottle : repeat_enable, filter_linear;   // canopy region-split field — see header; its
                                                                 // world-scale is mottle_uv_scale below (the
                                                                 // "Canopy Blend Sparseness" slider), NOT baked
                                                                 // fixed, so sparseness is live-tunable
uniform sampler2D tex_river : repeat_enable, filter_linear;    // river CORRIDOR gate (very low frequency) —
                                                                 // NOT the river shape itself, just where along
                                                                 // the seam network a river is allowed at all

// MAX_CANOPY = 10 fixed slots — see header. Only the first `canopy_count` are ever selected.
uniform sampler2D tex_canopy_0 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_1 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_2 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_3 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_4 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_5 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_6 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_7 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_8 : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_9 : repeat_enable, filter_linear_mipmap;   // real top-down canopy photos, each
uniform sampler2D tex_canopy_0_normal : repeat_enable, filter_linear_mipmap;   // sampled at its own UV scale/
uniform sampler2D tex_canopy_1_normal : repeat_enable, filter_linear_mipmap;   // offset — see fragment() below.
uniform sampler2D tex_canopy_2_normal : repeat_enable, filter_linear_mipmap;   // Normal maps are tools/
uniform sampler2D tex_canopy_3_normal : repeat_enable, filter_linear_mipmap;   // generate_canopy_normal.py
uniform sampler2D tex_canopy_4_normal : repeat_enable, filter_linear_mipmap;   // output, same convention as
uniform sampler2D tex_canopy_5_normal : repeat_enable, filter_linear_mipmap;   // Electric/Mechanic.
uniform sampler2D tex_canopy_6_normal : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_7_normal : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_8_normal : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_9_normal : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_water_wave : repeat_enable, filter_linear_mipmap;   // genuinely seamless wave-crest photo

uniform int canopy_count = 4;   // how many of the 10 slots above are actually active — see header

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);
uniform float zone_uv_scale = 0.0035;
uniform float mottle_uv_scale = 0.0003125;   // world px -> tex_mottle UV — Terrain Edit panel's "Canopy Blend
                                              // Sparseness"; bigger = transitions farther apart = more of any
                                              // one photo shows intact between them
uniform float canopy_uv_scale = 0.000625;   // world px -> each photo's OWN internal tiling scale (unrelated
                                             // to mottle_uv_scale above)
uniform float canopy_tint_strength = 0.5;
uniform float blend_softness = 0.06;
uniform float canopy_blend_width = 0.04;   // smoothstep half-width (mottle-value space) around each region
                                            // threshold — Terrain Edit panel's "Canopy Blend Width". Keep this
                                            // NARROW; sparseness (mottle_uv_scale above) is the real "less
                                            // shattered" knob, not widening this past band width.

// Real per-pixel directional lighting against tex_canopy_*_normal — see electric_ground.gdshader's header for
// the full rationale (self-contained Lambert + Blinn-Phong, tunable live via the Light Edit panel's
// arctic_ground.gd/apply_canopy_lighting).
uniform vec3 canopy_light_dir = vec3(0.6, 0.6, 0.6);
uniform vec4 canopy_light_color : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform float canopy_ambient = 0.5;
uniform float canopy_contrast = 1.0;
uniform float canopy_specular_strength = 0.35;
uniform float canopy_specular_power = 18.0;
uniform float blue_threshold = 0.5;
uniform vec4 col_blue_light : source_color = vec4(0.55, 0.75, 0.92, 1.0);
uniform vec4 col_sand_light : source_color = vec4(0.85, 0.90, 0.95, 1.0);

uniform int river_count = 3;   // 0..(canopy_count-1) — how many of the live canopy-blend seam lines carry a
                                // river ("River Count"); 0 = no rivers at all. See this file's header.
const float RIVER_UV_SCALE = 0.00025;          // world px -> tex_river UV — fixed, not exposed; a slow-
                                                // changing field so the corridor forms one long meander
const float RIVER_CORRIDOR_LEVEL = 0.5;        // which contour of tex_river becomes the corridor's centerline
const float RIVER_CORRIDOR_HALF_WIDTH = 0.15;  // half-width (tex_river value-space) of that corridor band
uniform float river_width = 0.035;   // half-width of the river band, in mottle-value space (0 = no rivers)
uniform vec4 river_color_dark : source_color = vec4(0.10, 0.28, 0.40, 1.0);
uniform vec4 river_color_light : source_color = vec4(0.25, 0.55, 0.72, 1.0);
uniform vec4 river_bank_color : source_color = vec4(0.90, 0.93, 0.97, 1.0);   // pale icy sand/frost bank
uniform float river_bank_width = 0.022;   // extra noise-value half-width beyond river_width the bank extends
uniform float water_wave_uv_scale = 0.00385;
uniform float water_wave_speed = 26.0;

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;
	float n = texture(tex_zone, world_pos * zone_uv_scale).r;
	float zone = smoothstep(blue_threshold - blend_softness, blue_threshold + blend_softness, n);

	// Canopy region split — see header. Each texture sampled at its own scale/offset (must match
	// ArcticNoise.GROUND_UV_MULT/OFFSET exactly) so none of their individually non-seamless tiling seams
	// line up with each other.
	float mottle = texture(tex_mottle, world_pos * mottle_uv_scale).r;
	vec2 uv_0 = world_pos * canopy_uv_scale;
	vec2 uv_1 = world_pos * canopy_uv_scale * 1.18 + vec2(311.0, -173.0);
	vec2 uv_2 = world_pos * canopy_uv_scale * 0.87 + vec2(-197.0, 421.0);
	vec2 uv_3 = world_pos * canopy_uv_scale * 1.32 + vec2(157.0, 289.0);
	vec2 uv_4 = world_pos * canopy_uv_scale * 0.79 + vec2(-421.0, -89.0);
	vec2 uv_5 = world_pos * canopy_uv_scale * 1.24 + vec2(233.0, -311.0);
	vec2 uv_6 = world_pos * canopy_uv_scale * 0.72 + vec2(-113.0, 197.0);
	vec2 uv_7 = world_pos * canopy_uv_scale * 1.41 + vec2(389.0, 101.0);
	vec2 uv_8 = world_pos * canopy_uv_scale * 0.65 + vec2(-271.0, -347.0);
	vec2 uv_9 = world_pos * canopy_uv_scale * 1.09 + vec2(97.0, -433.0);
	vec3 canopy_0 = texture(tex_canopy_0, uv_0).rgb;
	vec3 canopy_1 = texture(tex_canopy_1, uv_1).rgb;
	vec3 canopy_2 = texture(tex_canopy_2, uv_2).rgb;
	vec3 canopy_3 = texture(tex_canopy_3, uv_3).rgb;
	vec3 canopy_4 = texture(tex_canopy_4, uv_4).rgb;
	vec3 canopy_5 = texture(tex_canopy_5, uv_5).rgb;
	vec3 canopy_6 = texture(tex_canopy_6, uv_6).rgb;
	vec3 canopy_7 = texture(tex_canopy_7, uv_7).rgb;
	vec3 canopy_8 = texture(tex_canopy_8, uv_8).rgb;
	vec3 canopy_9 = texture(tex_canopy_9, uv_9).rgb;

	vec3 nrm_0 = texture(tex_canopy_0_normal, uv_0).rgb * 2.0 - 1.0;
	vec3 nrm_1 = texture(tex_canopy_1_normal, uv_1).rgb * 2.0 - 1.0;
	vec3 nrm_2 = texture(tex_canopy_2_normal, uv_2).rgb * 2.0 - 1.0;
	vec3 nrm_3 = texture(tex_canopy_3_normal, uv_3).rgb * 2.0 - 1.0;
	vec3 nrm_4 = texture(tex_canopy_4_normal, uv_4).rgb * 2.0 - 1.0;
	vec3 nrm_5 = texture(tex_canopy_5_normal, uv_5).rgb * 2.0 - 1.0;
	vec3 nrm_6 = texture(tex_canopy_6_normal, uv_6).rgb * 2.0 - 1.0;
	vec3 nrm_7 = texture(tex_canopy_7_normal, uv_7).rgb * 2.0 - 1.0;
	vec3 nrm_8 = texture(tex_canopy_8_normal, uv_8).rgb * 2.0 - 1.0;
	vec3 nrm_9 = texture(tex_canopy_9_normal, uv_9).rgb * 2.0 - 1.0;

	// 9 thresholds at k/canopy_count (k=1..9), each a narrow smoothstep band (canopy_blend_width) chained
	// through nested mix() — see header. A slot beyond canopy_count (k >= canopy_count) gets its threshold
	// hard-zeroed instead of computed, making that mix step an exact no-op regardless of what garbage/default
	// texture data sits in that unused uniform slot.
	float cc = float(canopy_count);
	float t1 = (canopy_count > 1) ? smoothstep(1.0 / cc - canopy_blend_width, 1.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t2 = (canopy_count > 2) ? smoothstep(2.0 / cc - canopy_blend_width, 2.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t3 = (canopy_count > 3) ? smoothstep(3.0 / cc - canopy_blend_width, 3.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t4 = (canopy_count > 4) ? smoothstep(4.0 / cc - canopy_blend_width, 4.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t5 = (canopy_count > 5) ? smoothstep(5.0 / cc - canopy_blend_width, 5.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t6 = (canopy_count > 6) ? smoothstep(6.0 / cc - canopy_blend_width, 6.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t7 = (canopy_count > 7) ? smoothstep(7.0 / cc - canopy_blend_width, 7.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t8 = (canopy_count > 8) ? smoothstep(8.0 / cc - canopy_blend_width, 8.0 / cc + canopy_blend_width, mottle) : 0.0;
	float t9 = (canopy_count > 9) ? smoothstep(9.0 / cc - canopy_blend_width, 9.0 / cc + canopy_blend_width, mottle) : 0.0;
	vec3 canopy_col = mix(mix(mix(mix(mix(mix(mix(mix(mix(canopy_0, canopy_1, t1), canopy_2, t2), canopy_3, t3), canopy_4, t4), canopy_5, t5), canopy_6, t6), canopy_7, t7), canopy_8, t8), canopy_9, t9);
	vec3 canopy_nrm = normalize(mix(mix(mix(mix(mix(mix(mix(mix(mix(nrm_0, nrm_1, t1), nrm_2, t2), nrm_3, t3), nrm_4, t4), nrm_5, t5), nrm_6, t6), nrm_7, t7), nrm_8, t8), nrm_9, t9));

	vec3 zone_tint = mix(col_sand_light.rgb, col_blue_light.rgb, zone);
	vec4 ground_col = vec4(mix(canopy_col, canopy_col * zone_tint * 2.0, canopy_tint_strength), 1.0);

	vec3 light_dir = normalize(canopy_light_dir);
	float ndotl = max(dot(canopy_nrm, light_dir), 0.0);
	float diffuse = canopy_ambient + (1.0 - canopy_ambient) * ndotl;
	diffuse = clamp((diffuse - 0.5) * canopy_contrast + 0.5, 0.0, 2.5);
	vec3 light_tint = mix(vec3(1.0), canopy_light_color.rgb, ndotl);
	vec3 half_vec = normalize(light_dir + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(canopy_nrm, half_vec), 0.0), canopy_specular_power) * canopy_specular_strength;
	ground_col.rgb = ground_col.rgb * diffuse * light_tint + canopy_light_color.rgb * spec;

	// River: runs along `river_count` of the live canopy-blend seam lines — reuses `mottle` (already sampled
	// above), so the river tracks the texture transition exactly. Seams beyond canopy_count - 1 don't exist,
	// so they're gated the same way the blend thresholds above are.
	float river_dist = 999.0;
	if (river_count >= 1 && canopy_count > 1) river_dist = min(river_dist, abs(mottle - 1.0 / cc));
	if (river_count >= 2 && canopy_count > 2) river_dist = min(river_dist, abs(mottle - 2.0 / cc));
	if (river_count >= 3 && canopy_count > 3) river_dist = min(river_dist, abs(mottle - 3.0 / cc));
	if (river_count >= 4 && canopy_count > 4) river_dist = min(river_dist, abs(mottle - 4.0 / cc));
	if (river_count >= 5 && canopy_count > 5) river_dist = min(river_dist, abs(mottle - 5.0 / cc));
	if (river_count >= 6 && canopy_count > 6) river_dist = min(river_dist, abs(mottle - 6.0 / cc));
	if (river_count >= 7 && canopy_count > 7) river_dist = min(river_dist, abs(mottle - 7.0 / cc));
	if (river_count >= 8 && canopy_count > 8) river_dist = min(river_dist, abs(mottle - 8.0 / cc));
	if (river_count >= 9 && canopy_count > 9) river_dist = min(river_dist, abs(mottle - 9.0 / cc));

	// Corridor gate — restricts the seam network down to one long meandering path, so a closed loop elsewhere
	// in the seam mesh (around a local mottle extremum) doesn't render as a river.
	float rv = texture(tex_river, world_pos * RIVER_UV_SCALE).r;
	float corridor = 1.0 - smoothstep(RIVER_CORRIDOR_HALF_WIDTH * 0.7, RIVER_CORRIDOR_HALF_WIDTH, abs(rv - RIVER_CORRIDOR_LEVEL));
	float river_mask = (1.0 - smoothstep(river_width * 0.6, river_width, river_dist)) * corridor;

	vec2 wave_dir_a = vec2(0.85, 0.53);
	vec2 wave_dir_b = vec2(-0.40, 0.92);
	vec2 wave_uv_a = world_pos * water_wave_uv_scale + wave_dir_a * TIME * water_wave_speed * water_wave_uv_scale;
	vec2 wave_uv_b = world_pos * water_wave_uv_scale * 1.7 - wave_dir_b * TIME * water_wave_speed * 0.6 * water_wave_uv_scale;
	float wave_a = texture(tex_water_wave, wave_uv_a).r;
	float wave_b = texture(tex_water_wave, wave_uv_b).r;
	float wave_mix = clamp(wave_a * 0.65 + wave_b * 0.5, 0.0, 1.0);
	vec3 water_rgb = mix(river_color_dark.rgb, river_color_light.rgb, wave_mix);
	water_rgb += vec3(pow(wave_mix, 5.0) * 0.4);

	vec3 foam_tint = river_bank_color.rgb;
	float shore_dist = abs(river_dist - river_width * 0.88);
	float foam_band = 1.0 - smoothstep(0.0, river_width * 0.16, shore_dist);
	water_rgb = mix(water_rgb, foam_tint, foam_band * (0.35 + 0.5 * wave_a));
	vec4 water_col = vec4(water_rgb, 1.0);

	// Icy sand/frost fringe between canopy and water — bank_mask is 1 all the way from the river center out
	// to river_width and fades to 0 by river_width + river_bank_width, so the only place it actually SHOWS is
	// that outer ring: canopy fades to frost, frost fades to water, instead of canopy running straight into
	// the riverbed. Corridor-gated too.
	float bank_mask = (1.0 - smoothstep(river_width, river_width + river_bank_width, river_dist)) * corridor;
	vec4 banked_col = mix(ground_col, river_bank_color, bank_mask);

	COLOR = mix(banked_col, water_col, river_mask);
}
