shader_type canvas_item;
// Infinite procedural nebula background. Deterministic in WORLD space: the script feeds
// world_offset = camera_world_pos * scroll_factor, so the same world location always renders the same gas
// (no boiling when backtracking) and it tiles infinitely. A slow time_drift keeps it alive at rest.
//
// Gradient (Perlin) noise + domain warp for soft turbulent gas. Living look:
//   • hue varies across space (warm red/orange/gold regions ↔ cool indigo/blue/cyan-white) via a slow field
//   • glowing near-white emission CORES where the gas is densest
//   • HDR-ish contrast/exposure curve → true black voids to bright cores (not flat midtone fog)
//   • two-tier stars: many tiny pinpoints + a few big colored stars with soft bloom + 4-point cross-flare
// Anti-faceting: many octaves on every field (so no single linear-gradient octave dominates), gentle
// remaps, moderate warp, and output dither — together these remove the straight/triangular edges.

uniform vec2  world_offset    = vec2(0.0);   // camera world pos × scroll_factor (fed each frame)
uniform int   octaves         : hint_range(1, 8) = 6;        // enough that contours stay CURVY (no facets)
uniform float base_scale      = 2.0;        // lower = bigger, softer billows (smoothness comes from here)
uniform float time_drift      = 0.005;
uniform float warp_strength    = 3.0;        // domain-warp amount (lower → fewer fold streaks)
uniform float cloud_coverage  : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_softness  : hint_range(0.0, 1.0) = 0.45; // blends density toward its low-freq form (blur)
// Coverage fade band around cloud_coverage — wide = gas ramps in over a long density range (no defined
// silhouette onset). Lower = density where gas starts to appear; hi = where it reaches full.
uniform float cov_fade_lo     : hint_range(0.0, 0.5) = 0.15;
uniform float cov_fade_hi     : hint_range(0.1, 1.0) = 0.6;
uniform float brightness      : hint_range(0.0, 2.0) = 0.9;
uniform float gas_brightness  : hint_range(0.0, 4.0) = 2.2;  // gas is the HERO — much brighter than before
uniform float gas_opacity     : hint_range(0.0, 3.0) = 1.6;  // how opaquely gas overrides the void

// Heatmap brightness variation (smooth clusters of similar "temperature").
uniform float bright_var_min  = 0.35;
uniform float bright_var_max  = 2.4;
uniform float bright_var_scale = 0.5;

// HDR tone curve.
uniform float contrast        : hint_range(0.5, 3.0) = 1.6;
uniform float exposure        : hint_range(0.1, 3.0) = 1.15;

// Glowing cores.
uniform float core_threshold  : hint_range(0.0, 1.0) = 0.78;
uniform float core_intensity  = 2.2;

// Stars: tier A (tiny pinpoints) + tier B (big bright bloom/flare).
uniform float star_density        : hint_range(0.0, 1.0) = 0.07;
uniform float star_brightness     = 0.4;     // faint pinprick texture
uniform float bright_star_density : hint_range(0.0, 1.0) = 0.07;  // total bright stars (mostly small)
uniform float bright_star_scale   = 2.2;     // tiles of the bright-star grid across the screen (low = few)
uniform float big_star_rarity     : hint_range(0.0, 1.0) = 0.10;  // fraction that are big/showy (~2-3 on screen)
uniform float halo_size           = 0.16;    // soft halo radius (cell units)
uniform float max_flare           = 0.5;     // max cross-flare arm length (cell units)
uniform float bloom_strength      = 0.6;     // how much colored light bleeds into the surrounding gas
uniform float starw_blue          = 0.18;    // colour weights (white = remainder)
uniform float starw_gold          = 0.12;
uniform float starw_red           = 0.05;
uniform float flaremix_none       = 1.0;     // flare-shape mix: none / 4-point / 6-point (default = all none)
uniform float flaremix_four       = 0.0;
uniform float bright_star_brightness = 0.5;  // turned DOWN — stars are quiet texture, gas is the drama
uniform float star_size_mult      = 0.6;     // shrinks bright-star core + halo
uniform float bloom_mult          = 0.4;     // cuts bright-star gas-bleed

// ── Macro "biome" regions: a very low-frequency field (one cycle spans many screens) that decides what
// kind of space you're in — empty void vs dense bright nebula — and drives density, colour and stars. ──
uniform float biome_scale       = 0.05;   // SMALL = huge regions (one cycle ≈ many screen-widths)
uniform float biome_warp        = 1.2;    // medium-freq domain warp → region boundaries SNAKE (no straight edges)
uniform float void_threshold    : hint_range(0.0, 1.0) = 0.35;  // below → empty void
uniform float dense_threshold   : hint_range(0.0, 1.0) = 0.72;  // above → dense nebula (wide band = soft fade)
uniform float cluster_strength  = 2.2;    // star-density multiplier in dense regions (clusters)
uniform float region_color_scale = 0.07;  // slow field for the dominant region hue (big colour blocks)
// Rare landmarks: occasional unmistakable features (huge nebula core + giant star).
uniform float landmark_scale    = 0.8;    // coarse grid (low = big, far-apart landmarks)
uniform float landmark_rarity   : hint_range(0.0, 1.0) = 0.05;  // fraction of coarse cells with a landmark
uniform float landmark_size     = 0.35;   // nebula-core glow radius (cell units)
uniform float landmark_intensity = 1.6;

uniform vec3 col_void   : source_color = vec3(0.012, 0.012, 0.03);  // near-black navy void
// Warm ramp (deep red → orange → gold).
uniform vec3 warm_lo : source_color = vec3(0.32, 0.05, 0.06);
uniform vec3 warm_mid: source_color = vec3(0.85, 0.30, 0.10);
uniform vec3 warm_hi : source_color = vec3(1.00, 0.78, 0.42);
// Cool ramp (indigo → blue → cyan-white).
uniform vec3 cool_lo : source_color = vec3(0.10, 0.10, 0.34);
uniform vec3 cool_mid: source_color = vec3(0.18, 0.34, 0.78);
uniform vec3 cool_hi : source_color = vec3(0.70, 0.92, 1.00);
uniform vec3 core_color : source_color = vec3(1.00, 0.95, 0.88);   // hot emission tint

// Precision-stable hash (Dave Hoskins). The old sin(dot(p,k))*43758 form lost float32 precision at the
// large sample coordinates this nebula uses (world_offset += _spawn_offset up to ±2000, plus +900/+500
// per-field offsets) → its level sets printed as straight diagonal seams. This works on fractional parts
// (×~0.1, not ×43758) so it stays well-distributed and seam-free into the thousands.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 grad(vec2 ip) {
	float a = hash(ip) * 6.28318530718;
	return vec2(cos(a), sin(a));
}

// 2D gradient (Perlin) noise with quintic fade, remapped to 0..1.
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	float n = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
	return n * 0.5 + 0.5;
}

// Simplex noise (Ashima/Gustavson) — triangular lattice, so NO square-grid straight facets like gradient
// noise has. fbm uses this now: the low-frequency macro fields (biome/hue/heat) were printing the gradient
// lattice as straight diagonal flat panels; simplex removes them at the source. Returns ~[-1, 1].
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

// fBm: sum octaves, freq ×2 / amp ×0.5, each octave rotated.
float fbm(vec2 p, int oct) {
	float v = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	p = rot * p;
	for (int k = 0; k < 8; k++) {
		if (k >= oct) { break; }
		v += amp * (snoise(p) * 0.5 + 0.5);   // background_test: ALL fields simplex → no square-grid facets anywhere
		norm += amp;
		p = rot * p * 2.0;
		amp *= 0.5;
	}
	return v / max(norm, 0.0001);
}

// Simplex fBm — used ONLY for the low-frequency macro fields (biome / region hue / brightness heatmap).
// Those are sampled at very low frequency with few octaves, where gradient noise's square lattice printed
// as straight diagonal facet panels. Simplex (triangular lattice) has no such grid → curvy at every scale.
// The high-frequency cloud detail (q/r/dens/big) stays on the softer gradient fbm above.
float fbm_s(vec2 p, int oct) {
	float v = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	p = rot * p;
	for (int k = 0; k < 8; k++) {
		if (k >= oct) { break; }
		v += amp * (snoise(p) * 0.5 + 0.5);
		norm += amp;
		p = rot * p * 2.0;
		amp *= 0.5;
	}
	return v / max(norm, 0.0001);
}

// Warm ramp: deep red → orange → gold (x = local intensity 0..1).
vec3 warm_ramp(float x) {
	x = clamp(x, 0.0, 1.0);
	if (x < 0.5) { return mix(warm_lo, warm_mid, smoothstep(0.0, 1.0, x / 0.5)); }
	return mix(warm_mid, warm_hi, smoothstep(0.0, 1.0, (x - 0.5) / 0.5));
}

// Cool ramp: indigo → blue → cyan-white.
vec3 cool_ramp(float x) {
	x = clamp(x, 0.0, 1.0);
	if (x < 0.5) { return mix(cool_lo, cool_mid, smoothstep(0.0, 1.0, x / 0.5)); }
	return mix(cool_mid, cool_hi, smoothstep(0.0, 1.0, (x - 0.5) / 0.5));
}

// Tier-A: sparse tiny pinpoint stars.
float stars(vec2 p, float density, out float tint) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash(cell);
	tint = hash(cell + 7.3);
	if (h > density) { return 0.0; }
	vec2 c = vec2(hash(cell + 1.7), hash(cell + 4.1));
	float dst = distance(f, c);
	float bright = (1.0 - smoothstep(0.0, 0.10, dst));
	bright *= 0.4 + 0.6 * hash(cell + 9.9);
	return bright;
}

// Weighted star colour: mostly pale-white, a minority blue-white & gold, a rare red/magenta.
vec3 star_color(float h) {
	if (h < starw_red) { return vec3(1.0, 0.38, 0.46); }                       // rare red/magenta
	if (h < starw_red + starw_gold) { return vec3(1.0, 0.80, 0.45); }          // gold/amber
	if (h < starw_red + starw_gold + starw_blue) { return vec3(0.68, 0.82, 1.0); } // blue-white
	return vec3(1.0, 0.97, 0.93);                                              // pale white (majority)
}

// Tier-B: bright stars, summed over a 3×3 neighbourhood so glow bleeds across cells into the gas.
// Every star hashes INDEPENDENT, CORRELATED properties (magnitude → size/brightness/flare/halo), a
// weighted colour, a per-star flare shape (none / 4-point / 6-point) and a random rotation → no two alike.
vec3 bright_stars(vec2 p, float density) {
	vec3 acc = vec3(0.0);
	vec2 cell = floor(p);
	vec2 f = fract(p);
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 oc = vec2(float(xx), float(yy));
			vec2 c = cell + oc;
			if (hash(c + 31.7) > density) { continue; }
			vec2 sc = oc + vec2(hash(c + 1.3), hash(c + 5.9));   // star centre relative to this cell
			vec2 d = f - sc;
			float dist = length(d);

			// Correlated per-star magnitude: big stars are larger + brighter + (optionally) flared.
			float m   = hash(c + 2.1);
			float big = step(hash(c + 6.7), big_star_rarity);
			float sz  = mix(mix(0.4, 0.9, m), mix(1.1, 1.9, m), big) * star_size_mult;   // size
			float pk  = mix(mix(0.2, 0.6, m), mix(0.9, 1.5, m), big);   // peak brightness
			float fl  = mix(mix(0.0, 0.18, m), mix(0.55, 1.0, m), big) * max_flare;
			float ha  = mix(mix(0.4, 0.8, m), mix(1.0, 1.5, m), big) * halo_size * star_size_mult;

			// Sharp core + soft GAUSSIAN halo + a slightly wider gaussian gas-bleed. Gaussians fall to ~0
			// well within one cell, so nothing is clipped at the 3×3 edge → NO square boxes around stars.
			float core = exp(-dist * dist / max(0.0004 * sz * sz, 1e-6));
			float halo = exp(-dist * dist / max(ha * ha, 1e-5));
			float gas  = exp(-dist * dist / max(ha * ha * 4.0, 1e-5));   // soft bleed into the gas (contained)

			// Per-star flare: shape (none / 4-pt / 6-pt) + random rotation. Default mix = all "none".
			float fsel = hash(c + 12.4);
			float points = (fsel < flaremix_none) ? 0.0 : ((fsel < flaremix_none + flaremix_four) ? 4.0 : 6.0);
			float ang = atan(d.y, d.x) + hash(c + 3.3) * 6.28318530718;
			float spike = (points < 1.0) ? 0.0 : pow(abs(cos(ang * points * 0.5)), 22.0);
			float flareI = (fl > 0.001) ? spike * exp(-dist / max(fl, 1e-3)) : 0.0;

			vec3 scol = star_color(hash(c + 8.2));
			float inten = core * 1.4 + halo * 0.55 + flareI * 0.6;
			acc += scol * (inten * pk + gas * bloom_strength * bloom_mult * pk * 0.25);
		}
	}
	return acc;
}

// Rare landmarks: a coarse grid where sparse cells emit a big bright nebula-core glow + a bright giant
// star, region-coloured. 3×3 + gaussian → contained (no boxes). These are the "whoa, what's over there".
vec3 landmarks(vec2 p, vec3 region_col) {
	vec3 acc = vec3(0.0);
	vec2 cell = floor(p);
	vec2 f = fract(p);
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 oc = vec2(float(xx), float(yy));
			vec2 c = cell + oc;
			if (hash(c + 71.3) > landmark_rarity) { continue; }
			vec2 lc = oc + vec2(0.25 + 0.5 * hash(c + 2.7), 0.25 + 0.5 * hash(c + 9.1));
			vec2 d = f - lc;
			float dist = length(d);
			float core_glow = exp(-dist * dist / max(landmark_size * landmark_size, 1e-5));   // big soft core
			float giant     = exp(-dist * dist / 0.0009);                                     // bright giant star
			// Landmark colour: its region hue, biased bright; occasionally a vivid giant (gold/blue/magenta).
			float ht = hash(c + 4.4);
			vec3 lcol = mix(region_col + vec3(0.3), star_color(ht), 0.5);
			acc += lcol * (core_glow * landmark_intensity + giant * landmark_intensity * 1.8);
		}
	}
	return acc;
}

void fragment() {
	vec2 t = vec2(TIME * time_drift);
	vec2 p = UV * base_scale + world_offset + t;

	// ── Domain warp → swirling cloud turbulence. background_test: simplex has more high-frequency energy than
	// gradient noise, so the strong warp folded it into busy "marble" veins. Soften with a gentler warp +
	// fewer octaves on the detail so it reads as soft painterly clouds again (no facets — simplex). ──
	float warp_eff = warp_strength * 0.3;   // gentler fold (3.0 → ~1.35)
	int oct_d = max(octaves - 1, 4);          // a touch less fine detail
	vec2 q = vec2(fbm(p, oct_d), fbm(p + vec2(5.2, 1.3), oct_d));
	vec2 r = vec2(fbm(p + warp_eff * q + vec2(1.7, 9.2), oct_d),
	              fbm(p + warp_eff * q + vec2(8.3, 2.8), oct_d));
	float dens = fbm(p + warp_eff * r, oct_d);

	// ── Macro BIOME: a huge-scale field deciding the region — empty void ↔ dense nebula. Drives the rest.
	// Its domain is warped by a medium-frequency field so the void↔dense boundary SNAKES (no straight edge). ──
	// Medium-frequency warp so the void↔dense boundary snakes. With simplex noise there is no square-grid
	// lattice, so a gentle warp keeps the regions LARGE and smooth (no facets) — the strong `r` warp would
	// over-drive this low-frequency field into busy high-frequency noise.
	float bwarp  = fbm_s(p * 0.6 + 21.0, 4);
	float biome  = fbm_s(p * biome_scale + (bwarp - 0.5) * biome_warp + 900.0, max(octaves - 2, 5));
	float region = smoothstep(void_threshold, dense_threshold, biome);   // 0 = void, 1 = dense nebula

	// Soft coverage, then GATE by region so voids go near-empty and dense regions get the full nebula.
	// cloud_softness blurs the density toward a lower-detail form — sampled from the WARPED coordinate so it
	// stays swirly (an un-warped field here injected angular/faceted contours).
	float big = fbm((p + warp_eff * r) * 0.6 + 50.0, max(octaves - 1, 5));
	float soft_eff = clamp(cloud_softness + 0.5, 0.0, 0.85);   // blur more → softer cloud body
	float dens_s = mix(dens, big, soft_eff);
	float cloud = smoothstep(cloud_coverage - cov_fade_lo, cloud_coverage + cov_fade_hi, dens_s) * (0.35 + 0.65 * big);
	cloud *= region;

	// ── Dominant region hue in BIG blocks (a SLOW field, not screen-scale → warm/cool don't average to
	// brown). Whole areas read warm (red→gold) or cool (indigo→blue); fine cloud detail rides on top. ──
	// Warp the hue field the same way the biome is warped (reusing bwarp) so the warm/cool boundary SNAKES
	// instead of cutting a straight diagonal — an unwarped low-freq field is near-planar, so its smoothstep
	// crossing renders as a straight line. Wider band → the handoff is a soft blend, not a defined edge.
	float region_hue = smoothstep(0.30, 0.70,
		fbm_s(p * region_color_scale + (bwarp - 0.5) * biome_warp + 500.0, max(octaves - 3, 4)));
	float gi = clamp(dens, 0.0, 1.0);   // ramp input: denser gas → bright end of its ramp
	vec3 base = mix(cool_ramp(gi), warm_ramp(gi), region_hue);

	// ── Brightness heatmap (within-region texture). Simplex (fbm_s) → smooth curvy variation, no facets. ──
	float hf = fbm_s(p * bright_var_scale + 300.0, 4);
	float heat = smoothstep(0.25, 0.75, hf);
	float gb = brightness * gas_brightness * mix(bright_var_min, bright_var_max, heat);

	// Gas over the void — HERO: bright + near-opaque where clouds exist; voids stay deep black.
	vec3 col = mix(col_void, base * gb, clamp(cloud * gas_opacity, 0.0, 1.0));

	// ── Glowing cores: densest gas blooms to a hot near-white emission. ──
	float core = smoothstep(core_threshold, 1.0, dens) * cloud;
	col += core_color * core * core_intensity;

	// ── HDR tone curve: crush voids toward black, lift cores toward white (true dynamic range). ──
	col = pow(max(col, vec3(0.0)) * exposure, vec3(contrast));

	// ── Stars: density FOLLOWS the region — clusters in dense nebulae, near-empty in voids. ──
	float star_region = mix(0.15, cluster_strength, region);
	float tintA;
	float sa = stars(p * 6.0, clamp(star_density * star_region, 0.0, 1.0), tintA);
	col += mix(vec3(1.0), vec3(0.7, 0.82, 1.0), tintA) * sa * star_brightness;
	col += bright_stars(p * bright_star_scale, clamp(bright_star_density * star_region, 0.0, 1.0)) * bright_star_brightness;

	// ── Rare landmarks (tinted by the region's dominant hue). ──
	col += landmarks(p * landmark_scale, mix(cool_ramp(0.7), warm_ramp(0.7), region_hue));

	// ── Dither: break 8-bit banding (runs at full res now). Triangular (two hashes) for cleaner noise. ──
	float d1 = hash(UV * 1973.0 + t);
	float d2 = hash(UV * 2671.0 - t);
	col += (d1 + d2 - 1.0) * 1.5 / 255.0;

	COLOR = vec4(col, 1.0);
}
