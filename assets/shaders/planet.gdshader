shader_type canvas_item;
// Procedural spherical planet on a quad (Sprite2D, UV 0..1). Shared sphere shading (discÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢normal,
// terminator day/night, atmospheric rim, slow spin) for all types, then branch on planet_type for the
// surface: 0 rocky, 1 gas giant, 2 ice, 3 Earth-like, 4 lava, 5 desert/Mars, 6 ringed gas giant.
// Surface noise uses SIMPLEX (no square-grid weave). planet_radius (ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°Ãƒâ€šÃ‚Â¤1) = fraction of the quad the sphere
// fills (1.0 normally; <1 for the ringed type so the ring has room).

uniform int   planet_type        = 0;
uniform float planet_radius      = 1.0;
uniform vec3  light_dir           = vec3(0.6, -0.5, 0.6);
uniform float terminator_softness : hint_range(0.01, 1.0) = 0.35;
uniform float ambient             = 0.06;
uniform float rotation_speed      = 0.05;
uniform float seed                = 0.0;
uniform vec3  atmo_color : source_color = vec3(0.6, 0.7, 1.0);
uniform float atmo_strength = 0.6;
uniform float atmo_power    = 3.0;

// rocky
uniform vec3  base_color  : source_color = vec3(0.45, 0.40, 0.34);
uniform vec3  base_color2 : source_color = vec3(0.30, 0.26, 0.22);
uniform float crater_density : hint_range(0.0, 1.0) = 0.5;
uniform float crater_depth   : hint_range(0.0, 1.0) = 0.55;   // interior bowl darkening
uniform float crater_rim     : hint_range(0.0, 1.0) = 0.3;    // lit-rim strength
uniform float maria_coverage : hint_range(0.0, 1.0) = 0.45;   // fraction of disc that becomes dark maria
uniform float maria_darkness : hint_range(0.0, 1.0) = 0.5;    // how much darker the maria plains get
uniform float crater_rays    : hint_range(0.0, 1.0) = 0.6;    // ejecta-ray intensity (Tycho-like)
uniform float crater_ray_rarity : hint_range(0.0, 1.0) = 0.15; // fraction of big craters that get rays
uniform float crater_ray_soft   : hint_range(1.0, 8.0) = 3.0;  // ray softness (higher = softer/fainter)
uniform float surface_contrast : hint_range(0.5, 2.5) = 1.25; // darkÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢bright tone spread
// gas (also used by ringed)
uniform vec3  band_a : source_color = vec3(0.85, 0.78, 0.62);
uniform vec3  band_b : source_color = vec3(0.72, 0.50, 0.30);
uniform vec3  band_c : source_color = vec3(0.55, 0.35, 0.22);
uniform float storm_on : hint_range(0.0, 1.0) = 1.0;
uniform float band_count  = 13.0;     // more = thinner/more numerous bands
uniform float turbulence  = 0.5;      // band shear / wobble
// ice
uniform vec3  ice_color : source_color = vec3(0.86, 0.92, 1.0);
uniform vec3  ice_tint  : source_color = vec3(0.55, 0.72, 0.95);
uniform float crack_intensity : hint_range(0.0, 1.0) = 0.6;
// earth
uniform float land_threshold : hint_range(0.0, 1.0) = 0.52;
uniform vec3  ocean_color : source_color = vec3(0.05, 0.20, 0.45);
uniform vec3  land_lo : source_color = vec3(0.14, 0.42, 0.17);
uniform vec3  land_hi : source_color = vec3(0.45, 0.38, 0.22);
uniform float cloud_amount = 0.5;
uniform float cloud_speed  = 0.04;
uniform float ice_cap_size : hint_range(0.0, 0.4) = 0.17;
// lava
uniform float crack_density : hint_range(0.0, 1.0) = 0.5;
uniform float crack_threshold : hint_range(0.0, 1.0) = 0.55;  // lower = more connected veins
uniform float vein_width : hint_range(0.02, 0.5) = 0.2;
uniform vec3  glow_lo  : source_color = vec3(0.5, 0.05, 0.0);
uniform vec3  glow_mid : source_color = vec3(1.0, 0.35, 0.0);
uniform vec3  glow_hi  : source_color = vec3(1.0, 0.9, 0.4);
uniform float glow_intensity = 1.6;
uniform vec3  crust_color : source_color = vec3(0.08, 0.06, 0.06);
// desert
uniform vec3  desert_lo : source_color = vec3(0.55, 0.30, 0.16);
uniform vec3  desert_hi : source_color = vec3(0.80, 0.58, 0.36);
uniform float canyon_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float cap_size : hint_range(0.0, 0.3) = 0.08;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.2;
// ocean / jungle (reuse earth uniforms above) + toxic / barren / carbon
uniform float cloud_storm : hint_range(0.0, 3.0) = 0.0;        // cloud swirl turbulence (ocean storms)
uniform float terrain_roughness : hint_range(0.0, 1.0) = 0.5;  // barren terrain detail strength
uniform vec3  carbon_lo : source_color = vec3(0.04, 0.04, 0.05);
uniform vec3  carbon_hi : source_color = vec3(0.10, 0.10, 0.13);
uniform vec3  sheen_color : source_color = vec3(0.45, 0.50, 0.65);
uniform float sheen_strength : hint_range(0.0, 1.5) = 0.5;
// ring (type 6)
uniform float ring_inner = 0.56;
uniform float ring_outer = 0.92;
uniform float ring_angle = 0.4;
uniform float ring_squash = 0.35;
uniform vec3  ring_color : source_color = vec3(0.80, 0.74, 0.60);
uniform float gap_pos = 0.74;
uniform float gap_width = 0.045;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Simplex noise (Ashima/Gustavson) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â organic, no square-grid weave. ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
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
float fbm(vec2 p) {
	float v = 0.0, amp = 0.5;
	for (int k = 0; k < 5; k++) { v += amp * (snoise(p) * 0.5 + 0.5); p *= 2.0; amp *= 0.5; }
	return v;
}
// Ridged ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ connected ridge/vein networks (peaks where snoise crosses 0).
float ridged(vec2 p) {
	float v = 0.0, amp = 0.5;
	for (int k = 0; k < 5; k++) { v += amp * (1.0 - abs(snoise(p))); p *= 2.0; amp *= 0.5; }
	return v;
}
// Worley returning (dist, offset-to-nearest-feature) so craters can be lit locally.
vec3 worley_off(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float md = 1.0; vec2 mo = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 3.7));
			vec2 d = g + o - f;
			float dist = length(d);
			if (dist < md) { md = dist; mo = d; }
		}
	}
	return vec3(md, mo);
}
// Worley variant returning (dist, offset-to-feature, feature-hash) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â the hash gates ejecta rays to a few
// "fresh" craters and varies crater freshness. Additive; used only by the rocky branch.
vec4 worley_h(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float md = 1.0; vec2 mo = vec2(0.0); float mh = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 3.7));
			vec2 d = g + o - f;
			float dist = length(d);
			if (dist < md) { md = dist; mo = d; mh = hash(i + g + 11.3); }
		}
	}
	return vec4(md, mo, mh);
}
// One power-law crater pass over a 3x3 cell neighborhood at `freq`. Most cells are empty (prob gate) and
// each crater has a jittered centre, a hash-varied radius (biased small) and a hash freshness driving
// depth / rim sharpness / rim brightness. Rays fire only from a rare fraction of big fresh craters and are
// soft + asymmetric. Accumulates into depress (max), rimlit (signed sum), rayadd (sum).
void crater_pass(vec2 sp, float freq, float prob, float rmin, float rmax, vec2 Ld, float so,
		float ray_rarity, float ray_soft, inout float depress, inout float rimlit, inout float rayadd) {
	vec2 P = sp * freq + so;
	vec2 i = floor(P); vec2 f = fract(P);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 cell = i + g;
			if (hash(cell + so * 0.7) > prob) { continue; }            // most cells empty -> gaps + clusters
			vec2 jit = vec2(hash(cell + 1.3), hash(cell + 7.7));
			vec2 d = g + jit - f;                                      // vector to crater centre (cell units)
			float dist = length(d);
			float hs = hash(cell + 3.1);
			float rad = mix(rmin, rmax, hs * hs);                      // power-law: bias toward small
			if (dist > rad * 2.8) { continue; }
			float hf = hash(cell + 5.5);                              // freshness 0..1
			float nd = dist / rad;
			float depth = mix(0.45, 1.0, hf);                        // fresh = deeper/darker bowl
			depress = max(depress, smoothstep(1.0, 0.0, nd) * depth);
			float rw = mix(0.34, 0.13, hf);                          // fresh = sharper rim
			float ring = smoothstep(1.0 - rw, 1.0, nd) * smoothstep(1.0 + rw, 1.0, nd);
			float lit = dot(normalize(d + vec2(0.0001)), Ld);
			rimlit += ring * (0.5 + hf) * lit;
			float rare = step(1.0 - ray_rarity, hf) * smoothstep(0.55, 0.9, hs);
			if (rare > 0.0 && nd > 1.0) {
				float ang = atan(d.y, d.x);
				float phase = hash(cell + 2.2) * 6.2831853;
				float nr = 3.0 + floor(hash(cell + 9.9) * 4.0);
				float lobe = 0.5 + 0.5 * sin(ang * nr + phase);
				lobe *= 0.6 + 0.4 * sin(ang * (nr * 0.41) - phase * 1.7);   // break symmetry
				lobe = pow(max(lobe, 0.0), ray_soft);
				float fall = smoothstep(rad * 2.6, rad, dist);              // fade outward from the rim
				rayadd += rare * lobe * fall;
			}
		}
	}
}

// Shared gas-giant surface (type 1 AND type 6): many bands of varying width, sheared + pole-compressed.
vec3 gas_surface(float lon, float lat) {
	float shear = (fbm(vec2(lon * 1.2, lat * 3.0) + seed * 2.0) - 0.5) * turbulence;
	float y = lat + shear;   // bands follow latitude ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ compress toward the poles
	float v = sin(y * band_count) + 0.5 * sin(y * band_count * 2.1 + 1.3) + 0.35 * sin(y * band_count * 0.6 - 0.7);
	v = v * 0.35 + 0.5;
	vec3 c = mix(band_a, band_b, smoothstep(0.25, 0.62, v));
	float dband = fbm(vec2(y * 2.0, lon * 0.3) + seed) * 0.5 + v * 0.5;
	c = mix(c, band_c, smoothstep(0.55, 0.85, dband));
	vec2 sc = vec2(0.6 + seed, -0.3);
	float spot = exp(-(pow((lon - sc.x) * 1.2, 2.0) + pow((lat - sc.y) * 3.0, 2.0)) * 6.0);
	c = mix(c, band_c * 1.2, spot * storm_on);
	return c;
}

// Shared Earth-like surface (ocean type 7, jungle type 9). Earth type 3 keeps its own inline copy.
// `storm` warps the cloud UV into spiral storm systems; cloud_scale/lo/hi shape coverage + wispiness.
vec3 earth_surface(vec2 sp, vec3 N, float lon, float lat, float cloud_scale, float cloud_lo, float cloud_hi, float storm) {
	float land = fbm(sp * 1.4 + seed) + (fbm(sp * 4.0 + seed * 3.0) - 0.5) * 0.12;
	float terr = fbm(sp * 3.0 + seed * 2.0);
	vec3 land_col = mix(land_lo, land_hi, terr);
	vec3 s = mix(ocean_color, land_col, smoothstep(land_threshold - 0.04, land_threshold + 0.04, land));
	float cap = smoothstep(1.0 - ice_cap_size, 1.0 - ice_cap_size * 0.4, abs(N.y));
	s = mix(s, vec3(0.95, 0.97, 1.0), cap);
	float clon = atan(N.x, N.z) + TIME * cloud_speed + seed * 3.0;
	vec2 cuv = vec2(clon, lat) * cloud_scale;
	vec2 cw = vec2(fbm(cuv * 0.5 + 11.0), fbm(cuv * 0.5 + 31.0)) - 0.5;
	cuv += cw * storm;                                       // swirl into spiral storms
	float cl = fbm(cuv + 30.0);
	float clouds = smoothstep(cloud_lo, cloud_hi, cl) * cloud_amount;
	s = mix(s, vec3(1.0), clouds);
	return s;
}

// Toxic / Venus haze (type 8): reuses the gas-giant fbm + turbulence + band_a/band_b colours, but drops
// the sin() bands -> thick uniform swirling soup with no band separation.
vec3 haze_surface(float lon, float lat) {
	float s1 = fbm(vec2(lon * 1.5, lat * 2.0) + seed * 2.0);
	float s2 = fbm(vec2(lon * 0.8, lat * 1.2) * 2.0 + seed * 5.0 + s1 * turbulence);
	float v = clamp(s1 * 0.5 + s2 * 0.6, 0.0, 1.0);
	return mix(band_a, band_b, v);                           // two close tones -> subtle mottle, no bands
}

void fragment() {
	vec2 pc = (UV - 0.5) * 2.0;
	vec2 sc = pc / max(planet_radius, 0.001);
	float sr2 = dot(sc, sc);
	bool in_sphere = sr2 <= 1.0;

	vec3 col = vec3(0.0);
	float alpha = 0.0;

	if (in_sphere) {
		float z = sqrt(max(1.0 - sr2, 0.0));
		vec3 N = normalize(vec3(sc, z));
		vec3 L = normalize(light_dir);
		float lon = atan(N.x, N.z) + TIME * rotation_speed + seed * 6.2831853;
		float lat = asin(clamp(N.y, -1.0, 1.0));
		vec2 sp = vec2(lon, lat);
		vec3 surf = base_color;
		vec3 emission = vec3(0.0);

		if (planet_type == 0) {
			// Rocky/moon: full-coverage craters everywhere (power-law sizes, jittered placement, per-crater
			// freshness, light-aware bowls). Gentle large-scale tonal drift replaces maria - no bald patches.
			vec2 Ld = normalize(L.xy + vec2(0.0001));   // light direction projected onto the surface
			surf = mix(base_color2, base_color, smoothstep(0.35, 0.75, fbm(sp * 3.0 + seed)));   // fine mottle everywhere
			float region = fbm(sp * 0.9 + seed);   // soft lighter/darker terrain regions (craters stay on top)
			surf *= mix(1.0 - maria_darkness * 0.4, 1.0 + maria_darkness * 0.15, smoothstep(maria_coverage - 0.15, maria_coverage + 0.15, region));
			// Craters: 4 power-law passes (few giant -> many tiny), jittered/overlapping, varied freshness.
			float depress = 0.0, rimlit = 0.0, rayadd = 0.0;
			float dprob = clamp(0.35 + 0.55 * crater_density, 0.0, 0.95);
			crater_pass(sp, 1.1,  dprob * 0.8,  0.28, 0.55, Ld, seed + 17.0,  crater_ray_rarity,       crater_ray_soft, depress, rimlit, rayadd);
			crater_pass(sp, 2.6,  dprob,        0.22, 0.46, Ld, seed + 41.0,  crater_ray_rarity * 0.5, crater_ray_soft, depress, rimlit, rayadd);
			crater_pass(sp, 5.5,  dprob,        0.18, 0.42, Ld, seed + 73.0,  0.0,                     crater_ray_soft, depress, rimlit, rayadd);
			crater_pass(sp, 11.0, dprob * 1.05, 0.16, 0.40, Ld, seed + 113.0, 0.0,                     crater_ray_soft, depress, rimlit, rayadd);
			surf *= 1.0 - clamp(depress, 0.0, 1.0) * crater_depth;          // full strength everywhere (no maria mask)
			surf += vec3(crater_rim) * clamp(rimlit, 0.0, 2.0);             // lit rims
			surf -= vec3(crater_rim * 0.6) * clamp(-rimlit, 0.0, 2.0);      // shadow rims
			surf += vec3(crater_rays) * rayadd;                             // soft ejecta on the rare fresh ones
			// 4 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Widen the value range so maria stay dark and rims/rays reach near-white.
			surf = clamp((surf - 0.5) * surface_contrast + 0.5, 0.0, 1.6);
		} else if (planet_type == 1) {
			surf = gas_surface(lon, lat);
		} else if (planet_type == 2) {
			surf = mix(ice_color, ice_tint, fbm(sp * 2.0 + seed) * 0.5);
			float cr = ridged(sp * (6.0 + 4.0 * crack_intensity) + seed * 5.0);
			float cracks = smoothstep(0.9, 1.0, cr);
			surf = mix(surf, ice_tint * 0.55, cracks * crack_intensity);
		} else if (planet_type == 3) {
			// Earth-like ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â big coherent continents (low-freq) + fine coastline + caps + drifting clouds.
			float land = fbm(sp * 1.4 + seed) + (fbm(sp * 4.0 + seed * 3.0) - 0.5) * 0.12;
			float terr = fbm(sp * 3.0 + seed * 2.0);
			vec3 land_col = mix(land_lo, land_hi, terr);
			surf = mix(ocean_color, land_col, smoothstep(land_threshold - 0.04, land_threshold + 0.04, land));
			float cap = smoothstep(1.0 - ice_cap_size, 1.0 - ice_cap_size * 0.4, abs(N.y));
			surf = mix(surf, vec3(0.95, 0.97, 1.0), cap);
			float clon = atan(N.x, N.z) + TIME * cloud_speed + seed * 3.0;
			float cl = fbm(vec2(clon, lat) * 3.0 + 30.0);
			float clouds = smoothstep(0.55, 0.78, cl) * cloud_amount;
			surf = mix(surf, vec3(1.0), clouds);
		} else if (planet_type == 4) {
			// Lava ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â connected ridged veins with a heat gradient; emissive (added after lighting).
			surf = crust_color;
			float cr = ridged(sp * (3.0 + 5.0 * crack_density) + seed * 4.0);
			float vein = smoothstep(crack_threshold, crack_threshold + vein_width, cr);
			float heat = smoothstep(crack_threshold, crack_threshold + 0.35, cr);
			vec3 glow = mix(glow_lo, glow_mid, smoothstep(0.0, 0.55, heat));
			glow = mix(glow, glow_hi, smoothstep(0.55, 1.0, heat));
			emission = glow * vein * glow_intensity;
		} else if (planet_type == 5) {
			// Desert/Mars ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â smooth isotropic mottling + faint irregular canyons (no waffle).
			float m = fbm(sp * 2.0 + seed);
			float m2 = fbm(sp * 4.5 + seed * 2.0);
			surf = mix(desert_lo, desert_hi, clamp(m * 0.7 + m2 * 0.3, 0.0, 1.0));
			float canyon = ridged(sp * 3.5 + seed * 3.0);
			surf *= 1.0 - smoothstep(0.70, 0.95, canyon) * canyon_intensity * 0.4;
			float cap = smoothstep(1.0 - cap_size, 1.0 - cap_size * 0.4, abs(N.y));
			surf = mix(surf, vec3(0.9, 0.9, 0.92), cap * 0.7);
			surf += desert_hi * dust_amount * 0.08;
		} else if (planet_type == 6) {
			surf = gas_surface(lon, lat);
		} else if (planet_type == 7) {
			// Ocean / water world (earth-like, high threshold -> mostly ocean; big storm clouds).
			surf = earth_surface(sp, N, lon, lat, 2.2, 0.42, 0.70, cloud_storm);
		} else if (planet_type == 8) {
			// Toxic / Venus-like: uniform sickly swirling haze, no bands.
			surf = haze_surface(lon, lat);
		} else if (planet_type == 9) {
			// Jungle / verdant (earth-like, low threshold -> mostly land; thin wispy clouds).
			surf = earth_surface(sp, N, lon, lat, 4.0, 0.62, 0.86, cloud_storm);
		} else if (planet_type == 10) {
			// Barren dead rock: muted grey-brown fbm mottle + faint ridges; no craters/water/rust.
			float m = fbm(sp * 2.5 + seed);
			float m2 = fbm(sp * (5.0 + 4.0 * terrain_roughness) + seed * 2.0);
			surf = mix(base_color2, base_color, clamp(m * 0.65 + m2 * 0.35, 0.0, 1.0));
			float ridge = ridged(sp * 4.0 + seed * 3.0);
			surf *= 1.0 - smoothstep(0.85, 1.05, ridge) * 0.12 * terrain_roughness;
		} else if (planet_type == 11) {
			// Carbon / obsidian: near-black charcoal + restrained metallic/bluish sheen on the lit side.
			float mc = fbm(sp * 3.0 + seed);
			surf = mix(carbon_lo, carbon_hi, mc * 0.5);
			vec3 V = vec3(0.0, 0.0, 1.0);
			vec3 H = normalize(L + V);
			surf += sheen_color * pow(max(dot(N, H), 0.0), 40.0) * sheen_strength;
		}

		float ndl = dot(N, L);
		float lit = smoothstep(-terminator_softness, terminator_softness, ndl);
		col = surf * (ambient + lit) + emission;
		float fres = pow(1.0 - z, atmo_power);
		col += atmo_color * atmo_strength * fres * smoothstep(-0.2, 0.5, ndl);
		alpha = smoothstep(1.0, 0.97, sr2);
	}

	// ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ Ring (type 6): near (front) arc draws over the planet, far arc is occluded by the sphere. ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬
	if (planet_type == 6) {
		float ca = cos(ring_angle), sa = sin(ring_angle);
		vec2 q = vec2(pc.x * ca - pc.y * sa, pc.x * sa + pc.y * ca);
		vec2 e = vec2(q.x, q.y / max(ring_squash, 0.05));
		float rr = length(e);
		float band = smoothstep(ring_inner, ring_inner + 0.02, rr) * smoothstep(ring_outer, ring_outer - 0.02, rr);
		float gap = 1.0 - (smoothstep(gap_pos - gap_width, gap_pos, rr) * smoothstep(gap_pos + gap_width, gap_pos, rr));
		float rtex = 0.7 + 0.3 * fbm(vec2(rr * 26.0, seed));
		float ra = band * gap * rtex;
		if (ra > 0.001) {
			vec3 rc = ring_color * (0.75 + 0.25 * rtex);
			bool front = q.y > 0.0;
			if (front) {
				float oa = ra + alpha * (1.0 - ra);
				col = (oa > 0.0) ? (rc * ra + col * alpha * (1.0 - ra)) / oa : vec3(0.0);
				alpha = oa;
			} else {
				float ta = alpha; vec3 tc = col;
				float ba = ra * 0.8; vec3 bc = rc * 0.55;
				float oa = ta + ba * (1.0 - ta);
				col = (oa > 0.0) ? (tc * ta + bc * ba * (1.0 - ta)) / oa : vec3(0.0);
				alpha = oa;
			}
		}
	}

	COLOR = vec4(col, alpha);
}
