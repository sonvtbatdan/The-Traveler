shader_type canvas_item;
render_mode unshaded;

// gauss_orb_fx — procedural plasma-ball, replacing both the 24-frame gauss24_XX.png orb flipbook and the
// 12-frame gauss_explosion flipbook (arena_weapons.gd reuses this same shader for the bigger impact burst,
// just driving `diameter` larger + an intro/outro alpha fade). UV is the draw_rect's local 0..1 space
// (square quad); p = UV remapped to -1..1 "radius units" so the whole shape is resolution-independent
// (works at any on-screen diameter, incl. the sqrt(damage) shrink, Pew Pew/Spirit Bomb size_mult, and the
// explosion's much larger draw size).
//
// Look, from the reference frames (assets/beam references/Gauss_orb_files_2/gauss24_*.png): a solid-ish
// navy-blue sphere textured with a Worley/cell "cracked glass" pattern (cell borders read as glowing cyan
// veins), a bright cyan rim shell right at the sphere boundary, jagged lightning prongs poking out past
// the rim at uneven angles (corona), a white-hot core blob near the centre the veins feed into, and a
// soft grey-white halo bleeding out into the transparent margin. NORMAL (mix) blend, not additive — an
// additive white core would blow out when many orbs/explosions overlap (Fission spawns several at once).

uniform float seed = 0.0;              // per-instance phase offset so simultaneous orbs (Fission) don't pulse in lockstep
uniform float time_scale = 1.0;        // overall animation-speed multiplier (the impact burst runs this much faster than the calm flying orb)

uniform float cell_freq = 5.0;         // Worley cell density across the sphere
uniform float cell_edge_width = 0.14;  // glowing vein thickness at cell borders
uniform float crack_mix = 0.55;        // strength of the finer 2nd crack layer (branching detail)
uniform float warp_amount = 0.4;       // domain-warp strength (cells wobble/breathe instead of sliding)
uniform float warp_speed = 0.5;
uniform float crack_jitter_rate = 11.0;  // Hz — the crack network's GEOMETRY (cell layout) snaps to a new
                                          // shape this many times/sec (stepped time, not a smooth crawl).
uniform float crack_dim = 0.32;          // resting (non-flashing) vein brightness — dim on purpose, so a
                                          // flash is a real jump from "barely visible" to "blinding", not
                                          // just a brighter line in an already-bright web.
uniform float flash_rate = 26.0;         // Hz — separate, faster on/off blink for the flash itself, decoupled
                                          // from crack_jitter_rate so bolts can strobe quicker than the web reshapes.
uniform float arc_flash_chance = 0.09;   // odds a given vein segment is "struck" on a given flash-frame — kept
                                          // low so strikes read as sparse, isolated bolts, not a shimmering mesh.
uniform float arc_flash_boost = 6.0;     // brightness multiplier while flashing — pushed past 1.0 on purpose,
                                          // this project runs HDR 2D with bloom, so a flash blooms into a bright,
                                          // slightly thicker bolt instead of just a brighter thin line.

uniform float sphere_radius = 0.78;    // radius (in -1..1 units) of the main cracked-sphere body
uniform float rim_width = 0.04;
uniform float rim_boost = 1.4;
uniform float rim_jitter = 0.02;       // breaks the rim into a jagged coil instead of a smooth ring

uniform float core_radius = 0.20;
uniform float core_jitter = 0.12;

uniform float spike_count = 18.0;      // corona prongs around the rim
uniform float spike_sharpness = 2.6;   // higher = thinner, more pointed prongs (vs. round lobes)
uniform float spike_len = 0.16;
uniform float spike_min = 0.02;

uniform float halo_softness = 0.38;
uniform float halo_amount = 0.6;
uniform float ambient_falloff = 1.6;   // wide soft glow filling the disc (the grey-white haze in the ref)

uniform float flicker_amount = 0.08;
uniform float flicker_speed = 14.0;

uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 body_color : source_color = vec3(0.05, 0.15, 0.55);
uniform vec3 edge_color : source_color = vec3(0.35, 0.75, 1.0);
uniform vec3 rim_color  : source_color = vec3(0.4, 0.85, 1.0);
uniform vec3 halo_color : source_color = vec3(0.75, 0.85, 1.0);

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

// Worley/cellular noise: (F1, F2, cell_id) = distance to nearest/second-nearest jittered grid feature
// point, plus a stable per-cell hash ID. F2-F1 near 0 exactly where two cells meet -> the "cracked glass"
// vein network. cell_id lets the fragment shader flash a whole vein-junction region coherently instead of
// per-pixel dithering.
vec3 worley(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 nearest = ip;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(ip + g + 11.1), hash(ip + g + 37.7));
			float d = length(g + o - fp);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				nearest = ip + g;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2, hash(nearest + 91.7));
}

void fragment() {
	float t = (TIME + seed * 13.0) * time_scale;
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);

	// Hard circular cutoff well inside the quad's corners: halo/ambient below use unbounded exp() falloff
	// that never truly reaches 0, which otherwise tints the whole square draw_rect faintly (very visible as
	// an actual square silhouette at the big explosion's size) — force it to exactly 0 by r=1.0 (the quad's
	// inscribed circle) so only the round plasma ball ever shows.
	float outer_mask = 1.0 - smoothstep(0.85, 1.0, r);

	// The crack layout SNAPS between configurations at crack_jitter_rate Hz (stepped time) rather than
	// crawling continuously — this is what actually reads as jittery electric flicker instead of a smooth
	// organic breathe. Corona/rim/core below reuse this same stepped time so the whole ball snaps together.
	float t_snap = floor(t * crack_jitter_rate) / max(0.001, crack_jitter_rate);

	// Domain-warp before the Worley lookup so the cell network wobbles/breathes in place (matching the
	// reference's frame-to-frame reshuffle) instead of visibly sliding sideways like a scrolling texture.
	float tn = fbm(vec2(p.x * 2.3 + t_snap * warp_speed, p.y * 2.3 - t_snap * warp_speed * 0.8 + seed));
	vec2 pw = p * cell_freq + (tn - 0.5) * warp_amount;
	vec3 w = worley(pw);
	float edge = 1.0 - smoothstep(0.0, cell_edge_width, w.y - w.x);
	// Finer 2nd crack layer (different frequency/offset) -> branching detail instead of one clean lattice.
	vec3 w2 = worley(pw * 1.9 + vec2(31.7, 47.3));
	float edge2 = 1.0 - smoothstep(0.0, cell_edge_width * 0.6, w2.y - w2.x);
	edge = max(edge, edge2 * crack_mix);

	// Arc flash: at rest the vein network is dim (crack_dim) — barely a faint tracery. A hashed subset of
	// vein segments then "gets struck" on a given flash-frame and snaps to arc_flash_boost brightness: a
	// hard on/off cut (not a fade), coherent per-cell (not per-pixel) so a whole segment lights up together,
	// and on ITS OWN faster/decoupled clock (flash_rate) so strikes blink independently of the slower
	// crack-layout reshuffle. That's what reads as actual lightning rather than a shimmering spiderweb.
	float t_flash = floor(t * flash_rate) / max(0.001, flash_rate);
	float flash1 = step(1.0 - arc_flash_chance, hash(vec2(w.z * 131.1, t_flash * 977.0) + seed * 3.7));
	float flash2 = step(1.0 - arc_flash_chance, hash(vec2(w2.z * 131.1, t_flash * 977.0) + seed * 5.1));
	float flash_on = max(flash1, flash2);
	edge *= mix(crack_dim, arc_flash_boost, flash_on);

	float sphere_mask = smoothstep(sphere_radius, sphere_radius * 0.7, r);
	float radial_bias = smoothstep(sphere_radius, 0.0, r);   // veins glow brighter as they approach the core
	edge *= sphere_mask * mix(1.0, 1.8, radial_bias);

	float rim_n = (fbm(vec2(ang * 3.0 + t_snap * 0.4, seed)) - 0.5) * rim_jitter;
	float rim = smoothstep(rim_width, 0.0, abs(r - sphere_radius + rim_n));

	float core = smoothstep(core_radius, 0.0, r + (tn - 0.5) * core_jitter);

	// Corona: uneven lightning prongs poking out past the rim, one hashed pointed tooth per sector —
	// cos()^sharpness peaks at the sector centre and drops fast toward its edges (a thin spike, not a lobe).
	float turns = ang / TAU + 0.5;
	float tphase = turns * spike_count;
	float ti = floor(tphase);
	float tfrac = (tphase - ti) - 0.5;
	float h1 = hash(vec2(ti, seed + 1.7));
	float presence = smoothstep(0.3, 0.7, hash(vec2(ti, seed + 5.3)));   // most sectors quiet, some flare -> uneven, not a gear
	float tooth = pow(max(0.0, cos(tfrac * PI)), spike_sharpness);
	float reach = sphere_radius + mix(spike_min, spike_len, h1) * tooth * presence;
	float spike_turb = fbm(vec2(turns * 6.0 + t_snap * 0.8, r * 4.0 + seed));
	float rr = r + (spike_turb - 0.5) * 0.04;
	float spike = smoothstep(reach + 0.02, reach - 0.04, rr) * smoothstep(sphere_radius * 0.9, sphere_radius, rr) * tooth * presence;

	float halo = exp(-pow(max(r - sphere_radius, 0.0) / max(0.001, halo_softness), 2.0)) * halo_amount;
	float ambient = exp(-r * r * ambient_falloff) * sphere_mask;

	float flick = 1.0 + flicker_amount * sin(t * flicker_speed + seed * 7.0);

	vec3 col = body_color * sphere_mask * 0.45;
	col += halo_color * ambient * 0.15;
	col += edge_color * edge;
	col += rim_color * rim * rim_boost;
	col += mix(edge_color, halo_color, 0.4) * spike;
	col += halo_color * halo;
	col += core_color * core * 1.5;
	col *= flick;

	float alpha = clamp(sphere_mask * 0.9 + edge * 0.9 + rim * rim_boost + spike * 0.9 + halo * 0.8 + core * 1.3, 0.0, 1.0) * outer_mask;

	// Multiply by the incoming COLOR (vertex-stage modulate/self_modulate) instead of overwriting it —
	// otherwise CanvasItem.modulate has no effect at all (Orb of Annihilation's red tint, and the
	// explosion's intro/outro alpha fade driven via modulate.a, would both silently do nothing).
	COLOR = vec4(col, alpha) * COLOR;
}
