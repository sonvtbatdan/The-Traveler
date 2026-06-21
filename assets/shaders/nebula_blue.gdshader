shader_type canvas_item;
// "background_blue" — a vivid, structured teal-green + purple/violet nebula with sharp filaments, spiral
// galaxies and bright star clusters (à la the reference). Same infinite world-offset scroll as the other
// backgrounds. Gradient noise + domain warp + RIDGED noise for structure; full-res + dither (no banding).

uniform vec2  world_offset    = vec2(0.0);
uniform int   octaves         : hint_range(1, 8) = 6;
uniform float base_scale      = 2.4;
uniform float time_drift      = 0.005;
uniform float warp_strength   = 3.2;
uniform float ridged_amount   : hint_range(0.0, 1.0) = 0.55;   //how sharp/filamentary the structure is
uniform float region_scale    = 0.45;                          //teal↔violet region size
uniform float coverage        : hint_range(0.0, 1.0) = 0.42;
uniform float gas_brightness  : hint_range(0.0, 4.0) = 2.4;
uniform float gas_opacity     : hint_range(0.0, 3.0) = 1.5;
uniform float contrast        : hint_range(0.5, 3.0) = 1.2;
uniform float exposure        : hint_range(0.1, 3.0) = 1.1;
uniform float core_threshold  : hint_range(0.0, 1.0) = 0.74;
uniform float core_intensity  = 2.4;
uniform float star_density    : hint_range(0.0, 1.0) = 0.10;   //dense pinpoint stars
uniform float star_brightness = 0.9;
uniform float bright_star_density : hint_range(0.0, 1.0) = 0.12;
uniform float bright_star_scale   = 2.4;
uniform float galaxy_rarity   : hint_range(0.0, 1.0) = 0.06;   //spiral galaxies (sparse)
uniform float galaxy_cell     = 1.6;
uniform float galaxy_size     = 0.34;
uniform float galaxy_intensity = 1.3;
uniform float cluster_rarity  : hint_range(0.0, 1.0) = 0.08;
uniform float cluster_cell    = 1.1;
uniform float cluster_size    = 0.10;
uniform float cluster_intensity = 1.5;

uniform vec3 col_void   : source_color = vec3(0.02, 0.03, 0.10);  //deep navy void
uniform vec3 teal_lo    : source_color = vec3(0.03, 0.20, 0.22);  //teal ramp
uniform vec3 teal_mid   : source_color = vec3(0.10, 0.78, 0.66);
uniform vec3 teal_hi    : source_color = vec3(0.70, 1.00, 0.92);
uniform vec3 violet_lo  : source_color = vec3(0.12, 0.08, 0.34);  //violet ramp
uniform vec3 violet_mid : source_color = vec3(0.48, 0.20, 0.82);
uniform vec3 violet_hi  : source_color = vec3(0.88, 0.42, 0.95);
uniform vec3 col_core   : source_color = vec3(0.78, 0.96, 1.00);  //blue-white hot cores
uniform vec3 galaxy_color  : source_color = vec3(0.65, 0.95, 1.00);
uniform vec3 cluster_color : source_color = vec3(0.70, 0.90, 1.00);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

// ── Simplex noise (Ashima/Gustavson) — triangular lattice → NO square-grid straight contours. ──
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }
float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
	vec2 i  = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
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
	return 130.0 * dot(m, g);   // ~[-1, 1]
}
float fbm(vec2 p, int oct) {
	float v = 0.0; float amp = 0.5; float norm = 0.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	p = rot * p;
	for (int k = 0; k < 8; k++) {
		if (k >= oct) { break; }
		v += amp * (snoise(p) * 0.5 + 0.5); norm += amp; p = rot * p * 2.0; amp *= 0.5;
	}
	return v / max(norm, 0.0001);
}
// Ridged fBm: sharp snaking filaments (1 - |2n-1|), powered.
float fbm_ridged(vec2 p, int oct) {
	float n = fbm(p, oct);
	float r = 1.0 - abs(2.0 * n - 1.0);
	return pow(clamp(r, 0.0, 1.0), 1.2);   // softer ridges (less sharp cusps)
}
vec3 ramp3(vec3 lo, vec3 mid, vec3 hi, float x) {
	x = clamp(x, 0.0, 1.0);
	return (x < 0.5) ? mix(lo, mid, smoothstep(0.0, 1.0, x / 0.5))
	                 : mix(mid, hi, smoothstep(0.0, 1.0, (x - 0.5) / 0.5));
}

float stars(vec2 p, float density, out float tint) {
	vec2 cell = floor(p); vec2 f = fract(p);
	float h = hash(cell); tint = hash(cell + 7.3);
	if (h > density) { return 0.0; }
	vec2 c = vec2(hash(cell + 1.7), hash(cell + 4.1));
	float b = (1.0 - smoothstep(0.0, 0.10, distance(f, c)));
	return b * (0.4 + 0.6 * hash(cell + 9.9));
}
// Bright cross-flare stars (blue/teal/white), 3×3 so glow bleeds.
vec3 bright_stars(vec2 p) {
	vec3 acc = vec3(0.0); vec2 cell = floor(p); vec2 f = fract(p);
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 c = cell + vec2(float(xx), float(yy));
			if (hash(c + 31.7) > bright_star_density) { continue; }
			vec2 d = f - (vec2(float(xx), float(yy)) + vec2(hash(c + 1.3), hash(c + 5.9)));
			float dist = length(d);
			float core = exp(-dist * dist / 0.0005);
			float halo = exp(-dist * dist / 0.02);
			float ht = hash(c + 8.2);
			vec3 sc = (ht < 0.4) ? vec3(0.6, 0.9, 1.0) : ((ht < 0.7) ? vec3(0.5, 1.0, 0.85) : vec3(1.0, 1.0, 1.0));
			acc += sc * (core * 1.3 + halo * 0.4);
		}
	}
	return acc;
}
// Sparse spiral galaxies: 2-arm log spiral + bright core, 3×3 for glow bleed.
vec3 galaxies(vec2 p) {
	vec3 acc = vec3(0.0);
	vec2 cell = floor(p / galaxy_cell);
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 c = cell + vec2(float(xx), float(yy));
			if (hash(c + 51.2) > galaxy_rarity) { continue; }
			vec2 center = (c + vec2(0.25 + 0.5 * hash(c + 2.1), 0.25 + 0.5 * hash(c + 6.4))) * galaxy_cell;
			vec2 d = p - center;
			float r = length(d);
			if (r > galaxy_size * 1.6) { continue; }
			float ang = atan(d.y, d.x) + hash(c + 3.9) * 6.2831853;
			float spin = (hash(c + 4.4) < 0.5) ? 1.0 : -1.0;
			float arm = pow(max(cos(2.0 * ang - spin * 6.0 * log(max(r, 0.001))), 0.0), 6.0);
			float radial = exp(-r * r / (galaxy_size * galaxy_size));
			float core = exp(-r * r / (galaxy_size * galaxy_size * 0.03));
			acc += galaxy_color * ((arm * radial * 0.7 + core) * galaxy_intensity);
		}
	}
	return acc;
}
// Bright blue-white star clusters: soft glow + a dense sprinkle of stars.
vec3 clusters(vec2 p) {
	vec3 acc = vec3(0.0);
	vec2 cell = floor(p / cluster_cell);
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 c = cell + vec2(float(xx), float(yy));
			if (hash(c + 71.9) > cluster_rarity) { continue; }
			vec2 center = (c + vec2(0.25 + 0.5 * hash(c + 1.1), 0.25 + 0.5 * hash(c + 8.8))) * cluster_cell;
			float r = distance(p, center);
			float glow = exp(-r * r / (cluster_size * cluster_size));
			float tint;
			float spark = stars((p - center) * 90.0 + 200.0, 0.5, tint) * smoothstep(cluster_size, 0.0, r);
			acc += cluster_color * (glow * 0.5 + spark) * cluster_intensity;
		}
	}
	return acc;
}

void fragment() {
	vec2 t = vec2(TIME * time_drift);
	vec2 p = UV * base_scale + world_offset + t;

	// Domain-warped density (one gentle iteration — simplex already kills the grid lines).
	vec2 q = vec2(fbm(p, octaves), fbm(p + vec2(5.2, 1.3), octaves));
	vec2 r = vec2(fbm(p + warp_strength * q + vec2(1.7, 9.2), octaves),
	              fbm(p + warp_strength * q + vec2(8.3, 2.8), octaves));
	vec2 wp = p + warp_strength * r;
	float dens = fbm(wp, octaves);
	float rid = fbm_ridged(wp * 1.25, octaves);
	float structure = mix(dens, rid, ridged_amount);

	float big = fbm(wp * 0.6 + 50.0, max(octaves - 1, 5));
	float cloud = smoothstep(coverage, coverage + 0.6, structure) * (0.4 + 0.6 * big);

	// Teal regions threading through violet flanks — domain-warped so the boundary SNAKES (no straight diagonal).
	float hue = smoothstep(0.30, 0.70, fbm(p * region_scale + (r - 0.5) * 2.5 + 500.0, max(octaves - 1, 5)));
	float gi = clamp(structure, 0.0, 1.0);
	vec3 base = mix(ramp3(violet_lo, violet_mid, violet_hi, gi), ramp3(teal_lo, teal_mid, teal_hi, gi), hue);

	vec3 col = mix(col_void, base * gas_brightness, clamp(cloud * gas_opacity, 0.0, 1.0));
	col += col_core * smoothstep(core_threshold, 1.0, structure) * cloud * core_intensity;

	col = pow(max(col, vec3(0.0)) * exposure, vec3(contrast));

	float tintA;
	col += mix(vec3(1.0), vec3(0.7, 0.95, 1.0), tintA = hash(floor(p * 6.0) + 7.3))
	     * stars(p * 6.0, star_density, tintA) * star_brightness;
	col += bright_stars(p * bright_star_scale);
	col += galaxies(p);
	col += clusters(p);

	float d1 = hash(UV * 1973.0 + t);
	float d2 = hash(UV * 2671.0 - t);
	col += (d1 + d2 - 1.0) * 1.5 / 255.0;

	COLOR = vec4(col, 1.0);
}
