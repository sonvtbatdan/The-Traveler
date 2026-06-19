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

// Muzzle mode — reshape the SAME beam texture into flame tongues (1) vs normal straight beam (0, default).
uniform int   muzzle_mode     = 0;
uniform float mz_tongues      = 5.0;    // number of flame tongues across the fan
uniform float mz_spread       = 1.0;    // fan HALF-angle (rad) — tongues radiate ±this from the gun apex
uniform float mz_sharpness    = 3.0;    // (retired — replaced by mz_body_round; kept for compatibility)
uniform float mz_notch        = 0.5;    // valley depth between tongues (0..1)
uniform float mz_len_jitter   = 0.3;    // per-tongue length variation (hash)
uniform float mz_tip_softness = 0.25;   // (retired — tip taper now driven by mz_tip_frac)
uniform float mz_body_round   = 3.0;    // CENTER fatness: >1 fat/convex leaf, =1 diamond, <1 needle
uniform float mz_tip_frac     = 0.2;    // fraction of tongue length used for the tip taper (small = blade w/ sudden point)
uniform float mz_count_min    = 2.0;    // per-frame tongue count re-rolls in [mz_count_min, mz_tongues]
uniform float mz_round_var    = 1.8;    // per-tongue fatness jitter around mz_body_round (needle↔leaf spread)
uniform float mz_asym         = 0.4;    // per-tongue sideways lean → asymmetric spikes (0 = symmetric)
uniform float mz_aspect       = 0.5;    // quad width/length, so polar angles aren't squashed by the scale
uniform float mz_frame        = 0.0;    // flipbook frame index — re-rolls the tongue shape each tick

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
	float along = UV.x * beam_len;
	// Shared turbulence — the SAME fbm field feeds both the beam and the muzzle (identical texture).
	float turb = fbm(vec2(UV.x * distort_scale + t * noise_scroll_speed, UV.y * 3.0));

	// Envelope vars — assigned by whichever mode runs; the rest of the shader is shared.
	float core; float body; float glow;
	float tail_in = 1.0; float head_mask = 1.0; float tip_splay = 0.0; float fray = 0.0;
	float along_t = 0.0;   // 0 = base → 1 = rim; set by the muzzle branch, used by the muzzle blue-edge tint

	if (muzzle_mode == 1) {
		// MUZZLE: a RADIAL fan of flame tongues spreading from the gun apex (UV.x = 0, UV.y = 0.5).
		// Polar coords from that apex: tongues occupy ANGULAR bands and reach out by RADIUS — the same
		// spreading fan the old polygon muzzle had, with the beam's smoothstep softness for free.
		vec2 p = vec2(UV.x, (UV.y - 0.5) * mz_aspect);             // local from the gun (aspect-corrected)
		float radius = length(p);
		float ang = atan(p.y, p.x);                                // 0 = straight ahead → ± = fanning sideways
		float fan = clamp(ang / max(0.05, mz_spread), -1.0, 1.0);  // -1..1 across the fan (mz_spread = half-angle)
		float fan_edge = 1.0 - smoothstep(0.8, 1.0, abs(fan));     // soft fade at the fan's outer edges
		// Per-frame tongue COUNT — the number of spikes re-rolls each flipbook tick (mz_frame), so the
		// muzzle never shows the same fixed prong count twice.
		float n_count = max(1.0, floor(mix(mz_count_min, mz_tongues, hash(vec2(mz_frame, 9.1))) + 0.5));
		float tphase = (fan * 0.5 + 0.5) * n_count;
		float ti = floor(tphase);
		float frac = (tphase - ti) - 0.5;                          // -0.5..0.5 within a tongue
		// Per-tongue, per-frame SHAPE — length, fatness and sideways lean all re-roll so no two spikes match.
		float h1 = hash(vec2(ti, mz_frame + 3.7));                 // length jitter
		float h2 = hash(vec2(ti, mz_frame + 17.3));                // fatness (needle ↔ leaf)
		float h3 = hash(vec2(ti, mz_frame + 31.9));                // sideways lean (asymmetry)
		float br = clamp(mz_body_round + (h2 - 0.5) * 2.0 * mz_round_var, 0.4, 6.0);
		float lean = (h3 - 0.5) * mz_asym;                         // shift this tongue's peak sideways
		float x = (frac - lean) * 2.0;                             // -1..1 across the tongue (asymmetric)
		// Super-ellipse body: br > 1 → fat fleshy leaf; =1 diamond; <1 pinched needle. |x|>1 → notch (lobe 0).
		float lobe = pow(max(0.0, 1.0 - pow(abs(x), br)), 1.0 / br);
		float jit = 1.0 + (h1 - 0.5) * 2.0 * mz_len_jitter;
		// mz_notch = cut DEPTH (0 = no gap, 1 = valley pulls to the base); floor = 1 - depth, independent of mz_body_round.
		float reach = (1.0 - mz_notch + mz_notch * lobe) * jit * fan_edge;     // radial extent — fat plateau, deep notch valleys
		float rr = radius + (turb - 0.5) * distort_amount * 0.5;   // fbm shimmer on the tips
		// Along-length late taper: a broad blade holding full width until the last `mz_tip_frac` of its
		// length, then pinching to a point — not a uniform triangle. (Also masks rr > reach → 0.)
		along_t = clamp(rr / max(0.05, reach), 0.0, 1.0);          // 0 at the gun → 1 at the tongue tip
		float flame = smoothstep(1.0, 1.0 - mz_tip_frac, along_t) * step(abs(ang), mz_spread);
		core = flame * (1.0 - smoothstep(0.0, 0.45, along_t));     // hot white near the base
		body = flame * (1.0 - smoothstep(0.25, 0.85, along_t));    // cyan-white mid
		glow = flame;                                              // blue along the whole tongue
	} else {
		// BEAM: straight tube (unchanged).
		float dy = abs(UV.y - 0.5) * 2.0 + (turb - 0.5) * distort_amount;
		dy = max(dy, 0.0);
		tail_in = smoothstep(0.0, head_softness, UV.x);
		float flare = pow(clamp(UV.x, 0.0, 1.0), head_flare_power);
		float widen = mix(0.45, 1.0, flare);
		core = pow(smoothstep(core_width * widen, 0.0, dy), 1.5);
		body = smoothstep(body_width * widen, 0.0, dy);
		glow = smoothstep(glow_width * widen, 0.0, dy);
		glow *= glow;
		float head_zone = smoothstep(0.55, 1.0, UV.x);
		float tendril = fbm(vec2(UV.y * 6.0 + t * 2.3, UV.x * 8.0 - t * 3.1));
		head_mask = mix(1.0, smoothstep(0.0, 0.85, tendril + (1.0 - dy)), head_zone);
		tip_splay = head_zone * smoothstep(1.0, 0.2, dy) * (0.4 + 0.6 * tendril);
		float tail_zone = smoothstep(0.35, 0.0, UV.x);
		float streaks = sin(UV.y * 18.0 + fbm(vec2(UV.x * 3.0, UV.y * 5.0 + t)) * 6.0) * 0.5 + 0.5;
		fray = tail_zone * streaks * tail_fray_amount * smoothstep(1.0, 0.1, dy);
	}

	// Striations + flicker (shared by both modes).
	float stria = sin(UV.x * stria_freq - t * stria_speed) * 0.5 + 0.5;
	float stria_mul = 1.0 - stria_strength + stria_strength * stria;
	float flick = 1.0 + flicker_amount * sin(t * flicker_speed);
	flick += (fbm(vec2(t * 7.0, 11.3)) - 0.5) * flicker_amount;

	core *= tail_in * head_mask * stria_mul;
	body *= tail_in * head_mask;
	glow = (glow * tail_in + tip_splay + fray) * head_mask;

	// Traveling brightness pulses — BEAM ONLY (don't make sense at a muzzle).
	float wave_m = 0.0;
	if (muzzle_mode == 0) {
		float wn = (fbm(vec2(UV.x * 5.0, t * 0.7)) - 0.5) * wave_noise;
		float wsum = 0.0;
		wsum += pow(0.5 + 0.5 * sin(along / wave_len_1 * TAU - t * wave_speed * 1.00 + wn), 3.0);
		wsum += pow(0.5 + 0.5 * sin(along / wave_len_2 * TAU - t * wave_speed * 0.83 + wn), 3.0);
		wsum += pow(0.5 + 0.5 * sin(along / wave_len_3 * TAU - t * wave_speed * 1.19 + wn), 3.0);
		wsum += pow(0.5 + 0.5 * sin(along / wave_len_4 * TAU - t * wave_speed * 0.67 + wn), 3.0);
		wave_m = (wsum * 0.25) * body * wave_strength;
	}

	// COILS wrapping the beam — BEAM ONLY.
	float coils = 0.0;
	if (muzzle_mode == 0) {
		float cn = (fbm(vec2(UV.x * 8.0 + t * 1.3, 3.7)) - 0.5) * coil_noise;
		coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_1 * sin(along / wave_len_1 * TAU - t * roll_speed * 1.00) + cn)));
		coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_2 * sin(along / wave_len_2 * TAU - t * roll_speed * 0.83) + cn)));
		coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_3 * sin(along / wave_len_3 * TAU - t * roll_speed * 1.19) + cn)));
		coils += smoothstep(roll_width, 0.0, abs((UV.y - 0.5) - (roll_amp * coil_amp_4 * sin(along / wave_len_4 * TAU - t * roll_speed * 0.67) + cn)));
		coils *= tail_in * head_mask * roll_strength;
	}

	vec3 col = (core_color * core * 1.6 + body_color * body + glow_color * glow * 0.8);
	col += wave_color * (wave_m + coils);
	// MUZZLE: 20% more blue, biased to the edges. along_t → 1 at the whole rim (tip + lateral sides,
	// where reach ≈ rr), so this tints the perimeter toward the blue glow colour and leaves the core white.
	if (muzzle_mode == 1) {
		float blue_amt = clamp(0.2 * mix(0.6, 1.4, along_t), 0.0, 1.0);   // ~0.12 at base → ~0.28 at the edges
		col = mix(col, glow_color, blue_amt);
	}
	col *= flick * overall_intensity * activation;

	float alpha = clamp(core * 1.2 + body * 0.8 + glow * 0.5 + fray * 0.4 + tip_splay * 0.5 + wave_m * 0.5 + coils * 0.5, 0.0, 1.0);
	alpha *= activation;

	COLOR = vec4(col, alpha);
}
