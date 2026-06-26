shader_type canvas_item;
render_mode blend_add, unshaded;
// 2D lightning bolt — the tutorial technique. A Line2D is textured with a CONTINUOUS thunder texture (a bright
// jagged centreline + soft glow). The bolt IS that texture: `color * t` is the soft blue body, and the white
// core is `pow(t, core_sharp)` — a SMOOTH, continuous function of the texture brightness (NOT a threshold), so
// the bright centre is a continuous line that never breaks into dashes. ADDITIVE → blooms under the arena env.

uniform sampler2D basic_texture : repeat_enable, filter_linear;
uniform vec4 color = vec4(0.3, 0.8, 1.8, 1.0);       // soft blue body/glow
uniform vec4 core_color = vec4(1.8, 2.0, 2.5, 1.0);  // HDR white-blue core (blooms)
uniform float core_sharp = 6.0;        // higher = thinner core; it's pow(t,core_sharp) so it stays CONTINUOUS
uniform float scroll_speed = 0.0;      // UV.x scroll (0 = static)
uniform float tiling_x = 1.0;          // texture repeats along the bolt length
uniform float phase = 0.0;             // static UV.x offset (a second strand crackles out of phase)
uniform float vanishing_value = 0.0;   // 0 = full bolt, 1 = gone
uniform float feather = 0.18;

void fragment() {
	vec2 uv = vec2(UV.x * tiling_x + TIME * scroll_speed + phase, UV.y);
	float t = texture(basic_texture, uv).r;                          // bolt brightness (continuous bright centreline)
	float keep = smoothstep(vanishing_value, min(vanishing_value + feather, 1.0), t);   // dissolve
	float v = t * keep;                                              // soft blue body
	float wcore = pow(t, core_sharp) * keep;                         // CONTINUOUS white core (smooth, no dashes)
	vec3 rgb = color.rgb * v + core_color.rgb * wcore;
	COLOR = vec4(rgb, max(v, wcore));                                // additive
}
