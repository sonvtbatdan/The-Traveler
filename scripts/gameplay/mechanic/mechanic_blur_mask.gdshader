shader_type spatial;
render_mode unshaded, cull_disabled;
// Flat "blur amount" proxy material — verbatim port of electric_blur_mask.gdshader (see that file's header).

const float MAX_BLUR_PX = 6.0;   // matches mechanic_terrain_edit.gd's Blur slider range (0..6.0)

instance uniform float blur_amount : hint_range(0.0, 6.0) = 0.0;

void fragment() {
	ALBEDO = vec3(blur_amount / MAX_BLUR_PX);
}
