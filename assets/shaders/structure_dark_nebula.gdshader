shader_type canvas_item;
// Dark nebula on a centered quad (Sprite2D, UV 0..1): opaque dust that HIDES the stars behind it.
// alpha = dust density (dense centre → high alpha + near-black; edges → transparent, soft gradual fade).
// Polish: a faint warm-brown backlit rim, and a few foreground stars drawn on top for depth.
// Drawn at z above the background star field so it occludes it. Noise helpers from nebula_bg.gdshader.

// ── TUNABLES ───────────────────────────────────────────────────────────────────
uniform float seed          = 0.0;
uniform float darkness      : hint_range(0.0, 1.0) = 0.85;  // how black the dust gets
uniform float max_opacity   : hint_range(0.0, 1.0) = 0.96;  // peak alpha (occlusion strength)
uniform float size          : hint_range(0.3, 1.1) = 0.8;   // blob radius (0..1 of quad)
uniform float edge_softness : hint_range(0.05, 0.9) = 0.55; // fraction of radius that fades out
uniform vec3  brown_tint : source_color = vec3(0.18, 0.10, 0.06); // dust hue (warm brown)
uniform float fg_star_count : hint_range(0.0, 1.0) = 0.10;  // foreground-star density
uniform vec3  rim_color  : source_color = vec3(0.45, 0.22, 0.10); // backlit warm rim
uniform float rim_strength  : hint_range(0.0, 1.0) = 0.30;
uniform float drift_speed   : hint_range(0.0, 0.2) = 0.01;

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

// One foreground star per cell (sharp, drawn on top of the dust).
float fg_stars(vec2 p, float density, out float bright) {
	vec2 cell = floor(p); vec2 f = fract(p);
	bright = 0.0;
	float h = hash(cell + seed * 3.0);
	if (h > density) { return 0.0; }
	vec2 c = vec2(hash(cell + 1.7), hash(cell + 4.1));
	float dst = distance(f, c);
	bright = 0.5 + 0.5 * hash(cell + 9.9);
	return (1.0 - smoothstep(0.0, 0.07, dst)) * bright;
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float t = TIME * drift_speed;

	// Domain-warped blobby dust shape.
	vec2 wp = p * 2.6 + vec2(seed * 6.7, seed * 2.9);
	vec2 q = vec2(fbm(wp + vec2(t, 0.0), 5), fbm(wp + vec2(5.2, 1.3) - vec2(0.0, t), 5));
	float blob = fbm(wp + 1.4 * q, 6);

	// Radial confinement → soft gradual edge.
	float radial = 1.0 - smoothstep(size * (1.0 - edge_softness), size, r);
	float density = clamp(blob * radial * 1.8 - 0.2, 0.0, 1.0);

	// Dust colour: denser = darker (toward black).
	vec3 dust = brown_tint * (1.0 - darkness * density) * (1.0 - 0.6 * density);

	// Backlit warm rim: peaks at the blob's mid-density transition band.
	float rim = density * (1.0 - density) * 4.0;
	dust += rim_color * rim * rim_strength;

	// Foreground stars on top.
	float sb;
	float st = fg_stars(p * 14.0, fg_star_count, sb);
	vec3 star_col = mix(vec3(1.0, 0.85, 0.7), vec3(0.8, 0.88, 1.0), hash(floor(p * 14.0) + 2.3));

	float alpha = clamp(density * max_opacity + st, 0.0, 1.0);
	vec3 col = dust + star_col * st;
	alpha *= 1.0 - smoothstep(0.97, 1.1, r);
	COLOR = vec4(col, alpha);
}
