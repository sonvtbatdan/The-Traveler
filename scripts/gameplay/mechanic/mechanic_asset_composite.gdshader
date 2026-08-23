shader_type canvas_item;
// Composites mechanic_asset_layer.gd's color pass with its blur-mask pass — verbatim port of
// electric_asset_composite.gdshader (see that file's header for the full rationale).

uniform sampler2D tex_blur_mask;
const float MAX_BLUR_PX = 6.0;   // must match mechanic_blur_mask.gdshader's MAX_BLUR_PX

void fragment() {
	float blur_px = texture(tex_blur_mask, UV).r * MAX_BLUR_PX;
	vec2 ps = TEXTURE_PIXEL_SIZE * blur_px;
	vec4 sum = vec4(0.0);
	float wsum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y)) * ps;
			float w = exp(-float(x * x + y * y) * 0.5);
			sum += texture(TEXTURE, UV + o) * w;
			wsum += w;
		}
	}
	COLOR = sum / max(wsum, 1e-4);
}
