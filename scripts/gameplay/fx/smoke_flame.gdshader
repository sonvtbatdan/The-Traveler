shader_type canvas_item;
render_mode blend_add;
// Source flame — a soft flame blob eroded into licking tongues by upward-scrolling fractal noise (the
// dynamic_fire technique). Additive, HDR-tinted so the arena glow env blooms the hot core.

uniform sampler2D fbm_tex : repeat_enable, filter_linear;
uniform float erosion_softness : hint_range(0.05, 0.5) = 0.22;
uniform float lick_speed : hint_range(0.2, 3.0) = 1.1;

void fragment() {
	float seed = fract((COLOR.r + COLOR.b) * 6.27 + 0.19);
	float age  = clamp(1.0 - COLOR.a, 0.0, 1.0);
	vec4 flame = texture(TEXTURE, UV);
	float n = texture(fbm_tex, UV * 2.2 + vec2(seed, -TIME * lick_speed)).r * 0.6
			+ texture(fbm_tex, UV * 5.5 + vec2(seed * 2.0, -TIME * lick_speed * 1.7)).r * 0.4;
	float edge = mix(0.08, 0.92, age);
	float mask = smoothstep(edge - erosion_softness, edge + erosion_softness, n);
	COLOR = vec4(COLOR.rgb, flame.a * mask * COLOR.a);
}
