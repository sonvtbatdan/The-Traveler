shader_type canvas_item;
render_mode blend_mix, unshaded;
// Stylized cel-fire for the Elephant's M2 attack — a POLAR field on one quad centred on the boss:
// it draws the radial fire JET (a spoke at the locked aim) AND the coiling fire RING together,
// clipped to the formed `sweep`. Normal alpha blend (NOT additive) so the dark cel outline stays
// crisp. Cartoon look: noise carves licking tongues on the outer edge; heat → discrete colour bands.
// Driven by elephant_move_2_fire.gd; all geometry/timing live in arena_elephant.gd (collision unchanged).

// ── Colours (hot core → yellow → orange body → dark rim) ──
uniform vec4 core_color         : source_color = vec4(1.0, 0.957, 0.753, 1.0);  // #fff4c0
uniform vec4 body_color         : source_color = vec4(1.0, 0.824, 0.290, 1.0);  // yellow
uniform vec4 body_orange_color  : source_color = vec4(1.0, 0.541, 0.118, 1.0);  // #ff8a1e
uniform vec4 outline_color      : source_color = vec4(0.776, 0.227, 0.078, 1.0);// #c63a14

// ── Geometry (normalised: quad half-size = 1; ring band sits at ring_frac) ──
uniform float ring_frac        = 0.80;   // radius of the ring band within the quad (0..1)
uniform float band_half        = 0.085;  // half-thickness of the fire band
uniform float jet_half_angle   = 0.30;   // radians: angular half-width of the radial jet spoke

// ── Cel band split (fractions of heat, outer→inner) ──
uniform float outline_thickness = 0.16;  // outermost rim share
uniform float orange_share      = 0.30;  // orange body share
uniform float yellow_share      = 0.28;  // yellow share (rest = pale core)

// ── Flame breakup / motion ──
uniform float tongue_height      = 0.7;   // extra outward reach of tongues (× band_half)
uniform float tongue_density     = 16.0;  // tongues around the ring / along the jet
uniform float tongue_lean        = 0.6;   // curl toward the travel direction
uniform float noise_scale        = 3.0;
uniform float noise_scroll_speed = 1.3;
uniform float flicker_speed      = 24.0;
uniform float flicker_amount     = 0.12;
uniform float overall_intensity  = 1.0;

// ── Driven per-frame by the script ──
uniform float activation  = 1.0;       // 0..1 ramp-in / fade-out (alpha)
uniform float sweep       = 3.14159;   // formed half-extent of the ring (0..PI; PI = closed)
uniform float aim_angle   = 0.0;       // centre angle of the jet + coil (locked aim)
uniform float beam_active = 1.0;       // 1 while the jet emits, 0 after

// NOTE: PI and TAU are built-in constants in the Godot shading language — do NOT redeclare them
// (redefinition = shader compile error → the MeshInstance2D falls back to a solid white quad).

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) { v += amp * vnoise(p); p *= 2.03; amp *= 0.5; }
	return v;
}
float ang_diff(float a, float b) {
	return mod(a - b + PI, TAU) - PI;
}
// heat (0=outer edge → 1=core) mapped to discrete cel bands.
vec4 cel(float h) {
	if (h <= 0.0) return vec4(0.0);
	if (h < outline_thickness) return outline_color;
	if (h < outline_thickness + orange_share) return body_orange_color;
	if (h < outline_thickness + orange_share + yellow_share) return body_color;
	return core_color;
}

void fragment() {
	float t = TIME;
	vec2 d = (UV - vec2(0.5)) * 2.0;     // -1..1, centre = boss
	float rad = length(d);
	float ang = atan(d.y, d.x);
	float da = abs(ang_diff(ang, aim_angle));

	// ── Coiling ring ──
	float ring_heat = 0.0;
	if (da <= sweep && rad > ring_frac - band_half * 2.0) {
		// outward tongues carved by scrolling noise along the ring (angle = along coord)
		float along = ang * tongue_density - t * noise_scroll_speed + da * tongue_lean;
		float tn = fbm(vec2(along, t * 0.7 + 3.0));
		float outer = ring_frac + band_half + tn * tongue_height * band_half;
		float inner = ring_frac - band_half;
		if (rad > inner && rad < outer) {
			float dc = rad - ring_frac;
			float norm = (dc < 0.0) ? (-dc) / band_half : dc / max(0.001, outer - ring_frac);
			ring_heat = 1.0 - clamp(norm, 0.0, 1.0);
		}
	}

	// ── Radial jet spoke (only while the beam emits) ──
	float jet_heat = 0.0;
	if (beam_active > 0.5 && rad < ring_frac + band_half && rad > 0.02) {
		float along = rad * tongue_density - t * noise_scroll_speed;
		float jn = fbm(vec2(along, ang * 3.0 + t * 0.6));
		float halfw = jet_half_angle * (0.35 + 0.65 * rad / ring_frac);   // widen toward the ring
		halfw += (jn - 0.5) * 0.12 * tongue_height;                       // licking side edges
		float dj = abs(ang_diff(ang, aim_angle));
		if (dj < halfw) jet_heat = 1.0 - clamp(dj / halfw, 0.0, 1.0);
	}

	float heat = max(ring_heat, jet_heat);
	if (heat <= 0.0) { COLOR = vec4(0.0); }
	else {
		float flick = 1.0 + flicker_amount * (sin(t * flicker_speed) + (fbm(vec2(t * 5.0, 7.0)) - 0.5));
		vec4 c = cel(heat);
		c.rgb *= clamp(flick * overall_intensity, 0.0, 2.0);
		c.a *= activation;
		COLOR = c;
	}
}
