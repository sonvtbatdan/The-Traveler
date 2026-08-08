shader_type canvas_item;

// Dark-basalt / ash blotchy ground for the Volcanic map — real top-down cracked-lava-rock PHOTOS
// (assets/map/volcanic/maptile/<set>/), tinted per-zone and tiled at world-scale. Mirrors
// rubicon_ground.gdshader's overall technique (baked seamless NoiseTexture2D level-sets, sampled + tiled via
// repeat wrap) with one deliberate difference: the lava contour is built from TWO fields instead of one —
//   1. tex_river: smooth SIMPLEX noise (same technique as Rubicon's river) — an organic, naturally meandering
//      macro flow path, not a mathematical shape.
//   2. tex_river_detail: CELLULAR/Manhattan noise, much higher frequency — added to the macro distance below
//      (domain-warping the threshold, not the shape) to roughen the BOUNDARY into jagged cracked-rock nicks
//      without turning the whole flow into a straight polyline.
// An earlier version used cellular noise ALONE as tex_river — Voronoi cell edges are literally straight line
// segments meeting at sharp vertices, so the whole river read as a mathematical zigzag, not a natural lava
// flow (user feedback: "như những đường thẳng gấp khúc"). See VolcanicNoise's header for the full rationale;
// RIVER_DETAIL_FREQ_MULT/RIVER_DETAIL_STRENGTH there must match river_detail_uv_scale/river_detail_strength
// here so CPU river-avoidance and GPU paint agree on roughly where the lava is.
// No landmark system yet (see rubicon_ground.gdshader's landmark_* block for the pattern to port once a
// landmark asset exists) — this shader is otherwise a straight port.

uniform sampler2D tex_zone : repeat_enable, filter_linear;     // dark-basalt-vs-ash split (low frequency, big blotches)
uniform sampler2D tex_mottle : repeat_enable, filter_linear;   // ground variant-region field (higher frequency)
uniform sampler2D tex_river : repeat_enable, filter_linear;    // lava contour MACRO field (smooth, very low frequency)
uniform sampler2D tex_river_detail : repeat_enable, filter_linear;   // lava contour EDGE-JAG detail field (cellular, high frequency)
uniform sampler2D tex_ground_a : repeat_enable, filter_linear_mipmap;   // real top-down cracked-lava-rock photos,
uniform sampler2D tex_ground_b : repeat_enable, filter_linear_mipmap;   // each sampled at its own UV scale/
uniform sampler2D tex_ground_c : repeat_enable, filter_linear_mipmap;   // offset — see fragment() below
uniform sampler2D tex_ground_a_normal : repeat_enable, filter_linear_mipmap;   // real tangent-space normal map
uniform sampler2D tex_ground_b_normal : repeat_enable, filter_linear_mipmap;   // per ground_a/b/c (tools/
uniform sampler2D tex_ground_c_normal : repeat_enable, filter_linear_mipmap;   // generate_canopy_normal.py)
uniform sampler2D tex_water_wave : repeat_enable, filter_linear_mipmap;   // genuinely seamless wave-crest photo
                                                                            // (reused from Rubicon, recolored
                                                                            // below into a lava flow shimmer)

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);
uniform float zone_uv_scale = 0.0035;
uniform float mottle_uv_scale = 0.02;
uniform float river_uv_scale = 0.0009;
uniform float river_detail_uv_scale = 0.0063;   // world px -> tex_river_detail UV (river_uv_scale * RIVER_DETAIL_FREQ_MULT)
uniform float river_detail_strength = 0.55;      // detail perturbation amplitude, as a fraction of river_width
uniform float ground_uv_scale = 0.000625;   // world px -> tex_ground_a/b UV
uniform float ground_tint_strength = 0.5;   // 0 = photo colors as-is, 1 = fully multiply-tinted by zone color
uniform float blend_softness = 0.06;

// Real per-pixel directional lighting against tex_ground_*_normal — same manual Lambert + Blinn-Phong term as
// rubicon_ground.gdshader (see its header for why this isn't a real Light2D), tunable live via the Light Edit
// panel (volcanic_ground.gd's apply_ground_lighting).
uniform vec3 ground_light_dir = vec3(0.6, 0.6, 0.6);
uniform vec4 ground_light_color : source_color = vec4(1.0, 0.75, 0.55, 1.0);   // warm ember-tinted "sun"
uniform float ground_ambient = 0.35;
uniform float ground_contrast = 1.15;
uniform float ground_specular_strength = 0.35;
uniform float ground_specular_power = 18.0;
uniform float blue_threshold = 0.5;
uniform vec4 col_zone_a_light : source_color = vec4(0.10, 0.10, 0.14, 1.0);   // dark basalt zone
uniform vec4 col_zone_b_light : source_color = vec4(0.30, 0.24, 0.20, 1.0);   // ash/dust zone

uniform float river_level = 0.5;    // VolcanicConfig.RIVER_LEVEL — which contour becomes the lava centerline
uniform float river_width = 0.035;  // half-width of the lava band, in noise-value space (0 = no lava)
uniform vec4 river_color_dark : source_color = vec4(0.35, 0.05, 0.02, 1.0);
uniform vec4 river_color_light : source_color = vec4(0.95, 0.45, 0.05, 1.0);
uniform vec4 river_bank_color : source_color = vec4(0.16, 0.05, 0.03, 1.0);   // dark obsidian crust rim
uniform float river_bank_width = 0.012;   // extra noise-value half-width beyond river_width the rim extends —
                                            // narrower than Rubicon's sand fringe so it reads as a thin cracked
                                            // edge, not a beach
uniform float water_wave_uv_scale = 0.00385;
uniform float water_wave_speed = 26.0;

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;
	float n = texture(tex_zone, world_pos * zone_uv_scale).r;
	float zone = smoothstep(blue_threshold - blend_softness, blue_threshold + blend_softness, n);

	float mottle = texture(tex_mottle, world_pos * mottle_uv_scale).r;
	vec2 uv_a = world_pos * ground_uv_scale;
	vec2 uv_b = world_pos * ground_uv_scale * 1.37 + vec2(311.0, -173.0);
	vec2 uv_c = world_pos * ground_uv_scale * 0.79 + vec2(-197.0, 421.0);
	vec3 ground_a = texture(tex_ground_a, uv_a).rgb;
	vec3 ground_b = texture(tex_ground_b, uv_b).rgb;
	vec3 ground_c = texture(tex_ground_c, uv_c).rgb;

	vec3 nrm_a = texture(tex_ground_a_normal, uv_a).rgb * 2.0 - 1.0;
	vec3 nrm_b = texture(tex_ground_b_normal, uv_b).rgb * 2.0 - 1.0;
	vec3 nrm_c = texture(tex_ground_c_normal, uv_c).rgb * 2.0 - 1.0;

	const float region_softness = 0.04;
	float t_ab = smoothstep(1.0 / 3.0 - region_softness, 1.0 / 3.0 + region_softness, mottle);
	float t_bc = smoothstep(2.0 / 3.0 - region_softness, 2.0 / 3.0 + region_softness, mottle);
	vec3 ground_col_raw = mix(mix(ground_a, ground_b, t_ab), ground_c, t_bc);
	vec3 ground_nrm = normalize(mix(mix(nrm_a, nrm_b, t_ab), nrm_c, t_bc));

	vec3 zone_tint = mix(col_zone_b_light.rgb, col_zone_a_light.rgb, zone);
	vec4 ground_col = vec4(mix(ground_col_raw, ground_col_raw * zone_tint * 2.0, ground_tint_strength), 1.0);

	vec3 light_dir = normalize(ground_light_dir);
	float ndotl = max(dot(ground_nrm, light_dir), 0.0);
	float diffuse = ground_ambient + (1.0 - ground_ambient) * ndotl;
	diffuse = clamp((diffuse - 0.5) * ground_contrast + 0.5, 0.0, 2.5);
	vec3 light_tint = mix(vec3(1.0), ground_light_color.rgb, ndotl);
	vec3 half_vec = normalize(light_dir + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(ground_nrm, half_vec), 0.0), ground_specular_power) * ground_specular_strength;
	ground_col.rgb = ground_col.rgb * diffuse * light_tint + ground_light_color.rgb * spec;

	// Lava: extract the near-river_level contour of tex_river (smooth simplex — organic macro flow, same
	// technique as Rubicon's river) then PERTURB that distance with tex_river_detail (cellular/Manhattan, much
	// higher frequency) so the boundary itself roughens into jagged cracked-rock nicks without turning the
	// overall flow into a straight polyline — see this shader's header for why a cellular-only macro field was
	// wrong. The 0.78 factor (vs Rubicon's 0.6) is a narrower transition band relative to river_width, so the
	// smoothstep blend doesn't blur the detail term's jaggedness back into a soft curve.
	float rv = texture(tex_river, world_pos * river_uv_scale).r;
	float river_dist = abs(rv - river_level);
	float river_detail = texture(tex_river_detail, world_pos * river_detail_uv_scale).r;
	river_dist -= (river_detail - 0.5) * river_width * river_detail_strength;
	float river_mask = 1.0 - smoothstep(river_width * 0.78, river_width, river_dist);

	// Real (genuinely seamless) wave-crest photo — reused from Rubicon's watertile set, recolored via
	// river_color_light/dark into a lava flow shimmer instead of water.
	vec2 wave_dir_a = vec2(0.85, 0.53);
	vec2 wave_dir_b = vec2(-0.40, 0.92);
	vec2 wave_uv_a = world_pos * water_wave_uv_scale + wave_dir_a * TIME * water_wave_speed * water_wave_uv_scale;
	vec2 wave_uv_b = world_pos * water_wave_uv_scale * 1.7 - wave_dir_b * TIME * water_wave_speed * 0.6 * water_wave_uv_scale;
	float wave_a = texture(tex_water_wave, wave_uv_a).r;
	float wave_b = texture(tex_water_wave, wave_uv_b).r;
	float wave_mix = clamp(wave_a * 0.65 + wave_b * 0.5, 0.0, 1.0);
	vec3 water_rgb = mix(river_color_dark.rgb, river_color_light.rgb, wave_mix);
	water_rgb += vec3(pow(wave_mix, 5.0) * 0.4);   // bright glints on the sharpest wave crests (hot lava crust)

	// Glowing crust right at the lava's edge (where lava meets rock), textured by the same wave field instead
	// of a perfectly smooth ring so it reads as irregular cooling crust, not a drawn outline.
	vec3 glow_tint = river_bank_color.rgb + vec3(0.6, 0.15, 0.0) * wave_a;   // brief hot-orange flicker over the
	                                                                          // dark obsidian base, not a flat fill
	float shore_dist = abs(river_dist - river_width * 0.92);
	float glow_band = 1.0 - smoothstep(0.0, river_width * 0.10, shore_dist);
	water_rgb = mix(water_rgb, glow_tint, glow_band * (0.35 + 0.5 * wave_a));
	vec4 water_col = vec4(water_rgb, 1.0);

	// Dark obsidian crust rim between rock and lava — bank_mask is 1 from the lava center out to river_width
	// (harmlessly UNDER the lava, which composites on top of it below) and fades to 0 by
	// river_width + river_bank_width, so it only shows as that thin outer ring.
	float bank_mask = 1.0 - smoothstep(river_width, river_width + river_bank_width, river_dist);
	vec4 banked_col = mix(ground_col, river_bank_color, bank_mask);

	COLOR = mix(banked_col, water_col, river_mask);
}
