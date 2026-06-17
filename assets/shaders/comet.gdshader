shader_type canvas_item;
render_mode blend_add;
// Comet on a LONG rectangular quad (Sprite2D, UV 0..1), rotated so local +X = the tail direction (away from
// the light). ONE continuous gas form: a tiny intensely-bright core wrapped in a delicate coma that blends
// seamlessly into a streaky, translucent, gently-curving tail that fans out and fades away. No head/tail
// seam, lengthwise filaments, soft feathered edges, additive + edge vignette (no rectangle). Noise helpers
// copied from the structure shaders.

// ── TUNABLES (driven by arena_comet.gd) ─────────────────────────────────────────
uniform float head_x          : hint_range(0.0, 0.4) = 0.16;  // head position along the quad (UV.x)
uniform float aspect          = 2.7;                          // quad width/height (keeps the coma circular)
uniform float tail_length     : hint_range(0.2, 0.9) = 0.8;   // how far down-tail the tail reaches (UV.x)
uniform float tail_base_mult  : hint_range(0.4, 1.6) = 0.95;  // tail base half-width = coma_size * this
uniform float fan_spread      : hint_range(0.0, 0.5) = 0.20;  // extra half-width gained by the tip (fanning)
uniform float tail_softness   : hint_range(0.5, 6.0) = 1.9;   // across-width feather (lower = softer edges)
uniform float tail_opacity    : hint_range(0.0, 1.0) = 0.7;   // tail translucency (stars show through)
uniform vec3  tail_color : source_color = vec3(0.55, 0.78, 1.0);
// Head: tiny hot core + delicate haze.
uniform float core_size       : hint_range(0.01, 0.12) = 0.04;
uniform float core_brightness : hint_range(0.5, 5.0) = 2.6;
uniform float coma_size       : hint_range(0.04, 0.3) = 0.13;
uniform float coma_glow       : hint_range(0.0, 1.5) = 0.45;
uniform vec3  coma_color : source_color = vec3(0.85, 0.92, 1.0);
// Longitudinal streaks (filaments running down the tail).
uniform float streak_intensity : hint_range(0.0, 1.0) = 0.7;
uniform float streak_fine     : hint_range(4.0, 40.0) = 20.0; // across freq → fine strands
uniform float streak_len      : hint_range(0.5, 8.0) = 2.6;   // along freq (low) → long strands
// Organic shape.
uniform float curve_amount    : hint_range(-0.3, 0.3) = 0.10; // gentle centerline curve
uniform float edge_irregularity : hint_range(0.0, 0.12) = 0.035;
// Ion tail.
uniform bool  second_tail     = true;
uniform float ion_angle       : hint_range(0.0, 0.3) = 0.06;
uniform float ion_fan_spread  : hint_range(0.0, 0.3) = 0.10;
uniform vec3  ion_color : source_color = vec3(0.45, 0.65, 1.0);
uniform float seed            = 0.0;

// ── NOISE ───────────────────────────────────────────────────────────────────────
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 grad(vec2 ip) { float a = hash(ip) * 6.28318530718; return vec2(cos(a), sin(a)); }
float gnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	float n = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
	return n * 0.5 + 0.5;
}
float fbm(vec2 p, int oct) {
	float v = 0.0; float amp = 0.5; float norm = 0.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	p = rot * p;
	for (int k = 0; k < 8; k++) { if (k >= oct) { break; }
		v += amp * gnoise(p); norm += amp; p = rot * p * 2.0; amp *= 0.5; }
	return v / max(norm, 0.0001);
}

// One teardrop tail's brightness. `along` = UV.x - head_x (0 at head, + down-tail); `across` in H units.
// Full width + brightness AT the head (no fade-in) so it merges with the coma; curved + wandering centerline
// for an organic shape; lengthwise streaks; opacity fades to the tip.
float tail_lobe(float along, float across, float spread, float base_w) {
	float t = clamp(along / tail_length, 0.0, 1.0);
	if (t >= 1.0) { return 0.0; }
	// Curved + noise-wandered centerline (organic, slightly asymmetric).
	float center = curve_amount * along * along
		+ (fbm(vec2(along * 1.8 + seed, 4.2), 4) - 0.5) * 2.0 * edge_irregularity;
	float a = across - center;
	// Width: head-wide → fans toward the tip, with a wavy non-straight silhouette.
	float wob = 0.85 + 0.30 * fbm(vec2(along * 4.0 + seed, 1.7), 4);
	float halfw = (base_w + spread * t) * wob;
	float lat = a / max(halfw, 1e-4);
	float across_falloff = exp(-lat * lat * tail_softness);     // soft feathered sides
	// Smooth front gate across the head's x-extent → no hard line at along=0; tail eases in behind the head.
	float gate = smoothstep(-coma_size / aspect, coma_size / aspect, along);
	float along_falloff = pow(1.0 - t, 1.7) * gate;             // merges into the coma → 0 at tip
	// Longitudinal streaks: high freq across (fine strands), low freq along (long strands).
	float strands = fbm(vec2(along * streak_len + seed, a * streak_fine), 5);
	float streak = 1.0 - streak_intensity + streak_intensity * strands * 1.7;
	return across_falloff * along_falloff * max(streak, 0.0);
}

void fragment() {
	float along = UV.x - head_x;
	float across = UV.y - 0.5;

	// Head: tiny hot core (intense pinpoint) + delicate haze (dimmer, steeper). aspect keeps it circular.
	float dco = length(vec2(along * aspect, across));
	float core = exp(-dco * dco / (core_size * core_size)) * core_brightness;
	float haze = exp(-dco * dco / (coma_size * coma_size)) * coma_glow;

	// Dust tail — flows out of the head body (base ≈ head radius), full-bright at the head → merges seamlessly.
	float base_w = coma_size * tail_base_mult;
	float dust = tail_lobe(along, across, fan_spread, base_w);

	// Ion tail: same side, tiny shear → narrow fan (no X), straighter + bluer + fainter.
	float ion = 0.0;
	if (second_tail) {
		float across_ion = across - ion_angle * along;
		ion = tail_lobe(along, across_ion, ion_fan_spread, base_w * 0.55) * 0.55;
	}

	vec3 col = coma_color * (core + haze)
		+ tail_color * dust * tail_opacity
		+ ion_color * ion * tail_opacity;

	// Edge vignette → nothing reaches the quad border, so the rectangle never shows as a box.
	float edge = smoothstep(0.0, 0.05, UV.x) * smoothstep(1.0, 0.94, UV.x)
		* smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);
	col *= edge;

	COLOR = vec4(col, 1.0);
}
