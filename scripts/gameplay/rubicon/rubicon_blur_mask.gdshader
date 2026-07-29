shader_type spatial;
render_mode unshaded, cull_disabled;
// Flat "blur amount" proxy material (rubicon_asset_layer.gd's blur-mask pass) — one shared resource across
// every scattered instance; each proxy's own blur value comes in via the "blur_amount" instance-uniform
// (RubiconAssetScan.set_instance_blur_param), not a per-material parameter, so many instances can share this
// one ShaderMaterial. Output encodes blur_amount/MAX_BLUR_PX into ALBEDO.r for rubicon_asset_composite.gdshader
// to read back and turn into a per-pixel blur radius.

const float MAX_BLUR_PX = 6.0;   // matches rubicon_terrain_edit.gd's Blur slider range (0..6.0)

instance uniform float blur_amount : hint_range(0.0, 6.0) = 0.0;

void fragment() {
	ALBEDO = vec3(blur_amount / MAX_BLUR_PX);
}
