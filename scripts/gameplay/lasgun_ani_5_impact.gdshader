shader_type canvas_item;
render_mode blend_add, unshaded;

// lasgun_ani_5_impact — procedural radial energy burst, replacing the hand-drawn 12-frame impact
// flipbook. Same tongue technique as lasgun_ani_5_muzzle.gdshader but spread over the full circle (no
// fan half-angle) since an impact has no preferred direction, plus a solid hot core disc at the centre.
// UV=(0.5, 0.5) is the hit point.

uniform float frame = 0.0;
uniform float spikes = 10.0;
uniform float spike_min = 5.0;
uniform float notch = 0.55;
uniform float len_jitter = 0.35;
uniform float body_round = 2.2;
uniform float round_var = 1.4;
uniform float tip_frac = 0.35;
uniform float distort_amount = 0.12;
uniform float core_radius = 0.16;   // solid hot-core disc radius (fraction of quad half-size)
uniform vec3 core_color : source_color = vec3(1.0, 0.98, 1.0);
uniform vec3 body_color : source_color = vec3(0.62, 0.82, 1.0);
uniform vec3 glow_color : source_color = vec3(0.31, 0.55, 1.0);
uniform float activation = 1.0;     // 0..1 fire-in/out ramp, set from GDScript each frame

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
	vec2 p = (UV - 0.5) * 2.0;
	float radius = length(p);
	float ang = atan(p.y, p.x);
	float turns = (ang / TAU) + 0.5;   // 0..1 around the circle

	float n_count = max(1.0, floor(mix(spike_min, spikes, hash(vec2(frame, 5.3))) + 0.5));
	float tphase = turns * n_count;
	float ti = floor(tphase);
	float tfrac = (tphase - ti) - 0.5;
	float h1 = hash(vec2(ti, frame + 1.7));
	float h2 = hash(vec2(ti, frame + 13.1));
	float br = clamp(body_round + (h2 - 0.5) * 2.0 * round_var, 0.4, 6.0);
	float x = tfrac * 2.0;
	float lobe = pow(max(0.0, 1.0 - pow(abs(x), br)), 1.0 / br);
	float jit = 1.0 + (h1 - 0.5) * 2.0 * len_jitter;
	float reach = (1.0 - notch + notch * lobe) * jit;

	float turb = fbm(vec2(turns * 6.0 + frame * 0.3, radius * 3.0));
	float rr = radius + (turb - 0.5) * distort_amount;
	float along_t = clamp(rr / max(0.05, reach), 0.0, 1.0);
	float spike = 1.0 - smoothstep(1.0 - tip_frac, 1.0, along_t);

	float core_disc = 1.0 - smoothstep(core_radius * 0.6, core_radius, radius);
	float core = max(core_disc, spike * (1.0 - smoothstep(0.0, 0.4, along_t)));
	float body = spike * (1.0 - smoothstep(0.2, 0.85, along_t));
	float glow = spike + core_disc * 0.6;

	vec3 col = core_color * core * 1.6 + body_color * body + glow_color * glow * 0.8;
	float alpha = clamp(core * 1.3 + body * 0.8 + glow * 0.5, 0.0, 1.0);
	COLOR = vec4(col * activation, alpha * activation);
}
