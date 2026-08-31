shader_type canvas_item;
render_mode blend_add;
// Ember spark — a soft hot dot that FLICKERS (per-particle phase from the COLOR.r/COLOR.g seed, like the
// smoke shader) and keeps a bright pinpoint core. Additive; HDR output so the arena glow env blooms it.

uniform float flicker_hz : hint_range(0.0, 40.0) = 16.0;
uniform float core_boost : hint_range(1.0, 4.0)  = 2.2;

void fragment() {
	float seed = fract(sin(dot(COLOR.rgb, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	vec4 t = texture(TEXTURE, UV);
	float d = t.a;
	float core = pow(d, 4.0) * core_boost;                    // sharp bright pinpoint
	float f = 0.6 + 0.4 * sin(TIME * flicker_hz * 6.2831853 + seed * 40.0);
	float lum = max(COLOR.r, max(COLOR.g, COLOR.b));
	vec3 rgb = COLOR.rgb + vec3(core * lum);
	COLOR = vec4(rgb, (d + core * 0.5) * COLOR.a * f);
}
