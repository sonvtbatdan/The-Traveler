shader_type canvas_item;
// Reflection nebula on a centered quad (Sprite2D, UV 0..1): a bright star embedded in gas it lights blue.
// An fbm gas cloud whose brightness falls off radially from the (possibly off-centre) star — brightest
// hugging the star, fading to soft irregular edges. Blue tint (blue scatters most). Noise helpers copied
// from nebula_bg.gdshader.

// ── TUNABLES ───────────────────────────────────────────────────────────────────
uniform float seed            = 0.0;
uniform float star_brightness : hint_range(0.0, 5.0) = 2.2;
uniform vec2  star_offset     = vec2(0.0, 0.0);            // star position relative to centre (-0.4..0.4)
uniform float cloud_size      : hint_range(0.2, 1.2) = 0.7;
uniform vec3  tint_color : source_color = vec3(0.35, 0.55, 1.0); // reflection blue
uniform float falloff_rate    : hint_range(0.5, 6.0) = 2.4; // higher = tighter glow around the star
uniform float turbulence      : hint_range(0.0, 1.0) = 0.5;
uniform float drift_speed     : hint_range(0.0, 0.2) = 0.015;

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

void fragment() {
	vec2 p = UV - 0.5;
	float t = TIME * drift_speed;

	// Distance from the (off-centre) star.
	vec2 d = p - star_offset * 0.5;
	float dist = length(d) * 2.0;

	// Domain-warped fbm cloud.
	vec2 wp = p * 3.0 + vec2(seed * 5.3, seed * 2.1);
	vec2 q = vec2(fbm(wp + vec2(t, 0.0), 5), fbm(wp + vec2(1.7, 9.2) - vec2(0.0, t), 5));
	float cloud = fbm(wp + turbulence * 2.0 * q, 6);

	// Radial falloff from the star (brightest hugging it).
	float fall = exp(-dist * falloff_rate / max(cloud_size, 1e-3));
	float density = cloud * fall;
	density = smoothstep(0.04, 0.5, density);

	// Bright star point + bloom.
	float core = exp(-dist * dist / 0.0012) * star_brightness;
	float bloom = exp(-dist * dist / 0.03) * star_brightness * 0.35;
	vec3 star_col = vec3(0.85, 0.92, 1.0);

	vec3 col = tint_color * density * (0.6 + 0.8 * cloud) + star_col * (core + bloom);
	float alpha = clamp(density + core + bloom, 0.0, 1.0);
	alpha *= 1.0 - smoothstep(0.96, 1.1, length(p) * 2.0);
	COLOR = vec4(col, alpha);
}
