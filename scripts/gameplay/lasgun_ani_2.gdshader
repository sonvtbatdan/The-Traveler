shader_type canvas_item;
render_mode blend_add, unshaded;

// ── lasgun_ani_2 — fully procedural blue energy beam ──────────────────────────────
// UV.x = 0 at the tail (origin), 1 at the head (target). UV.y = 0..1 across thickness (0.5 = centerline).
// Four layers drawn additively in one pass: blue glow halo → cyan-white body → white hot core →
// comet-head tendrils + tail fray. Turbulence + striations + flicker driven by in-shader fbm (no
// external NoiseTexture dependency). All tunables are uniforms — mirrored from lasgun_ani_2.gd.

// Geometry / envelope
uniform float head_flare_power = 2.0;   // how much every layer fans toward the head (higher = more flare)
uniform float head_softness    = 0.06;  // tail fade-in sharpness (smaller = crisper tail start)
uniform float tail_fray_amount = 0.6;   // strength of the frayed parallel streaks at the tail

// Layer widths (fraction of half-thickness, 0..1 from centerline)
uniform float core_width = 0.06;
uniform float body_width = 0.18;
uniform float glow_width = 0.5;

// Layer colors
uniform vec3 core_color : source_color = vec3(1.0, 0.972, 1.0);   // #ffffff / #f0f8ff
uniform vec3 body_color : source_color = vec3(0.62, 0.82, 1.0);   // #8fc4ff..#cfe6ff
uniform vec3 glow_color : source_color = vec3(0.31, 0.55, 1.0);   // #3a6cff..#6fa0ff

// Turbulence / wisps
uniform float distort_amount     = 0.16;  // how far noise pushes the centerline distance (wisp wobble)
uniform float distort_scale      = 4.0;   // noise spatial frequency along the beam
uniform float noise_scroll_speed = 1.4;   // how fast the turbulence scrolls (forward energy flow)

// Striations (energy flowing tail → head)
uniform float stria_freq     = 40.0;
uniform float stria_speed    = 8.0;
uniform float stria_strength = 0.25;

// Flicker (global brightness pulse, ~8–12 Hz)
uniform float flicker_speed  = 60.0;
uniform float flicker_amount = 0.10;

// Master
uniform float overall_intensity = 1.0;
uniform float activation        = 1.0;   // 0..1 ramp-in/out (width + alpha lerp) set by the script

// Traveling pulse (white-blue brightness wave racing away from the muzzle) + axial roll (helical highlight)
uniform vec3  wave_color : source_color = vec3(0.80, 0.90, 1.0);
uniform float wave_speed = 3.0;
uniform float wave_strength = 0.7;
uniform float beam_len = 760.0;     // beam length in px (pushed per shot) → pixel-fixed wavelengths
uniform float wave_len_1 = 137.0;   // four fixed pixel wavelengths (primes → large LCM, never converge)
uniform float wave_len_2 = 191.0;
uniform float wave_len_3 = 251.0;
uniform float wave_len_4 = 313.0;
uniform float roll_speed = 1.5;
uniform float roll_amp = 0.18;
uniform float roll_freq = 9.0;
uniform float roll_width = 0.06;
uniform float roll_strength = 0.5;
uniform float wave_noise = 2.5;    // phase jitter (rad) → irregular pulses
uniform float coil_noise = 0.06;   // small random wobble on the coil
uniform float coil_amp_1 = 0.85;   // per-coil weave amplitude as a fraction of roll_amp (all < 1)
uniform float coil_amp_2 = 0.65;
uniform float coil_amp_3 = 0.45;
uniform float coil_amp_4 = 0.30;

// ── hash / value-noise / fbm ──────────────────────────────────────────────────────
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i + vec2(0.0, 0.0));
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float t = TIME;

	// STRAIGHT main beam: distance from the FIXED centerline (UV.y = 0.5) + a little edge texture.
	float along = UV.x * beam_len;
	float dy = abs(UV.y - 0.5) * 2.0;
	dy += (fbm(vec2(UV.x * distort_scale + t * noise_scroll_speed, UV.y * 3.0)) - 0.5) * distort_amount;
	dy = max(dy, 0.0);

	// Length envelope: fade in at the tail, flare wider toward the head.
	float tail_in = smoothstep(0.0, head_softness, UV.x);
	float flare   = pow(clamp(UV.x, 0.0, 1.0), head_flare_power);   // 0 at tail → 1 at head
	float widen   = mix(0.45, 1.0, flare);                          // head is ~2.2x the tail width

	// Three radial layers (center-bright → edge-0), each widened toward the head.
	float core = smoothstep(core_width * widen, 0.0, dy);
	core = pow(core, 1.5);
	float body = smoothstep(body_width * widen, 0.0, dy);
	float glow = smoothstep(glow_width * widen, 0.0, dy);
	glow *= glow;   // softer falloff for the halo

	// Comet head: flame-like tendrils that splay/curl, influence rising as UV.x → 1.
	float head_zone = smoothstep(0.55, 1.0, UV.x);
	float tendril = fbm(vec2(UV.y * 6.0 + t * 2.3, UV.x * 8.0 - t * 3.1));
	float head_mask = mix(1.0, smoothstep(0.0, 0.85, tendril + (1.0 - dy)), head_zone);
	// Let the very tip splay outward past the nominal edge.
	float tip_splay = head_zone * smoothstep(1.0, 0.2, dy) * (0.4 + 0.6 * tendril);

	// Tail fray: thin parallel streaks that fade out behind the origin.
	float tail_zone = smoothstep(0.35, 0.0, UV.x);
	float streaks = sin(UV.y * 18.0 + fbm(vec2(UV.x * 3.0, UV.y * 5.0 + t)) * 6.0) * 0.5 + 0.5;
	float fray = tail_zone * streaks * tail_fray_amount * smoothstep(1.0, 0.1, dy);

	// Striations scrolling tail → head (energy flow cue).
	float stria = sin(UV.x * stria_freq - t * stria_speed) * 0.5 + 0.5;
	float stria_mul = 1.0 - stria_strength + stria_strength * stria;

	// Flicker (global breathing brightness) + a little noisy sparkle.
	float flick = 1.0 + flicker_amount * sin(t * flicker_speed);
	flick += (fbm(vec2(t * 7.0, 11.3)) - 0.5) * flicker_amount;

	// Compose.
	core *= tail_in * head_mask * stria_mul;
	body *= tail_in * head_mask;
	glow = (glow * tail_in + tip_splay + fray) * head_mask;

	// Four traveling brightness pulses at the SAME fixed pixel wavelengths (ride the coils). `along`
	// was computed above with the snake; a noise term keeps each pulse irregular.
	float wn = (fbm(vec2(UV.x * 5.0, t * 0.7)) - 0.5) * wave_noise;
	float wsum = 0.0;
	wsum += pow(0.5 + 0.5 * sin(along / wave_len_1 * TAU - t * wave_speed * 1.00 + wn), 3.0);
	wsum += pow(0.5 + 0.5 * sin(along / wave_len_2 * TAU - t * wave_speed * 0.83 + wn), 3.0);
	wsum += pow(0.5 + 0.5 * sin(along / wave_len_3 * TAU - t * wave_speed * 1.19 + wn), 3.0);
	wsum += pow(0.5 + 0.5 * sin(along / wave_len_4 * TAU - t * wave_speed * 0.67 + wn), 3.0);
	float wave_m = (wsum * 0.25) * body * wave_strength;

	// COILS wrapping the STRAIGHT beam: several helical threads at FIXED pixel wavelengths (never sync),
	// each a thin bright highlight weaving across the width off the centerline, with an irregular wobble.
	float cn = (fbm(vec2(UV.x * 8.0 + t * 1.3, 3.7)) - 0.5) * coil_noise;
	float coils = 0.0;
	coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_1 * sin(along / wave_len_1 * TAU - t * roll_speed * 1.00) + cn)));
	coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_2 * sin(along / wave_len_2 * TAU - t * roll_speed * 0.83) + cn)));
	coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_3 * sin(along / wave_len_3 * TAU - t * roll_speed * 1.19) + cn)));
	coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_4 * sin(along / wave_len_4 * TAU - t * roll_speed * 0.67) + cn)));
	coils *= tail_in * head_mask * roll_strength;

	vec3 col = (core_color * core * 1.6 + body_color * body + glow_color * glow * 0.8);
	col += wave_color * (wave_m + coils);
	col *= flick * overall_intensity * activation;

	float alpha = clamp(core * 1.2 + body * 0.8 + glow * 0.5 + fray * 0.4 + tip_splay * 0.5 + wave_m * 0.5 + coils * 0.5, 0.0, 1.0);
	alpha *= activation;

	COLOR = vec4(col, alpha);
}
