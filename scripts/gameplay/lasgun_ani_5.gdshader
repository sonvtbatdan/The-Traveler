shader_type canvas_item;
render_mode blend_add, unshaded;

// lasgun_ani_5 body — procedural energy-beam tube, ported from lasgun_ani_2.gdshader's straight-beam
// branch (this project's earlier procedural-beam experiment), replacing the body.png tile+fade texture.
// UV.x = 0 at the tail (gun) -> 1 at the head (impact). UV.y = 0..1 across thickness (0.5 = centerline).
// Four layers drawn additively: distortion-wobbled core/body/glow width envelope that flares toward the
// head, tail-fray streaks, head tendrils, striations, flicker, and travelling wave/coil highlights.
//
// The muzzle ("head") is NOT a separate shader/quad anymore — it's this SAME tube: the width envelope
// tapers to a true point at UV.x=0 (the `cone` factor below) and a radial `point_glow` term makes that
// point read as a bright ignition spark. Because it's the identical code/palette/turbulence as the rest
// of the tube, the muzzle can't help but connect seamlessly — there's no second shader to fall out of sync.

uniform float beam_len = 760.0;    // beam length in px (pushed per-frame) — pixel-fixed wavelengths
uniform float thickness_px = 120.0;   // beam thickness in px (pushed per-frame) — for the point glow's radius
uniform float activation = 1.0;    // 0..1 fire-in/out ramp * short-range fade, set from GDScript each frame

uniform float core_width = 0.06;
uniform float body_width = 0.18;
uniform float glow_width = 0.5;
uniform float head_flare_power = 2.0;
uniform float head_softness = 0.06;
uniform float tail_fray_amount = 0.6;

uniform float cone_frac = 0.08;       // fraction of beam_len over which the tube opens from a point to full width
uniform float point_radius_px = 70.0; // radius (px) of the bright ignition point (pushed per-frame = half the beam's current thickness, so it always matches the tube's width)
uniform float point_boost = 1.6;      // extra brightness multiplier on the ignition point
uniform float point_color_bias = 0.4; // 0 = point is core_color (white-hot), 1 = point is body_color (red) — leans the ignition point redder than the tube's white core
uniform float birth_mult = 1.0;       // fire-start punch: point radius scales by this, eases to 1 over time

uniform float distort_amount = 0.16;
uniform float distort_scale = 4.0;
uniform float noise_scroll_speed = 1.4;

uniform float stria_freq = 40.0;
uniform float stria_speed = 8.0;
uniform float stria_strength = 0.25;

uniform float flicker_speed = 60.0;
uniform float flicker_amount = 0.10;

uniform float wave_speed = 3.0;
uniform float wave_strength = 0.7;
uniform float roll_speed = 1.5;
uniform float roll_amp = 0.18;
uniform float roll_strength = 0.5;

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 body_color : source_color = vec3(1.0, 0.25, 0.15);
uniform vec3 glow_color : source_color = vec3(0.85, 0.05, 0.05);
uniform vec3 wave_color : source_color = vec3(1.0, 0.55, 0.35);

// Fixed pixel wavelengths (primes -> large LCM, never converge) and fine detail constants — internal,
// not exposed as tunables (matches lasgun_ani_2.gdshader's originals).
const float WAVE_LEN_1 = 137.0;
const float WAVE_LEN_2 = 191.0;
const float WAVE_LEN_3 = 251.0;
const float WAVE_LEN_4 = 313.0;
const float ROLL_WIDTH = 0.06;
const float WAVE_NOISE = 2.5;
const float COIL_NOISE = 0.06;
const float COIL_AMP_1 = 0.85;
const float COIL_AMP_2 = 0.65;
const float COIL_AMP_3 = 0.45;
const float COIL_AMP_4 = 0.30;

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
	float turb = fbm(vec2(UV.x * distort_scale + t * noise_scroll_speed, UV.y * 3.0));

	float dy = abs(UV.y - 0.5) * 2.0 + (turb - 0.5) * distort_amount;
	dy = max(dy, 0.0);
	float tail_in = smoothstep(0.0, head_softness, UV.x);
	float flare = pow(clamp(UV.x, 0.0, 1.0), head_flare_power);
	// `cone` opens the tube from a true point (0 width) at UV.x=0 up to its normal tail width by
	// cone_frac — the muzzle IS this opening, not a separate stamp glued on afterward.
	float cone = smoothstep(0.0, cone_frac, UV.x);
	float widen = cone * mix(0.45, 1.0, flare);
	float core = pow(smoothstep(core_width * widen, 0.0, dy), 1.5);
	float body = smoothstep(body_width * widen, 0.0, dy);
	float glow = smoothstep(glow_width * widen, 0.0, dy);
	glow *= glow;
	float head_zone = smoothstep(0.55, 1.0, UV.x);
	float tendril = fbm(vec2(UV.y * 6.0 + t * 2.3, UV.x * 8.0 - t * 3.1));
	float head_mask = mix(1.0, smoothstep(0.0, 0.85, tendril + (1.0 - dy)), head_zone);
	float tip_splay = head_zone * smoothstep(1.0, 0.2, dy) * (0.4 + 0.6 * tendril);
	float tail_zone = smoothstep(0.35, 0.0, UV.x);
	float streaks = sin(UV.y * 18.0 + fbm(vec2(UV.x * 3.0, UV.y * 5.0 + t)) * 6.0) * 0.5 + 0.5;
	float fray = tail_zone * streaks * tail_fray_amount * smoothstep(1.0, 0.1, dy);

	float stria = sin(UV.x * stria_freq - t * stria_speed) * 0.5 + 0.5;
	float stria_mul = 1.0 - stria_strength + stria_strength * stria;
	float flick = 1.0 + flicker_amount * sin(t * flicker_speed);
	flick += (fbm(vec2(t * 7.0, 11.3)) - 0.5) * flicker_amount;

	core *= tail_in * head_mask * stria_mul;
	body *= tail_in * head_mask;
	glow = (glow * tail_in + tip_splay + fray) * head_mask;

	// Ignition point: a bright radial spark exactly at the tube's true origin (UV = (0, 0.5) in actual
	// pixels), independent of `cone`/`tail_in` — those fade the TUBE to nothing right where this point
	// takes over, so the point is the only thing visible at the very tip, then the cone grows out of it.
	vec2 origin_px = vec2(UV.x * beam_len, (UV.y - 0.5) * thickness_px);
	float point_glow = smoothstep(point_radius_px * birth_mult, 0.0, length(origin_px));
	vec3 point_color = mix(core_color, body_color, point_color_bias);

	// Traveling brightness pulses (energy flowing tail -> head).
	float wn = (fbm(vec2(UV.x * 5.0, t * 0.7)) - 0.5) * WAVE_NOISE;
	float wsum = 0.0;
	wsum += pow(0.5 + 0.5 * sin(along / WAVE_LEN_1 * TAU - t * wave_speed * 1.00 + wn), 3.0);
	wsum += pow(0.5 + 0.5 * sin(along / WAVE_LEN_2 * TAU - t * wave_speed * 0.83 + wn), 3.0);
	wsum += pow(0.5 + 0.5 * sin(along / WAVE_LEN_3 * TAU - t * wave_speed * 1.19 + wn), 3.0);
	wsum += pow(0.5 + 0.5 * sin(along / WAVE_LEN_4 * TAU - t * wave_speed * 0.67 + wn), 3.0);
	float wave_m = (wsum * 0.25) * body * wave_strength;

	// Coils wrapping the beam (helical highlight).
	float cn = (fbm(vec2(UV.x * 8.0 + t * 1.3, 3.7)) - 0.5) * COIL_NOISE;
	float coils = 0.0;
	coils += smoothstep(ROLL_WIDTH, 0.0, abs((UV.y - 0.5) - (roll_amp * COIL_AMP_1 * sin(along / WAVE_LEN_1 * TAU - t * roll_speed * 1.00) + cn)));
	coils += smoothstep(ROLL_WIDTH, 0.0, abs((UV.y - 0.5) - (roll_amp * COIL_AMP_2 * sin(along / WAVE_LEN_2 * TAU - t * roll_speed * 0.83) + cn)));
	coils += smoothstep(ROLL_WIDTH, 0.0, abs((UV.y - 0.5) - (roll_amp * COIL_AMP_3 * sin(along / WAVE_LEN_3 * TAU - t * roll_speed * 1.19) + cn)));
	coils += smoothstep(ROLL_WIDTH, 0.0, abs((UV.y - 0.5) - (roll_amp * COIL_AMP_4 * sin(along / WAVE_LEN_4 * TAU - t * roll_speed * 0.67) + cn)));
	coils *= tail_in * head_mask * roll_strength;

	vec3 col = core_color * core * 1.6 + body_color * body + glow_color * glow * 0.8;
	col += wave_color * (wave_m + coils);
	col += point_color * point_glow * point_boost * 1.6;
	col *= flick;

	float alpha = clamp(core * 1.2 + body * 0.8 + glow * 0.5 + fray * 0.4 + tip_splay * 0.5 + wave_m * 0.5 + coils * 0.5 + point_glow * point_boost, 0.0, 1.0);

	COLOR = vec4(col * activation, alpha * activation);
}
