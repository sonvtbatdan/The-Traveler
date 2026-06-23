shader_type canvas_item;
// Explosion SMOKE shader — MIX (alpha) blend on purpose: smoke OCCLUDES the scene, so it must be alpha-blended.
// (Additive dark smoke adds ~no light over a dark background → invisible; that was the original bug.) The puff
// is tinted by the per-particle ramp (warm-lit gray → dark gray) and faded by the alpha curve (0 → peak → 0, so
// it billows in after the fireball and dissipates). Noise erodes the edge as it fades for a wispy break-up.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float noise_scale      = 1.4;
uniform float erosion_softness = 0.25;

void fragment() {
	vec4 p = COLOR;                                          // rgb = gray ramp, a = opacity curve (0→peak→0)
	float n = texture(noise_tex, UV * noise_scale).r;
	vec4 puff = texture(TEXTURE, UV);                        // soft puff shape
	float edge = 1.0 - p.a;                                  // as opacity drops, erode more → wispy dissipation
	float mask = smoothstep(edge - erosion_softness, edge + erosion_softness, n);
	COLOR = vec4(p.rgb, puff.a * p.a * mask);               // alpha-blended → actually visible smoke
}
