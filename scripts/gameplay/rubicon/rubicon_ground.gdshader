shader_type canvas_item;

// Blue-grass / dark-sand blotchy ground for the Rubicon map. Screen-filling rect (rubicon_ground.gd),
// world_offset uniform makes the pattern scroll continuously with the player instead of the rect itself
// moving. Noise is BAKED into seamless textures at load time (FastNoiseLite/NoiseTexture2D, script side) —
// same "Luna's Wandering Stars" technique as assets/shaders/nebula_baked.gdshader — this shader only
// SAMPLES + tiles them via repeat wrap. An earlier hand-rolled live fbm() here showed a real banding
// artifact; the baked-texture approach is the one already proven artifact-free in this codebase.

uniform sampler2D tex_zone : repeat_enable, filter_linear;     // blue-vs-sand split (low frequency, big blotches)
uniform sampler2D tex_mottle : repeat_enable, filter_linear;   // within-zone color variation (higher frequency)
uniform sampler2D tex_river : repeat_enable, filter_linear;    // river contour field (very low frequency)

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);
uniform float zone_uv_scale = 0.0035;     // world px -> tex_zone UV
uniform float mottle_uv_scale = 0.02;     // world px -> tex_mottle UV
uniform float river_uv_scale = 0.0009;    // world px -> tex_river UV
uniform float blend_softness = 0.06;
uniform float blue_threshold = 0.5;
uniform vec4 col_blue_dark : source_color = vec4(0.14, 0.32, 0.62, 1.0);
uniform vec4 col_blue_light : source_color = vec4(0.30, 0.56, 0.90, 1.0);
uniform vec4 col_sand_dark : source_color = vec4(0.20, 0.15, 0.06, 1.0);
uniform vec4 col_sand_light : source_color = vec4(0.46, 0.36, 0.15, 1.0);

uniform float river_level = 0.5;    // RubiconConfig.RIVER_LEVEL — which contour becomes the river centerline
uniform float river_width = 0.035;  // half-width of the river band, in noise-value space (0 = no rivers)
uniform vec4 river_color_dark : source_color = vec4(0.05, 0.18, 0.35, 1.0);
uniform vec4 river_color_light : source_color = vec4(0.15, 0.45, 0.65, 1.0);
uniform float river_shimmer_speed = 0.4;

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;
	float n = texture(tex_zone, world_pos * zone_uv_scale).r;
	float zone = smoothstep(blue_threshold - blend_softness, blue_threshold + blend_softness, n);
	float mottle = texture(tex_mottle, world_pos * mottle_uv_scale).r;
	vec4 blue_col = mix(col_blue_dark, col_blue_light, mottle);
	vec4 sand_col = mix(col_sand_dark, col_sand_light, mottle);
	vec4 ground_col = mix(sand_col, blue_col, zone);

	// River: extract the near-river_level contour of a separate, much-lower-frequency noise field — a soft
	// winding band, not a hard-edged shape. A subtle two-wave animated shimmer gives it a "flowing water"
	// read without needing an actual scrolling texture asset.
	float rv = texture(tex_river, world_pos * river_uv_scale).r;
	float river_mask = 1.0 - smoothstep(river_width * 0.6, river_width, abs(rv - river_level));
	float shimmer_a = sin(world_pos.x * 0.04 + world_pos.y * 0.03 + TIME * river_shimmer_speed) * 0.5 + 0.5;
	float shimmer_b = sin(world_pos.x * 0.07 - world_pos.y * 0.05 + TIME * river_shimmer_speed * 1.3) * 0.5 + 0.5;
	vec4 water_col = mix(river_color_dark, river_color_light, mix(shimmer_a, shimmer_b, 0.5));

	COLOR = mix(ground_col, water_col, river_mask);
}
