shader_type canvas_item;
render_mode blend_mix;
// ── SmokeTrail — volumetric-look smoke draw shader ───────────────────────────────────────────────────────
// A particle wall of soft blobs reads as a flat smear. AAA fixes this with flipbooks baked from a fluid sim;
// with no baked art the same *look* is approximated procedurally, per particle:
//   • DOMAIN WARP + TIME EVOLUTION — the sample point is displaced by a slowly evolving noise field, so the
//     internal pattern folds/curls over the puff's life ("boil"), not just scales.
//   • RELIEF LIGHTING — the noise-field gradient is treated as a surface normal, lit from the fire dir →
//     bright ridges / dark hollows → reads as a lit volume (cheap stand-in for a 6-way-lighting bake).
//   • AGE EROSION — carve threshold rises with age (COLOR.a falls past peak_alpha) → dense core → wisps.
//   • per-particle seed packed into COLOR.r/COLOR.g (+ a screen-space jitter) decorrelates overlapping puffs.
// The fbm texture packs TWO independent noise fields (r, g) so one sample gives a 2D warp vector.
// MIX blend: dark smoke must OCCLUDE; additive dark is invisible on a dark scene.

uniform sampler2D fbm_tex : repeat_enable, filter_linear;   // .r / .g = two seamless fractal-noise fields
uniform float peak_alpha   = 0.95;
uniform float warp_amp     : hint_range(0.0, 0.8)  = 0.34;
uniform float evolve       : hint_range(0.0, 1.5)  = 0.4;    // internal boil rate
uniform float macro_scale  : hint_range(0.4, 4.0)  = 1.35;
uniform float detail_scale : hint_range(1.5, 8.0)  = 3.3;
uniform float edge_soft    : hint_range(0.03, 0.5) = 0.15;
uniform float young_cut    : hint_range(0.0, 0.4)  = 0.04;
uniform float old_cut      : hint_range(0.4, 1.0)  = 0.70;
uniform vec2  light_dir     = vec2(0.55, 0.45);
uniform float light_gain   : hint_range(0.0, 2.0)  = 0.82;
uniform float ambient      : hint_range(0.0, 0.8)  = 0.34;
uniform vec3  c_shadow     = vec3(0.06, 0.06, 0.08);
uniform vec3  c_body       = vec3(0.31, 0.30, 0.30);
uniform vec3  c_lit        = vec3(0.60, 0.48, 0.40);
uniform bool  cheap = false;   // crowd LOD: skip the relief-lighting texture reads (see smoke_trail.gd)

void fragment() {
	float v    = COLOR.g;
	float a0   = COLOR.a;
	float seed = fract((COLOR.r / max(COLOR.g, 1e-4) - 0.5) * 1.373 + 0.123);
	float age  = clamp(1.0 - a0 / max(peak_alpha, 1e-4), 0.0, 1.0);

	vec2 p = UV - 0.5;
	float ang = seed * 6.2831853;
	vec2 luv = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang))) * p;
	vec2 base = luv * macro_scale + vec2(seed * 17.0, seed * 11.0) + SCREEN_UV * 0.55;
	float tt = TIME * evolve + seed * 30.0;

	// read 1 — 2D domain-warp vector from the packed r/g fields
	vec2 warp = texture(fbm_tex, base * 0.5 + vec2(tt * 0.05, seed)).rg - 0.5;
	vec2 duv = base + warp * warp_amp;

	// reads 2 & 3 — macro + detail density
	float macro = texture(fbm_tex, duv + vec2(tt * 0.03, 0.0)).r;
	float dc = texture(fbm_tex, duv * detail_scale - vec2(0.0, tt * 0.09)).r;
	float n = macro * 0.6 + dc * 0.4;

	float r = length(p) * 2.0;
	float env = smoothstep(1.02, 0.04, r);
	float cut = mix(young_cut, old_cut, age);
	float dens = smoothstep(cut - edge_soft, cut + edge_soft, n * 0.7 + env * 0.5 - 0.12) * env;
	if (dens < 0.003) {
		discard;   // eroded rim — skip the lighting reads below
	}

	// reads 4 & 5 — detail-field gradient → fake surface normal → relief lighting (skipped on the cheap path,
	// where the density field itself stands in for the shading term)
	float lit;
	if (cheap) {
		lit = ambient + light_gain * clamp(n * 1.3 - 0.15, 0.0, 1.0) * (1.0 - age * 0.6);
	} else {
		float e = 0.6 / detail_scale;
		float nx = texture(fbm_tex, (duv + vec2(e, 0.0)) * detail_scale).r;
		float ny = texture(fbm_tex, (duv + vec2(0.0, e)) * detail_scale).r;
		vec2 nrm = normalize(vec2(nx - dc, ny - dc) + vec2(1e-5));
		float lambert = dot(nrm, normalize(light_dir)) * 0.5 + 0.5;
		lit = ambient + light_gain * pow(clamp(lambert, 0.0, 1.0), 1.4) * (1.0 - age * 0.6);
	}

	vec3 col = mix(c_shadow, c_body, clamp(lit, 0.0, 1.0));
	col = mix(col, c_lit, clamp((lit - 0.7) * 2.2, 0.0, 1.0) * (1.0 - age * 0.8));
	col = mix(col, c_shadow * 1.5, age * 0.45);
	col *= v / max(peak_alpha, 1e-4);

	COLOR = vec4(col, dens * a0);
}
