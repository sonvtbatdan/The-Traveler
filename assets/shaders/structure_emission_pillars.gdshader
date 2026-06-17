shader_type canvas_item;
// Emission pillars (Pillars of Creation) on a centered quad (Sprite2D, UV 0..1): dense backlit gas columns.
// Anisotropic fbm + a column wave bias noise into upright fingers rising from a base; tops eroded.
// A backlight glow above/behind lights the column edges (bright rims) while the bodies stay dark/dense.
// A few baby stars near the tips. Noise helpers from nebula_bg.gdshader. NOTE: finicky — expect tuning.

// ── TUNABLES ───────────────────────────────────────────────────────────────────
uniform float seed            = 0.0;
uniform float column_count    : hint_range(1.0, 6.0) = 3.0;
uniform float column_width    : hint_range(0.0, 1.0) = 0.45;  // 0 thin · 1 fat
uniform float column_height   : hint_range(0.3, 1.0) = 0.85;
uniform float erosion         : hint_range(0.0, 1.5) = 0.7;
uniform vec2  backlight_dir   = vec2(0.0, -1.0);              // glow comes from above by default
uniform vec3  backlight_color : source_color = vec3(0.55, 0.7, 1.0); // cool back glow
uniform float rim_brightness  : hint_range(0.0, 2.0) = 1.0;
uniform vec3  gas_color : source_color = vec3(0.45, 0.28, 0.14); // warm brown/gold gas
uniform float baby_stars      : hint_range(0.0, 1.0) = 0.4;
uniform float drift_speed     : hint_range(0.0, 0.2) = 0.01;

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

// Gas density at (x in 0..1, yb in 0..1 where 0 = base/bottom, 1 = top).
float gas_density(float x, float yb, float t) {
	// Column wave: column_count lobes across x, wavered by low-freq noise → irregular placement.
	float warpx = (fbm(vec2(x * 2.0, yb * 1.2) + seed + t, 4) - 0.5) * 2.2;
	float colwave = 0.5 + 0.5 * cos(x * column_count * 6.28318530718 + warpx);
	float colmask = pow(colwave, mix(5.0, 1.4, column_width));
	// Vertical: rise from base, fade toward column_height.
	float vert = 1.0 - smoothstep(column_height * 0.45, column_height, yb);
	// Erode the tops irregularly.
	float etop = fbm(vec2(x * 9.0, yb * 5.0) + seed + 20.0, 5);
	vert *= 1.0 - smoothstep(0.2, 1.0, (yb / max(column_height, 1e-3)) * (0.5 + erosion * etop));
	float gas = colmask * vert;
	gas *= 0.65 + 0.7 * fbm(vec2(x * 5.0, yb * 3.0) + seed + 5.0, 5); // internal clumpiness
	return clamp(gas, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV;
	float x = uv.x;
	float yb = 1.0 - uv.y;          // 0 base (bottom) → 1 top
	float t = TIME * drift_speed;

	float gas = gas_density(x, yb, t);

	// Rim: sample density a step toward the backlight; lit where the body thins out facing the light.
	vec2 ld = normalize(backlight_dir + vec2(1e-5));
	float step_px = 0.02;
	float g_toward = gas_density(clamp(x + ld.x * step_px, 0.0, 1.0),
		clamp(yb - ld.y * step_px, 0.0, 1.0), t); // -ld.y: backlight_dir.y<0 (up) → sample higher yb
	float rim = clamp(gas - g_toward, 0.0, 1.0) * 6.0;
	rim *= smoothstep(0.15, 0.5, gas);

	float pillar = smoothstep(0.3, 0.6, gas);
	float halo = smoothstep(0.04, 0.35, gas);

	// Cool background glow, brighter toward the top/back, confined to gassy areas.
	vec3 backglow = backlight_color * (0.1 + 0.5 * pow(yb, 1.5)) * halo;

	// Baby stars near the tips (high yb, on a column).
	float star = 0.0;
	vec2 sc = floor(vec2(x, yb) * vec2(18.0, 26.0));
	if (hash(sc + seed) < baby_stars && yb > column_height * 0.45 && pillar > 0.2) {
		vec2 f = fract(vec2(x, yb) * vec2(18.0, 26.0));
		float dst = distance(f, vec2(hash(sc + 1.3), hash(sc + 4.7)));
		star = (1.0 - smoothstep(0.0, 0.12, dst)) * 1.4;
	}

	vec3 body = gas_color * (0.25 + 0.6 * gas);            // dark dense bodies
	vec3 col = body * pillar
		+ backlight_color * rim * rim_brightness
		+ backglow
		+ vec3(1.0, 0.95, 0.85) * star;

	float alpha = clamp(pillar + rim * 0.6 + halo * 0.35 + star, 0.0, 1.0);
	// Fade the quad's left/right/top edges so there's no rectangular silhouette.
	alpha *= smoothstep(0.0, 0.08, x) * smoothstep(1.0, 0.92, x);
	alpha *= smoothstep(1.0, 0.82, yb);
	COLOR = vec4(col, alpha);
}
