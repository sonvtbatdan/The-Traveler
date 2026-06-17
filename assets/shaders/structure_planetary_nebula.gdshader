shader_type canvas_item;
// Planetary nebula (Ring / Helix "Eye of God") on a centered quad (Sprite2D, UV 0..1).
// A central star sits in a dark cavity ringed by a glowing bicolor shell (inner hotter teal/green,
// outer cooler red/orange), made wispy with fbm turbulence. `look`: 0 = hollow ring, 1 = filled eye
// with a dark pupil. Noise helpers copied from nebula_bg.gdshader (the repo duplicates these per-shader).

// ── TUNABLES ───────────────────────────────────────────────────────────────────
uniform float seed            = 0.0;
uniform float look            : hint_range(0.0, 1.0) = 0.0;   // 0 ring · 1 eye
uniform float shell_radius    : hint_range(0.1, 0.95) = 0.62; // peak-brightness radius (0..1 of quad)
uniform float shell_thickness : hint_range(0.02, 0.4) = 0.14;
uniform vec3  inner_color : source_color = vec3(0.20, 0.95, 0.85); // hot inner (teal/green)
uniform vec3  outer_color : source_color = vec3(0.95, 0.35, 0.18); // cool outer (red/orange)
uniform float star_brightness : hint_range(0.0, 4.0) = 1.6;
uniform float turbulence      : hint_range(0.0, 0.6) = 0.22;
uniform float halo_strength   : hint_range(0.0, 1.0) = 0.25;
uniform float drift_speed     : hint_range(0.0, 0.2) = 0.02;  // slow swirl

// ── NOISE (Dave Hoskins hash + simplex + gradient/simplex fBm) ──────────────────
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
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }
float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
	vec2 i  = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz; x12.xy -= i1;
	i = mod289(i);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m; m = m * m;
	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x  = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}
float fbm(vec2 p, int oct) {
	float v = 0.0; float amp = 0.5; float norm = 0.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	p = rot * p;
	for (int k = 0; k < 8; k++) { if (k >= oct) { break; }
		v += amp * gnoise(p); norm += amp; p = rot * p * 2.0; amp *= 0.5; }
	return v / max(norm, 0.0001);
}
float fbm_s(vec2 p, int oct) {
	float v = 0.0; float amp = 0.5; float norm = 0.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	p = rot * p;
	for (int k = 0; k < 8; k++) { if (k >= oct) { break; }
		v += amp * (snoise(p) * 0.5 + 0.5); norm += amp; p = rot * p * 2.0; amp *= 0.5; }
	return v / max(norm, 0.0001);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;             // 0 centre → 1 at quad edge (axis)
	float ang = atan(p.y, p.x);
	float t = TIME * drift_speed;

	// Domain-warp the radius so the shell is an irregular wispy torus, not a smooth donut.
	vec2 sp = p * 3.0 + vec2(seed * 7.1, seed * 3.7);
	float warp = (fbm_s(sp + vec2(t, -t), 5) - 0.5) * turbulence;
	float rt = r + warp;

	// Main shell: gaussian band peaked at shell_radius.
	float d = (rt - shell_radius) / max(shell_thickness, 1e-3);
	float band = exp(-d * d);
	// Angular + radial wisps break the ring up.
	float wisp = fbm(vec2(ang * 2.5 + t * 2.0, rt * 4.0) + seed, 5);
	band *= 0.45 + 0.9 * wisp;

	// Bicolour across the shell: inner (hot) → outer (cool).
	float cmix = smoothstep(shell_radius - shell_thickness, shell_radius + shell_thickness, rt);
	vec3 shell_col = mix(inner_color, outer_color, cmix);

	// Central star + bloom in the cavity.
	float core = exp(-r * r / 0.0016) * star_brightness;
	float bloom = exp(-r * r / 0.02) * star_brightness * 0.4;
	vec3 star_col = vec3(1.0, 0.95, 0.85);

	// Eye look: faint gas filling the cavity + a darker pupil hugging the star.
	float fill = smoothstep(shell_radius, 0.0, rt) * (0.25 + 0.35 * fbm(p * 5.0 + seed + 11.0, 5));
	fill *= look;
	float pupil = 1.0 - look * (1.0 - smoothstep(0.04, 0.16, r)); // darken just outside the star
	vec3 fill_col = mix(inner_color, outer_color, 0.4);

	// Faint outer halo.
	float halo = exp(-pow(max(rt - shell_radius, 0.0) / (shell_thickness * 3.0), 2.0)) * halo_strength;

	vec3 col = shell_col * band
		+ fill_col * fill * pupil
		+ shell_col * halo * 0.5
		+ star_col * (core + bloom);

	float alpha = clamp(band * 1.2 + fill * pupil + halo + core + bloom, 0.0, 1.0);
	// Hard-clip outside the quad disc so corners stay transparent.
	alpha *= 1.0 - smoothstep(0.96, 1.05, r);
	COLOR = vec4(col, alpha) * COLOR.a;
}
