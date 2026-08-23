shader_type canvas_item;
// Composites electric_asset_layer.gd's color pass (TEXTURE, the merged real 3D assets + cloud occluder) with
// its blur-mask pass (tex_blur_mask, same camera transform, proxy geometry whose ALBEDO.r encodes that
// instance's own blur/MAX_BLUR_PX — see electric_blur_mask.gdshader) to give each scattered asset type its
// own independent blur amount even though they now all share ONE render pass (needed so assets and the real
// 3D cloud mesh can depth-test/occlude each other correctly — see electric_trees.gd's header comment).
// Same 3x3 gaussian shape as assets/shaders/dof_blur.gdshader, just with a per-pixel radius instead of a
// uniform one.

uniform sampler2D tex_blur_mask;
const float MAX_BLUR_PX = 6.0;   // must match electric_blur_mask.gdshader's MAX_BLUR_PX

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
