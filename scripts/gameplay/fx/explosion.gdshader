shader_type canvas_item;
render_mode blend_add, unshaded;
// Explosion FIREBALL-PUFF shader. Unlike dynamic_fire, this does NOT punch holes with the noise (that produced
// the stippled "sparkle" embers). Instead the noise only MOTTLES brightness (a multiply, never a cutout), so
// each puff stays a solid filled blob with fiery internal variation. Additive + HDR → blooms. The puff's own
// alpha (soft radial) + the per-particle alpha curve handle the fade; the noise never removes coverage.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float noise_scale = 0.55;   // coarse → broad flame mottling, not fine speckle
uniform float mottle      = 0.45;   // how much the noise darkens (0 = flat, 1 = strong)
uniform float intensity   = 1.2;
uniform float glow        = 1.8;    // HDR boost → blooms

void fragment() {
	vec4 particle = COLOR;                                   // rgb = red/orange ramp, a = fade curve
	float n = texture(noise_tex, UV * noise_scale + vec2(particle.a * 0.15)).r;
	float mott = mix(1.0 - mottle, 1.0, n);                  // brightness only — never cuts coverage
	vec4 puff = texture(TEXTURE, UV);                        // soft radial puff (solid centre → soft rim)
	COLOR = vec4(particle.rgb * (intensity + glow) * mott, puff.a * particle.a);
}
