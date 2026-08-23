shader_type canvas_item;

// Blue-grass / dark-sand blotchy ground for the Mechanic map — ported from electric_ground.gdshader (same
// baked-noise-texture technique, same fragment() structure). Screen-filling rect (mechanic_ground.gd),
// world_offset uniform makes the pattern scroll continuously with the player instead of the rect itself
// moving. Noise is BAKED into seamless textures at load time (FastNoiseLite/NoiseTexture2D, script side) —
// this shader only SAMPLES + tiles them via repeat wrap.
//
// Two deliberate differences from electric_ground.gdshader:
//  1. SEVEN canopy photos blended (not Electric's 3-of-N swappable set) — Mechanic's assets/map/mechanic/
//     maptile/default/ ships 7 photos meant to be used together, per request ("dùng cả 7 ảnh random đặt xen
//     kẽ"). Same TECHNIQUE as Electric: tex_mottle's continuous noise field is split into N equal thresholds
//     (Electric: 2 thresholds/3 textures; here: 6 thresholds/7 textures), each threshold crossing a narrow
//     smoothstep band, chained through nested mix() exactly like electric_ground.gdshader's t_ab/t_bc.
//     2026-08-19, 3rd pass ("chuyển lại phương pháp blend canopy cũ... giống Electric... nhưng dùng vân blend
//     thưa hơn"): an intermediate 2nd pass replaced this with Voronoi cell tiling (no blending at all) to
//     kill a "shattered/vein" look — reverted per request back to Electric's actual blending technique, this
//     time with mottle_uv_scale exposed as a LIVE "Canopy Blend Sparseness" slider (mechanic_ground.gd's
//     apply_canopy_mottle_scale) instead of a fixed baked frequency, so how far apart the 6 transitions land
//     — and therefore how much of any one photo shows intact between them — is directly tunable.
//  2. No landmark ring/patch system — Mechanic has no landmark .glb yet (mirrors volcanic_ground.gdshader's
//     same omission for the same reason); port the block back from electric_ground.gdshader once one exists.
//
// River (2026-08-19, 3rd redesign): REVERTED to a verbatim copy of electric_ground.gdshader's river technique
// — a single low-frequency tex_river contour, smoothstepped around river_level — on request ("River: ...
// phần code river copy lại của electric thay vào river hiện tại của mechanic"). This replaced BOTH of an
// intermediate pass's additions: the branching crack/vein network (tex_river_cell, Worley F2-F1 thresholding —
// "đường đứt gãy... nhánh rẽ như tia sét, rễ cây", 2026-08-18) and the screen-space "energy pulse" sweeps that
// traveled across it. Neither survives here; see this file's git history for that implementation if it's
// ever wanted back.
//
// River (2026-08-19, 4th redesign — SAME DAY): that Electric-style river used its OWN independent low-freq
// field (tex_river), which crosses canopy photo boundaries at essentially random angles — "đang bị cắt qua
// các texture nên khá xấu" (cuts across the textures, looks ugly). Replaced tex_river entirely: the river now
// runs exactly ALONG `river_count` of the SAME 6 canopy-blend seam lines (the mottle field's k/7 crossings
// already used for the 7-way canopy split above), by reusing that EXACT mottle sample — guaranteed pixel-
// perfect alignment, not just "close" — instead of an independent field that happened to wander near a seam
// sometimes. `river_count` (0..6, Terrain Edit panel's "River Count") picks how many of the 6 seams actually
// carry a river; 0 = none, 6 = every seam.
//
// River (2026-08-19, 5th redesign — SAME DAY): the seam field alone is unconstrained smooth 2D noise, so its
// level-sets aren't just long winding lines — they also form small CLOSED LOOPS around local mottle
// extrema, same as any topographic contour map does. On request ("river phải dài... vòng tròn... sai quy
// tắc river trong thực tế" — rivers must be long, a closed loop is unrealistic), tex_river is back, but in a
// completely different ROLE than the 4th redesign: not "IS the river" any more, just a much-lower-frequency
// CORRIDOR gate — a wide soft band (RIVER_CORRIDOR_HALF_WIDTH, fixed/not exposed) that the seam-following
// mask above is multiplied by. Only the sections of the seam network that happen to fall inside this slow-
// changing corridor actually render as water, which reads as one (or a few) long meandering path(s) instead
// of the ENTIRE seam mesh with its closed loops. MechanicNoise.is_river() (CPU-side river-avoidance for
// trees/plumes) mirrors both the seam AND corridor checks — see its own header.

uniform sampler2D tex_zone : repeat_enable, filter_linear;     // blue-vs-sand split (low frequency, big blotches)
uniform sampler2D tex_mottle : repeat_enable, filter_linear;   // canopy region-split field — see header; its
                                                                 // world-scale is mottle_uv_scale below (the
                                                                 // "Canopy Blend Sparseness" slider), NOT baked
                                                                 // fixed, so sparseness is live-tunable
uniform sampler2D tex_river : repeat_enable, filter_linear;    // river CORRIDOR gate (very low frequency) —
                                                                 // see header's 5th redesign; NOT the river
                                                                 // shape itself, just where along the seam
                                                                 // network a river is allowed to appear at all
uniform sampler2D tex_canopy_a : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_b : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_c : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_d : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_e : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_f : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_canopy_g : repeat_enable, filter_linear_mipmap;   // real top-down canopy photos, each
uniform sampler2D tex_canopy_a_normal : repeat_enable, filter_linear_mipmap;   // sampled at its own UV scale/
uniform sampler2D tex_canopy_b_normal : repeat_enable, filter_linear_mipmap;   // offset — see fragment()
uniform sampler2D tex_canopy_c_normal : repeat_enable, filter_linear_mipmap;   // below. Normal maps are
uniform sampler2D tex_canopy_d_normal : repeat_enable, filter_linear_mipmap;   // tools/generate_canopy_
uniform sampler2D tex_canopy_e_normal : repeat_enable, filter_linear_mipmap;   // normal.py output, same
uniform sampler2D tex_canopy_f_normal : repeat_enable, filter_linear_mipmap;   // convention as Electric.
uniform sampler2D tex_canopy_g_normal : repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_water_wave : repeat_enable, filter_linear_mipmap;   // genuinely seamless wave-crest photo

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);
uniform float zone_uv_scale = 0.0035;
uniform float mottle_uv_scale = 0.0003125;   // world px -> tex_mottle UV (1/3200 default — Terrain Edit
                                              // panel's "Canopy Blend Sparseness"; bigger = transitions farther
                                              // apart = more of any one photo shows intact between them)
uniform float canopy_uv_scale = 0.000625;   // world px -> each photo's OWN internal tiling scale (unrelated
                                             // to mottle_uv_scale above — how big that photo's own leaf detail
                                             // reads within whichever region it's currently occupying)
uniform float canopy_tint_strength = 0.5;
uniform float blend_softness = 0.06;
uniform float canopy_blend_width = 0.04;   // smoothstep half-width (mottle-value space) around each of the 6
                                            // region thresholds — Terrain Edit panel's "Canopy Blend Width".
                                            // Kept NARROW (mirrors Electric's own 0.04) — nested mix() only
                                            // reads as a clean blend for narrow, mostly non-overlapping bands;
                                            // sparseness (mottle_uv_scale above) is the real "less shattered"
                                            // knob, not widening this past band width.

// Real per-pixel directional lighting against tex_canopy_*_normal — see electric_ground.gdshader's header
// for the full rationale (self-contained Lambert + Blinn-Phong, tunable live via the Light Edit panel's
// mechanic_ground.gd/apply_canopy_lighting).
uniform vec3 canopy_light_dir = vec3(0.6, 0.6, 0.6);
uniform vec4 canopy_light_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float canopy_ambient = 0.45;
uniform float canopy_contrast = 1.0;
uniform float canopy_specular_strength = 0.3;
uniform float canopy_specular_power = 18.0;
uniform float blue_threshold = 0.5;
uniform vec4 col_blue_light : source_color = vec4(0.30, 0.56, 0.90, 1.0);
uniform vec4 col_sand_light : source_color = vec4(0.46, 0.36, 0.15, 1.0);

uniform int river_count = 3;   // 0..6 — how many of the 7-way canopy blend's seam lines carry a river ("River
                                // Count"); 0 = no rivers at all, 6 = every seam. See this file's header.
const float RIVER_UV_SCALE = 0.00025;          // world px -> tex_river UV (1/4000) — fixed, not exposed; a
                                                // slow-changing field so the corridor forms one long meander
                                                // across a wide area rather than crossing itself many times
const float RIVER_CORRIDOR_LEVEL = 0.5;        // which contour of tex_river becomes the corridor's centerline
const float RIVER_CORRIDOR_HALF_WIDTH = 0.15;  // half-width (tex_river value-space) of that corridor band
uniform float river_width = 0.035;   // half-width of the river band, in mottle-value space (0 = no rivers)
uniform vec4 river_color_dark : source_color = vec4(0.05, 0.18, 0.35, 1.0);
uniform vec4 river_color_light : source_color = vec4(0.15, 0.45, 0.65, 1.0);
uniform vec4 river_bank_color : source_color = vec4(0.87, 0.74, 0.40, 1.0);   // golden riverbank sand
uniform float river_bank_width = 0.022;   // extra noise-value half-width beyond river_width the bank extends
uniform float water_wave_uv_scale = 0.00385;
uniform float water_wave_speed = 26.0;

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;
	float n = texture(tex_zone, world_pos * zone_uv_scale).r;
	float zone = smoothstep(blue_threshold - blend_softness, blue_threshold + blend_softness, n);

	// 7-way canopy region split — Electric's own technique (electric_ground.gdshader's t_ab/t_bc), just
	// extended from 2 thresholds/3 textures to 6 thresholds/7 textures. Each texture sampled at its own
	// scale/offset so none of their individually non-seamless tiling seams line up with each other.
	float mottle = texture(tex_mottle, world_pos * mottle_uv_scale).r;
	vec2 uv_a = world_pos * canopy_uv_scale;
	vec2 uv_b = world_pos * canopy_uv_scale * 1.18 + vec2(311.0, -173.0);
	vec2 uv_c = world_pos * canopy_uv_scale * 0.87 + vec2(-197.0, 421.0);
	vec2 uv_d = world_pos * canopy_uv_scale * 1.32 + vec2(157.0, 289.0);
	vec2 uv_e = world_pos * canopy_uv_scale * 0.79 + vec2(-421.0, -89.0);
	vec2 uv_f = world_pos * canopy_uv_scale * 1.24 + vec2(233.0, -311.0);
	vec2 uv_g = world_pos * canopy_uv_scale * 0.72 + vec2(-113.0, 197.0);
	vec3 canopy_a = texture(tex_canopy_a, uv_a).rgb;
	vec3 canopy_b = texture(tex_canopy_b, uv_b).rgb;
	vec3 canopy_c = texture(tex_canopy_c, uv_c).rgb;
	vec3 canopy_d = texture(tex_canopy_d, uv_d).rgb;
	vec3 canopy_e = texture(tex_canopy_e, uv_e).rgb;
	vec3 canopy_f = texture(tex_canopy_f, uv_f).rgb;
	vec3 canopy_g = texture(tex_canopy_g, uv_g).rgb;

	vec3 nrm_a = texture(tex_canopy_a_normal, uv_a).rgb * 2.0 - 1.0;
	vec3 nrm_b = texture(tex_canopy_b_normal, uv_b).rgb * 2.0 - 1.0;
	vec3 nrm_c = texture(tex_canopy_c_normal, uv_c).rgb * 2.0 - 1.0;
	vec3 nrm_d = texture(tex_canopy_d_normal, uv_d).rgb * 2.0 - 1.0;
	vec3 nrm_e = texture(tex_canopy_e_normal, uv_e).rgb * 2.0 - 1.0;
	vec3 nrm_f = texture(tex_canopy_f_normal, uv_f).rgb * 2.0 - 1.0;
	vec3 nrm_g = texture(tex_canopy_g_normal, uv_g).rgb * 2.0 - 1.0;

	// 6 thresholds at k/7 (k=1..6), each a narrow smoothstep band (canopy_blend_width) exactly like Electric's
	// t_ab/t_bc — chained through nested mix() so each region is mostly pure, blending only right at a
	// crossing. mottle_uv_scale (the "sparseness" slider) controls how far apart these crossings land in
	// WORLD SPACE, not this math — widen it out there, not by loosening canopy_blend_width here.
	float t1 = smoothstep(1.0 / 7.0 - canopy_blend_width, 1.0 / 7.0 + canopy_blend_width, mottle);
	float t2 = smoothstep(2.0 / 7.0 - canopy_blend_width, 2.0 / 7.0 + canopy_blend_width, mottle);
	float t3 = smoothstep(3.0 / 7.0 - canopy_blend_width, 3.0 / 7.0 + canopy_blend_width, mottle);
	float t4 = smoothstep(4.0 / 7.0 - canopy_blend_width, 4.0 / 7.0 + canopy_blend_width, mottle);
	float t5 = smoothstep(5.0 / 7.0 - canopy_blend_width, 5.0 / 7.0 + canopy_blend_width, mottle);
	float t6 = smoothstep(6.0 / 7.0 - canopy_blend_width, 6.0 / 7.0 + canopy_blend_width, mottle);
	vec3 canopy_col = mix(mix(mix(mix(mix(mix(canopy_a, canopy_b, t1), canopy_c, t2), canopy_d, t3), canopy_e, t4), canopy_f, t5), canopy_g, t6);
	vec3 canopy_nrm = normalize(mix(mix(mix(mix(mix(mix(nrm_a, nrm_b, t1), nrm_c, t2), nrm_d, t3), nrm_e, t4), nrm_f, t5), nrm_g, t6));

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

	// River: runs along `river_count` of the SAME 6 canopy-blend seam lines — reuses `mottle` (already sampled
	// above for the 7-way canopy split), so the river tracks the texture transition exactly instead of an
	// independent field crossing it at random angles — see this file's header. river_dist = distance (in
	// mottle-value space) to the NEAREST of the first `river_count` seam levels; seams beyond river_count don't
	// contribute at all (left at the 999.0 sentinel, never the min).
	float river_dist = 999.0;
	if (river_count >= 1) river_dist = min(river_dist, abs(mottle - 1.0 / 7.0));
	if (river_count >= 2) river_dist = min(river_dist, abs(mottle - 2.0 / 7.0));
	if (river_count >= 3) river_dist = min(river_dist, abs(mottle - 3.0 / 7.0));
	if (river_count >= 4) river_dist = min(river_dist, abs(mottle - 4.0 / 7.0));
	if (river_count >= 5) river_dist = min(river_dist, abs(mottle - 5.0 / 7.0));
	if (river_count >= 6) river_dist = min(river_dist, abs(mottle - 6.0 / 7.0));

	// Corridor gate (5th redesign, see header) — restricts the seam network down to one long meandering path,
	// so a closed loop elsewhere in the seam mesh (around a local mottle extremum) doesn't render as a river.
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

	// Golden sand fringe between canopy and water — bank_mask is 1 all the way from the river center out to
	// river_width and fades to 0 by river_width + river_bank_width, so the only place it actually SHOWS is
	// that outer ring: canopy fades to sand, sand fades to water, instead of canopy running straight into the
	// riverbed. Corridor-gated too, so the bank fringe doesn't show along seam sections outside the corridor.
	float bank_mask = (1.0 - smoothstep(river_width, river_width + river_bank_width, river_dist)) * corridor;
	vec4 banked_col = mix(ground_col, river_bank_color, bank_mask);

	COLOR = mix(banked_col, water_col, river_mask);
}
