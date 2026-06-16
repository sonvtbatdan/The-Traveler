shader_type canvas_item;
// Background_2 — "Luna's Wandering Stars" technique: noise is BAKED into seamless textures at load (by
// FastNoiseLite/NoiseTexture2D on the script side), and this shader only SAMPLES + SCROLLS them. Much
// cheaper than live fBm. Shape (mask) is kept SEPARATE from colour: final = warm_colour × high-contrast
// mask, on a deep navy void base → big dark voids + glowing filaments instead of uniform soup.
//
// Infinite/deterministic: the script feeds world_offset = camera_world_pos * scroll_factor; textures are
// seamless and sampled with repeat wrap, so it tiles forever with no visible repeat. Two cloud layers
// scroll at slightly different rates for depth. A cheap hash star pass rides on top.

uniform sampler2D tex_a    : repeat_enable, filter_linear;   // cloud colour layer 1 (fBm)
uniform sampler2D tex_b    : repeat_enable, filter_linear;   // cloud colour layer 2 (fBm, diff seed)
uniform sampler2D tex_mask : repeat_enable, filter_linear;   // void/filament mask (ridged)

uniform vec2  world_offset    = vec2(0.0);   // camera world pos × scroll_factor (fed each frame)
uniform float scale_a         = 1.5;         // tiles of tex_a across the screen
uniform float scale_b         = 2.3;
uniform float scale_mask      = 1.1;
uniform float scroll_a        = 1.0;         // per-layer scroll-rate multiplier (depth)
uniform float scroll_b        = 1.4;
uniform float coverage        : hint_range(0.0, 1.0) = 0.45;  // void threshold (higher = more empty)
uniform float mask_contrast   : hint_range(0.02, 1.0) = 0.30; // smaller = sharper, snakier filaments
uniform float brightness      : hint_range(0.0, 2.0) = 0.60;  // dim < 1 so it stays a background
uniform float star_density    : hint_range(0.0, 1.0) = 0.06;
uniform float star_brightness = 0.8;

uniform vec3 col_void  : source_color = vec3(0.03, 0.05, 0.13);  // deep navy-blue base (makes warm pop)
uniform vec3 col_warm1 : source_color = vec3(0.55, 0.16, 0.07);  // dim red filament
uniform vec3 col_warm2 : source_color = vec3(0.95, 0.45, 0.16);  // bright orange filament
uniform vec3 col_core  : source_color = vec3(0.70, 0.85, 1.00);  // blue-white hottest cores

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Sparse pinpoint stars (same world drift so they travel with the gas).
float stars(vec2 p, float density, out float tint) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash(cell);
	tint = hash(cell + 7.3);
	if (h > density) { return 0.0; }
	vec2 c = vec2(hash(cell + 1.7), hash(cell + 4.1));
	float dst = distance(f, c);
	float bright = (1.0 - smoothstep(0.0, 0.10, dst));
	bright *= 0.4 + 0.6 * hash(cell + 9.9);
	return bright;
}

void fragment() {
	// Two cloud-colour layers at different scales + scroll rates → parallax depth within the gas.
	float a = texture(tex_a, UV * scale_a + world_offset * scroll_a).r;
	float b = texture(tex_b, UV * scale_b + world_offset * scroll_b).r;
	float cloud = a * 0.6 + b * 0.4;

	// Separate mask defines WHERE nebula exists. High-contrast smoothstep → mostly dark with bright
	// tendrils; `coverage` slides the void/cloud balance.
	float m = texture(tex_mask, UV * scale_mask + world_offset * scroll_a * 0.8).r;
	m = smoothstep(coverage, coverage + mask_contrast, m);

	float dens = cloud * m;   // colour × mask = the nebula shape

	// Deep navy everywhere; warm clouds ADD on top (so they pop against the blue), hottest cores → blue-white.
	vec3 warm = mix(col_warm1, col_warm2, smoothstep(0.25, 0.80, cloud));
	vec3 col = col_void;
	col += warm * dens * brightness;
	col += col_core * smoothstep(0.78, 1.0, dens) * brightness;

	// Star pass on top.
	float tint;
	float s = stars((UV * scale_a + world_offset * scroll_a) * 24.0, star_density, tint);
	vec3 star_col = mix(vec3(1.0, 1.0, 1.0), vec3(0.7, 0.82, 1.0), tint);
	col += star_col * s * star_brightness;

	COLOR = vec4(col, 1.0);
}
