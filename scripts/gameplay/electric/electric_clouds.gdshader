shader_type canvas_item;

// Procedural cloud layer — baked seamless noise (same technique as electric_ground.gdshader /
// assets/shaders/nebula_baked.gdshader), thresholded into alpha blobs instead of a hard color split.
// No art dependency: clouds are the most seam-forgiving layer, good to prove the parallax rig on before
// touching harder ground/grass/tree assets.
//
// `clumpiness` (Terrain Edit panel's "Cloud Clumpiness" slider) morphs the look between two extremes: at 0,
// a WIDE smoothstep band around `coverage` reads as a soft, fairly uniform misty veil (the original look).
// At 1, the SAME underlying mass field gets a much narrower/harder edge (soft haze -> a distinct silhouette)
// AND a RAISED effective threshold (fewer noise peaks qualify as "cloud" at all, not just sharper edges on
// the same total area — 3 stacked layers each still covering ~50% at hard edges would otherwise union into
// near-total sky coverage with no real gaps), plus a second, higher-frequency sample of the same noise
// texture (no extra texture memory) multiplies into the alpha as internal turbulence, so surviving cloud
// interiors read as fluffy/uneven instead of flat. Net result: real "some areas thick, some areas clear"
// cumulus-like coverage instead of a uniform fog layer.

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
