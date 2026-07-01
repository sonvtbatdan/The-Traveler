shader_type canvas_item;
render_mode blend_mix;

// Photoshop-style blend modes that need the backdrop (screen behind the sprite):
//   mode 0 = Screen, 1 = Hard Light, 2 = Overlay, 3 = Lighten.
// Normal / Add (Color Dodge) / Multiply do NOT use this shader — they use CanvasItemMaterial.
uniform int mode = 0;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

float b_screen(float b, float s)    { return 1.0 - (1.0 - b) * (1.0 - s); }
float b_overlay(float b, float s)   { return b < 0.5 ? 2.0 * b * s : 1.0 - 2.0 * (1.0 - b) * (1.0 - s); }
// Hard Light = Overlay with source and backdrop swapped.
float b_hardlight(float b, float s) { return s < 0.5 ? 2.0 * b * s : 1.0 - 2.0 * (1.0 - b) * (1.0 - s); }

vec3 blend3(vec3 dst, vec3 src) {
	if (mode == 0) {
		return vec3(b_screen(dst.r, src.r), b_screen(dst.g, src.g), b_screen(dst.b, src.b));
	} else if (mode == 1) {
		return vec3(b_hardlight(dst.r, src.r), b_hardlight(dst.g, src.g), b_hardlight(dst.b, src.b));
	} else if (mode == 3) {
		return max(dst, src);   // Lighten = keep the brighter of backdrop/source per channel
	}
	return vec3(b_overlay(dst.r, src.r), b_overlay(dst.g, src.g), b_overlay(dst.b, src.b));
}

void fragment() {
	vec4 src = texture(TEXTURE, UV) * COLOR;       // sprite pixel (× node modulate)
	vec3 dst = texture(screen_tex, SCREEN_UV).rgb; // backdrop behind this sprite
	vec3 res = blend3(dst, src.rgb);
	// Composite by the sprite's own alpha, output opaque so blend_mix just writes
	// our computed colour over the backdrop (alpha 0 areas write the backdrop back = no change).
	COLOR = vec4(mix(dst, res, src.a), 1.0);
}
