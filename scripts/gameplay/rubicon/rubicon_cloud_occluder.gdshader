shader_type spatial;
render_mode unshaded;
// Real 3D cloud geometry (rubicon_trees.gd's cloud occluder box, world Y ~ RubiconConfig.CLOUD_MIN_PX..
// CLOUD_MAX_PX) living in the SAME World3D/camera pass as the scattered assets, so the engine's own
// per-pixel depth test does the height-based clipping for free: parts of a tall asset above this box occlude
// it (poke through, matching CLOUD_MAX_PX), parts below get occluded BY it (still "under the clouds") —
// see rubicon_trees.gd's header comment for why this replaces the old whole-object above/below split.
// Same blotchy-noise look as rubicon_clouds.gdshader (the decorative 2D parallax layer kept for sky
// atmosphere), just sampled from absolute world XZ instead of a 2D UV/world_offset trick, since this mesh is
// real geometry that moves in world space to track the camera (rubicon_trees.gd repositions it every frame).

uniform sampler2D tex_cloud : repeat_enable, filter_linear;
uniform float uv_scale = 0.0003;
uniform float coverage = 0.55;
uniform float softness = 0.18;
uniform float max_alpha = 0.3;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float n = texture(tex_cloud, world_xz * uv_scale).r;
	float a = smoothstep(coverage - softness, coverage + softness, n) * max_alpha;
	ALBEDO = cloud_color.rgb;
	ALPHA = a;
}
