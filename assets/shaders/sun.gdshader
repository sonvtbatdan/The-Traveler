shader_type canvas_item;
// A star/sun on a centered quad (Sprite2D, UV 0..1): a big bright disc with fbm surface churn (granulation),
// limb darkening, a glowing corona that wisps outward, and a wide soft bloom. The central landmark of the
// authored solar system. Noise helpers copied from the structure/comet shaders.

// ── TUNABLES ────────────────────────────────────────────────────────────────────
uniform float disc_radius   : hint_range(0.1, 0.8) = 0.42;  // disc edge (0..1 of the quad half)
uniform vec3  core_color  : source_color = vec3(1.0, 0.95, 0.75);
uniform vec3  limb_color  : source_color = vec3(1.0, 0.55, 0.15);
uniform vec3  corona_color: source_color = vec3(1.0, 0.45, 0.10);
uniform float corona_strength : hint_range(0.0, 2.0) = 0.9;
uniform float churn_speed   : hint_range(0.0, 1.0) = 0.12;
uniform float brightness    : hint_range(0.5, 4.0) = 1.6;
uniform float seed          = 0.0;

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

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;            // 0 centre → 1 quad edge
	float ang = atan(p.y, p.x);
	float t = TIME * churn_speed;

	// Surface granulation (churning fbm), domain-warped so it boils.
	vec2 sp = p * 5.0 + vec2(seed * 3.1, seed * 1.7);
	vec2 q = vec2(fbm(sp + vec2(t, 0.0), 5), fbm(sp + vec2(1.7, 9.2) - vec2(0.0, t), 5));
	float churn = fbm(sp + 1.3 * q, 6);

	// Disc body: hot core → cooler limb, modulated by granulation, with limb darkening at the edge.
	float body = 1.0 - smoothstep(disc_radius * 0.85, disc_radius, r);   // 1 inside → 0 at the rim
	vec3 surf = mix(core_color, limb_color, smoothstep(0.0, disc_radius, r));
	surf *= 0.75 + 0.5 * churn;                                          // bright/dark granules
	surf *= mix(1.0, 0.6, smoothstep(disc_radius * 0.6, disc_radius, r)); // limb darkening

	// Corona: glow beyond the disc, wispy (angular + radial fbm), exp falloff.
	float wisp = fbm(vec2(ang * 3.0 + t * 2.0, r * 3.0) + seed, 5);
	float corona = exp(-pow(max(r - disc_radius, 0.0) / 0.22, 2.0)) * (0.5 + 0.9 * wisp) * corona_strength;
	// Wide soft bloom.
	float bloom = exp(-r * r / 0.5) * 0.35;

	vec3 col = surf * body * brightness
		+ corona_color * corona
		+ core_color * bloom;

	float alpha = clamp(body + corona + bloom, 0.0, 1.0);
	alpha *= 1.0 - smoothstep(0.97, 1.06, r);   // keep the quad corners transparent
	COLOR = vec4(col, alpha);
}
