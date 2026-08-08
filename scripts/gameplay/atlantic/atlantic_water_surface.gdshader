shader_type canvas_item;
render_mode blend_mix, unshaded;

// Screen-space "we're underwater" overlay for the Atlantic map — a fullscreen ColorRect on a CanvasLayer, same
// hint_screen_texture refraction trick as scripts/gameplay/fx/z_slash_distort.gdshader / explosion_shockwave.
// gdshader, but CONTINUOUS instead of a triggered burst: gently refracts the ENTIRE rendered frame (ground,
// enemies, ship — everything below this layer) through a slow-scrolling smooth noise field, then lays a
// procedural CAUSTIC sparkle network on top.
//
// WORLD-LOCKED (2026-08-08 fix): the noise fields are sampled at (UV -> world_pos via world_offset/rect_size,
// same trick atlantic_ground.gdshader uses), NOT raw screen UV — so the ripple/caustic pattern is pinned to the
// TERRAIN and pans naturally as the player moves, instead of sitting fixed on the screen (the original,
// wrong-feeling behaviour: "Ripple đính kèm theo terrain, không di chuyển theo người chơi" — the player wanted
// it to move WITH the world as they fly around). Only the actual screen_tex REFRACTION lookup stays in
// SCREEN_UV space (that's the rendered frame we're displacing, which is inherently screen-space).
//
// Caustics technique: the difference of two independently-scrolling CELLULAR (Voronoi) noise fields, sharpened
// with pow() — where the two fields happen to cross near-equal value, the difference goes to ~0 and pow()
// blows that up into a bright thin vein; everywhere else it stays dark. That's the standard cheap real-time
// "fake caustics" trick (no light-front simulation, no ray tracing) — reads as a dancing net-of-light pattern
// very close to real underwater caustics for a fraction of the cost. Two INDEPENDENT scroll directions/speeds
// keep the network from ever visibly repeating.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D tex_distort : repeat_enable, filter_linear;    // smooth low-freq field — gentle refraction only
uniform sampler2D tex_caustic_a : repeat_enable, filter_linear;  // cellular/Voronoi — caustic network input #1
uniform sampler2D tex_caustic_b : repeat_enable, filter_linear;  // cellular/Voronoi — caustic network input #2

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);

uniform float distort_strength = 0.006;   // UV displacement, in SCREEN_UV units (0..1) — keep this SMALL
uniform float distort_speed = 0.05;
uniform float sparkle_intensity = 0.35;
uniform vec4 sparkle_color : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform float sparkle_speed = 0.09;

const float DISTORT_WORLD_UV_SCALE = 1.0 / 900.0;   // world-px -> tex_distort UV
const float CAUSTIC_WORLD_UV_SCALE = 1.0 / 260.0;   // world-px -> caustic UV (much higher frequency)
const float CAUSTIC_SHARPNESS = 10.0;               // higher = thinner, more distinct veins

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;

	// Gentle whole-screen refraction: two samples of the same smooth field, offset so X/Y displacement are
	// decorrelated (otherwise everything would just slide diagonally instead of "waving").
	vec2 duv = world_pos * DISTORT_WORLD_UV_SCALE + vec2(TIME * distort_speed, TIME * distort_speed * 0.7);
	float dx = texture(tex_distort, duv).r - 0.5;
	float dy = texture(tex_distort, duv + vec2(3.7, 1.9)).r - 0.5;
	vec2 disp = vec2(dx, dy) * distort_strength;
	vec3 base = texture(screen_tex, SCREEN_UV + disp).rgb;

	// Caustic sparkle network — see this shader's header for the "difference of two Voronoi fields" trick.
	vec2 cuv = world_pos * CAUSTIC_WORLD_UV_SCALE;
	vec2 cuv_a = cuv + vec2(TIME * sparkle_speed, TIME * sparkle_speed * 0.35);
	vec2 cuv_b = cuv * 1.31 - vec2(TIME * sparkle_speed * 0.6, TIME * sparkle_speed * 0.8);
	float ca = texture(tex_caustic_a, cuv_a).r;
	float cb = texture(tex_caustic_b, cuv_b).r;
	float caustic = pow(clamp(1.0 - abs(ca - cb) * 2.0, 0.0, 1.0), CAUSTIC_SHARPNESS);

	// Dampen the sparkle over already-dark pixels — the SAME additive overlay reads as far more intense
	// contrast against near-black (e.g. the current's own dark centerline) than against the lighter seafloor,
	// even though its magnitude is uniform across the screen. 2026-08-08 fix: "ở những phần current, ripple trở
	// nên rõ ràng hơn rất nhiều vì current có màu tối sẫm" — mask the sparkle by the base pixel's own luminance
	// so it fades out over the deep/dark water instead of standing out on it.
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	float sparkle_mask = smoothstep(0.0, 0.3, luma);

	vec3 col = base + sparkle_color.rgb * caustic * sparkle_intensity * sparkle_mask;
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
