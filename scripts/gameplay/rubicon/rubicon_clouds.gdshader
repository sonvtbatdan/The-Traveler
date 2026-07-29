shader_type canvas_item;

// Soft procedural cloud layer — baked seamless noise (same technique as rubicon_ground.gdshader /
// assets/shaders/nebula_baked.gdshader), thresholded into soft alpha blobs instead of a hard color split.
// No art dependency: clouds are the most seam-forgiving layer, good to prove the parallax rig on before
// touching harder ground/grass/tree assets.

uniform sampler2D tex_cloud : repeat_enable, filter_linear;

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);
uniform float uv_scale = 0.002;
uniform float coverage = 0.55;
uniform float softness = 0.18;
uniform float max_alpha = 0.3;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;
	float n = texture(tex_cloud, world_pos * uv_scale).r;
	float a = smoothstep(coverage - softness, coverage + softness, n) * max_alpha;
	COLOR = vec4(cloud_color.rgb, a);
}
