shader_type canvas_item;
render_mode blend_add, unshaded;
// Dynamic-fire erosion/dissolve shader (tutorial technique). Applied as the GPUParticles2D DRAW material.
// ADDITIVE blend: dark/eroded areas add NO light (so they never read as "dirty"), and overlapping particles
// brighten toward a white-hot core — the clean glowing-flamethrower look. Each particle's per-instance COLOR
// carries the ParticleProcessMaterial output: rgb = hot ramp (white→orange→red over life), a = alpha curve
// (0→1 over life) used as the EROSION EDGE so the flame dissolves as it ages.

uniform sampler2D noise_tex : repeat_enable, filter_linear;   // seamless single-channel erosion noise
uniform float noise_scale     = 0.7;    // tiling of the noise across each particle quad (smaller = larger, smoother)
uniform float erosion_softness = 0.28;  // width of the smoothstep band (larger = softer, wispier edge)
uniform float intensity        = 1.1;   // overall brightness (additive → glow)
uniform float glow             = 0.0;   // HDR boost: pushes output rgb >1 so a WorldEnvironment bloom catches it
uniform float fade_start       = 0.62;  // life fraction where the particle starts fading out (kills hard ember specks)

void fragment() {
	vec4 particle = COLOR;                                   // per-particle ramp colour (rgb) + alpha-curve (a)
	float n = texture(noise_tex, UV * noise_scale).r;        // 0..1 noise
	float edge = particle.a;                                 // 0 at birth (full flame) -> 1 at death (gone)
	float mask = smoothstep(edge - erosion_softness, edge + erosion_softness, n);
	float fade = 1.0 - smoothstep(fade_start, 1.0, particle.a);   // dissipate late embers instead of leaving hard chunks
	vec4 flame = texture(TEXTURE, UV);                       // flame sprite (grayscale-on-black OR transparent)
	float lum = max(flame.r, max(flame.g, flame.b));         // brightness = the flame's internal detail
	float coverage = flame.a * lum;                          // shape: works for opaque-on-black AND RGBA flames
	COLOR = vec4(particle.rgb * (intensity + glow), coverage * mask * fade);   // glow>0 → HDR rgb (>1) → WorldEnvironment bloom
}
