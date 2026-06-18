shader_type canvas_item;
render_mode blend_mix, unshaded;
// Textured flame ribbon. UV.x runs along the beam (tiled tile_count times), UV.y across the width.
// Normal alpha blend (NOT additive) so the texture's dark outlines stay readable. Two scrolling samples
// of the same tile (different scale + speed) are overlaid so one still frame never looks like a static
// repeat. Flicker + subtle edge falloff + tint/intensity on top. Driven by flame_ribbon.gd.

uniform sampler2D flame_tex : repeat_enable, filter_linear;
uniform float tile_count      = 1.0;    // manual extra tiling multiplier; UV.x already carries arc-length tiles
uniform float scroll_speed    = 0.6;    // layer 1 scroll toward the head
uniform float scroll_speed_2  = 0.9;    // layer 2 scroll (opposite) to break the loop
uniform float layer2_scale    = 2.0;    // layer 2 samples the tile at a different scale
uniform float layer_mix       = 0.4;    // how strongly layer 2 modulates layer 1 (0 = layer 1 only)
uniform float flicker_speed   = 10.0;
uniform float flicker_amount  = 0.12;
uniform float edge_falloff    = 0.12;   // soft fade at the V edges (keep small; texture defines the edge)
uniform vec4  tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity       = 1.0;    // push hotter (toward white) via tint, or deeper via tint+this

float hash11(float p){ p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void fragment(){
	float t = TIME;
	float u = UV.x * tile_count;
	vec4 c1 = texture(flame_tex, vec2(u + t * scroll_speed, UV.y));
	vec4 c2 = texture(flame_tex, vec2(u * layer2_scale - t * scroll_speed_2, UV.y));
	vec4 col = c1;
	col.rgb *= mix(vec3(1.0), c2.rgb * 1.6, layer_mix);
	col.a   *= mix(1.0, clamp(c2.a * 1.4, 0.0, 1.4), layer_mix);
	float fl = 1.0 + flicker_amount * (sin(t * flicker_speed) + (hash11(floor(t * flicker_speed * 1.7)) - 0.5));
	col.rgb *= fl;
	float ev = smoothstep(0.0, edge_falloff, UV.y) * smoothstep(1.0, 1.0 - edge_falloff, UV.y);
	col.a *= ev;
	col.rgb *= tint_color.rgb * intensity;
	col.a *= tint_color.a;
	COLOR = col;
}
