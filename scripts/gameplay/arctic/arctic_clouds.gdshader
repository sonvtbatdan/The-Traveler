shader_type canvas_item;

// Procedural cloud layer — baked seamless noise, thresholded into alpha blobs instead of a hard color split.
// Port of mechanic_clouds.gdshader (see that file's header for the full `clumpiness` rationale — identical
// here).

uniform sampler2D tex_cloud : repeat_enable, filter_linear;

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);
uniform float uv_scale = 0.002;
uniform float coverage = 0.55;
uniform float softness = 0.18;
uniform float max_alpha = 0.3;
uniform float clumpiness = 0.65;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;
	float mass = texture(tex_cloud, world_pos * uv_scale).r;
	float effective_coverage = coverage + 0.16 * clumpiness;
	float edge_softness = mix(softness, softness * 0.15, clumpiness);
	float mask = smoothstep(effective_coverage - edge_softness, effective_coverage + edge_softness, mass);
	float detail = texture(tex_cloud, world_pos * uv_scale * 4.3 + vec2(91.0, -57.0)).r;
	float detail_mod = mix(1.0, 0.55 + 0.75 * detail, clumpiness);
	float a = clamp(mask * detail_mod, 0.0, 1.0) * max_alpha;
	COLOR = vec4(cloud_color.rgb, a);
}
