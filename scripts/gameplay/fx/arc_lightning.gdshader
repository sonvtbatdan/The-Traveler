shader_type canvas_item;
render_mode blend_add, unshaded;
// 2D lightning bolt shader (from the "2D lightning in Godot" tutorial), applied to a Line2D per arc link.
// A tileable thunder texture is scrolled along the bolt (UV.x × tiling + TIME × speed) so it crackles/flickers;
// `vanishing_value` (0→1) smoothsteps the texture away so the bolt dissolves; the HDR `color` makes it bloom
// under the arena WorldEnvironment. ADDITIVE so overlapping strands brighten toward white-hot.

uniform sampler2D basic_texture : repeat_enable, filter_linear;
uniform vec4 color = vec4(1.4, 2.2, 3.2, 1.0);   // HDR electric blue-white → blooms (raw, no sRGB convert)
uniform float scroll_speed = -2.0;     // UV.x scroll rate (texture crawls along the bolt)
uniform float tiling_x = 1.0;          // how many times the thunder texture repeats along the bolt length
uniform float vanishing_value = 0.0;   // 0 = full bolt, 1 = gone (sweeps the dim texels away first)
uniform float feather = 0.18;          // softness of the vanish edge

void fragment() {
	vec2 uv = vec2(UV.x * tiling_x + TIME * scroll_speed, UV.y);
	float t = texture(basic_texture, uv).r;                          // single channel (perf) = bolt brightness
	float keep = smoothstep(vanishing_value, min(vanishing_value + feather, 1.0), t);   // dissolve mask
	float v = t * keep;                                              // keep the soft falloff → glow halo survives
	COLOR = vec4(color.rgb * v, v);                                  // premultiplied additive (HDR core blooms)
}
