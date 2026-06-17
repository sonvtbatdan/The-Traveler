shader_type canvas_item;
render_mode blend_add;
// Comet v2 (teardrop / brushstroke). One continuous gas form: a soft diffuse bright head that tapers
// smoothly into a fine, delicate, translucent, silky-streaked tail — WIDEST AT THE HEAD, narrowing to a
// point at the tip (the reverse of v1's cone). On a LONG rectangular quad (Sprite2D, UV 0..1), rotated so
// local +X = the tail direction (away from the light). Additive + edge vignette (no rectangle). Noise
// helpers copied from the structure shaders.

// ── TUNABLES (driven by arena_comet.gd) ─────────────────────────────────────────
uniform float head_x          : hint_range(0.0, 0.4) = 0.16;  // head position along the quad (UV.x)
uniform float aspect          = 2.8;                          // quad width/height (keeps the coma circular)
uniform float tail_length     : hint_range(0.2, 0.9) = 0.82;  // how far down-tail the tail reaches (UV.x)
uniform float tail_base_mult  : hint_range(0.4, 1.6) = 1.05;  // head (widest) half-width = coma_size * this
uniform float taper_pow       : hint_range(0.3, 3.0) = 0.9;   // taper curve: lower = stays fat longer
uniform float tip_frac        : hint_range(0.0, 0.3) = 0.05;  // tip half-width as a fraction of the head (→ point)
uniform float tail_softness   : hint_range(0.5, 6.0) = 1.8;   // across-width feather (lower = softer edges)
uniform float tail_opacity    : hint_range(0.0, 1.0) = 0.4;   // delicate/translucent (stars show through)
uniform float tail_fade       : hint_range(1.0, 5.0) = 2.6;   // brightness fade down-tail (higher = head-concentrated)
uniform vec3  tail_color : source_color = vec3(0.55, 0.78, 1.0);
// Head: small hot core + soft diffuse haze that melts into the tail.
uniform float core_size       : hint_range(0.01, 0.12) = 0.04;
uniform float core_brightness : hint_range(0.5, 5.0) = 1.8;
uniform float coma_size       : hint_range(0.04, 0.3) = 0.14;
uniform float coma_glow       : hint_range(0.0, 1.5) = 0.45;
uniform float head_softness   : hint_range(0.8, 2.5) = 1.35;  // <2 = broader/softer diffuse glow
uniform float head_elong      : hint_range(1.0, 4.0) = 2.2;   // >1 = oblong head stretched along the tail axis
uniform vec3  coma_color : source_color = vec3(0.85, 0.92, 1.0);
// Longitudinal streaks (fine silky filaments running down the tail).
uniform float streak_intensity : hint_range(0.0, 1.0) = 0.55;
uniform float streak_fine     : hint_range(4.0, 60.0) = 36.0; // across freq → fine dense strands
uniform float streak_len      : hint_range(0.5, 8.0) = 2.6;   // along freq (low) → long strands
uniform float flow_speed      : hint_range(0.0, 0.5) = 0.06;  // filaments scroll head→tip → travelling-gas feel
uniform float flicker_amt     : hint_range(0.0, 0.6) = 0.18;  // per-strand brightness boil over time
uniform float flicker_speed   : hint_range(0.0, 8.0) = 1.6;
uniform float wobble_amt      : hint_range(0.0, 0.1) = 0.02;  // slow sideways breathing of the filaments
uniform float wobble_speed    : hint_range(0.0, 4.0) = 0.9;
// Head shimmer.
uniform float head_pulse_amt  : hint_range(0.0, 0.5) = 0.12;  // gentle brightness pulse on the nucleus
uniform float head_pulse_speed : hint_range(0.0, 8.0) = 2.0;
// Organic shape.
uniform float curve_amount    : hint_range(-0.3, 0.3) = 0.07; // gentle sine bow
uniform float edge_irregularity : hint_range(0.0, 0.12) = 0.03;
// Ion tail.
uniform bool  second_tail     = true;
uniform float ion_angle       : hint_range(0.0, 0.3) = 0.06;
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
// Widest at the head (base_w), tapering to a fine point (base_w*tip_frac) at the tip; brightness
// concentrated at the head; fine silky streaks; gentle sine curve.
float tail_lobe(float along, float across, float base_w, float time) {
	float t = clamp(along / tail_length, 0.0, 1.0);
	if (t >= 1.0) { return 0.0; }
	// Gentle sine bow + noise-wandered centerline (organic, slightly asymmetric).
	float center = curve_amount * sin(along / max(tail_length, 1e-3) * 3.14159)
		+ (fbm(vec2(along * 1.8 + seed, 4.2), 4) - 0.5) * 2.0 * edge_irregularity;
	float a = across - center;
	// Width: WIDEST at the head → narrows to a point at the tip.
	float wob = 0.85 + 0.30 * fbm(vec2(along * 4.0 + seed, 1.7), 4);
	float wprofile = pow(1.0 - t, taper_pow);                       // 1 at head → 0 at tip
	float halfw = base_w * (tip_frac + (1.0 - tip_frac) * wprofile) * wob;
	float lat = a / max(halfw, 1e-4);
	float across_falloff = exp(-lat * lat * tail_softness);         // soft feathered sides
	// Smooth front gate across the head's x-extent → no seam at along=0; tail eases in behind the head.
	float gate = smoothstep(-coma_size / aspect, coma_size / aspect, along);
	float along_falloff = pow(1.0 - t, tail_fade) * gate;          // brightness concentrated at the head
	// Fine silky streaks: high freq across (dense strands), low freq along (long strands), lifted floor.
	// Animated: scroll filaments head→tip (along - flow); slow sideways wobble so the tail breathes; and a
	// per-strand flicker so the gas boils/churns rather than sitting static.
	float flow = time * flow_speed;
	float a_w = a + wobble_amt * sin(along * 7.0 - time * wobble_speed + seed);
	float strands = fbm(vec2((along - flow) * streak_len + seed, a_w * streak_fine), 6);
	float flicker = 1.0 + flicker_amt * (fbm(vec2(a_w * streak_fine * 0.5, time * flicker_speed + seed), 3) - 0.5) * 2.0;
	float streak = (1.0 - streak_intensity * 0.6 + streak_intensity * strands * 1.2) * flicker;
	return across_falloff * along_falloff * max(streak, 0.0);
}

void fragment() {
	float along = UV.x - head_x;
	float across = UV.y - 0.5;

	// Head: small hot core + a SOFT diffuse haze (sub-gaussian). Oblong — stretched along the tail axis by
	// head_elong (so it's not a round ball); aspect keeps the across-axis to scale.
	// Shimmer: a gentle brightness pulse + a slow churn so the nucleus feels like an active source.
	float head_pulse = 1.0 + head_pulse_amt * sin(TIME * head_pulse_speed + seed);
	float churn = 0.88 + 0.24 * fbm(vec2(along * 6.0 + TIME * 0.6, across * 6.0 - TIME * 0.4), 3);
	float dco = length(vec2(along * aspect / head_elong, across));
	float core = exp(-dco * dco / (core_size * core_size)) * core_brightness * head_pulse;
	float haze = exp(-pow(dco / coma_size, head_softness)) * coma_glow * head_pulse * churn;

	// Dust tail — widest at the head (≈ coma), tapering to a point; merges seamlessly with the coma.
	float base_w = coma_size * tail_base_mult;
	float dust = tail_lobe(along, across, base_w, TIME);

	// Ion tail: same side, tiny shear → narrow trail (no X), straighter + bluer + fainter; same taper.
	float ion = 0.0;
	if (second_tail) {
		float across_ion = across - ion_angle * along;
		ion = tail_lobe(along, across_ion, base_w * 0.55, TIME) * 0.55;
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
