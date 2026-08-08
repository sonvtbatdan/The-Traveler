shader_type spatial;
render_mode unshaded, cull_disabled;
// Flat "blur amount" proxy material — verbatim port of volcanic_blur_mask.gdshader.

const float MAX_BLUR_PX = 6.0;   // matches atlantic_terrain_edit.gd's Blur slider range (0..6.0)

instance uniform float blur_amount : hint_range(0.0, 6.0) = 0.0;

void fragment() {
	ALBEDO = vec3(blur_amount / MAX_BLUR_PX);
}
