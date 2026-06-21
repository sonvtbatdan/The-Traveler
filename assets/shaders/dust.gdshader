shader_type canvas_item;
render_mode blend_add;
// Dark space dust: sparse motes placed deterministically in WORLD space (so they sit in the world and
// scroll with it). A mote emits NO light by itself (additive blend → invisible) and only shows when a
// light source (ship / bullets / lasers) is near it. Lights are passed in as world-space point lights.

uniform vec2  cam_world  = vec2(0.0);            // camera world position (this fragment's world frame)
uniform vec2  view_size  = vec2(1440.0, 780.0);  // visible world size (viewport / zoom)
uniform float dust_density : hint_range(0.0, 1.0) = 0.12;  // fraction of cells holding a mote (sparse)
uniform float dust_cell   = 50.0;                // world px per dust cell
uniform float mote_size   = 2.6;                 // mote radius (px)
uniform vec3  dust_color  : source_color = vec3(0.62, 0.70, 0.95);  // dust tint when lit

const int MAX_LIGHTS = 48;
uniform int   light_count = 0;
uniform vec2  light_pos[MAX_LIGHTS];        // world positions
uniform float light_radius[MAX_LIGHTS];     // reach (px)
uniform float light_intensity[MAX_LIGHTS];
uniform vec3  light_color[MAX_LIGHTS];

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 wp = cam_world + (UV - 0.5) * view_size;   // this fragment's world position
	// Find the nearest dust mote (one per occupied cell; 3×3 covers cell boundaries).
	vec2 cell = floor(wp / dust_cell);
	float best = 0.0;
	vec2 mote_world = wp;
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 c = cell + vec2(float(xx), float(yy));
			if (hash(c) > dust_density) { continue; }
			vec2 m = (c + vec2(0.2 + 0.6 * hash(c + 1.3), 0.2 + 0.6 * hash(c + 4.7))) * dust_cell;
			float pres = smoothstep(mote_size, 0.0, distance(wp, m));
			if (pres > best) { best = pres; mote_world = m; }
		}
	}
	if (best <= 0.001) {
		COLOR = vec4(0.0);   // no dust here → invisible
	} else {
		// Light the mote by every nearby point light.
		vec3 lcol = vec3(0.0);
		for (int i = 0; i < MAX_LIGHTS; i++) {
			if (i >= light_count) { break; }
			float fall = smoothstep(light_radius[i], 0.0, distance(mote_world, light_pos[i])) * light_intensity[i];
			lcol += light_color[i] * fall;
		}
		lcol = clamp(lcol, 0.0, 2.0);
		COLOR = vec4(dust_color * lcol * best, 1.0);
	}
}
