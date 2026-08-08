shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// REAL 3D swirling-vortex FUNNEL for the Atlantic "whirlpool" plume — a curved surface-of-revolution mesh (wide
// mouth, narrow throat — see atlantic_clouds.gd's _build_funnel_mesh()) spawned into atlantic_trees.gd's shared
// World3D "host" root (get_world3d_root()) so it renders through the SAME orthogonal isometric-tilted camera/
// compositor as the ship/temple/scattered coral (atlantic_asset_layer.gd) — no separate viewport needed.
//
// atlantic_clouds.gd positions the mesh so the wide mouth sits at world Y=0 (the water surface) and the narrow
// throat extends down into "underwater" — mesh UV convention (set explicitly in _build_funnel_mesh, NOT
// Godot's built-in CylinderMesh anymore): V=0 at the mouth rim, V=1 at the throat, U wraps 0..1 around the
// circumference in the SAME direction the mesh's own vertices are wound (sin/cos(U*TAU)).
//
// 2026-08-09 rewrite #2 — user supplied a reference photo/spec after rewrite #1 still weren't reading as a real
// vortex ("Bề mặt của nó vẫn đang làm những đường thẳng chứ không phải dạng vortex"): the winding term needs to
// be grounded in the actual fluid-dynamics shape of a drain vortex, not an ad-hoc curve.
//
// MODEL — a "spiral sink" (a Rankine-type vortex with radial inflow toward the drain, superimposed on
// tangential rotation): a fluid parcel's path under simultaneous inward radial velocity v_r and tangential
// velocity v_θ traces a LOGARITHMIC SPIRAL, r(θ) = a·e^(kθ) (equivalently θ(r) = ln(r/a)/k) — the standard
// result for combined radial+tangential flow with a constant v_r/v_θ ratio, and visually exactly what a real
// whirlpool's streak lines look like: nearly straight far from the core (large r, slow angular change per unit
// r), tightening into a fast, tight coil approaching the drain (small r, huge angular change per unit r) — the
// Rankine model's own free-vortex region (v_θ ∝ 1/r, outside the solid-body core) is what gives that inverse
// relationship. `wind` below implements θ(r) directly: swirl_strength acts as 1/k (the spiral's pitch), and
// `phase` combines it with the STATIC per-arm angular offset (ang·arm_count) plus a TIME-based rotation applied
// uniformly at every radius (the whole pattern spins together, same as a real vortex's overall rotation).
//
// `r(v)` uses the SAME curved profile atlantic_clouds.gd's _build_funnel_mesh() actually builds the mesh with
// (mouth_radius/throat_radius/profile_exp, all set as uniforms below) so the winding is computed against the
// TRUE physical radius at that depth, not a straight-line approximation.

uniform float spin_speed = 2.0;       // radians/sec — tied to the Plume Edit panel's "Spin Speed" slider
uniform float swirl_strength = 5.0;   // spiral pitch (1/k in the log-spiral) — higher = tighter winding near the throat
uniform float arm_count = 5.0;        // number of visible spiral arms
uniform vec4 tint : source_color = vec4(0.35, 0.75, 0.9, 1.0);
uniform float opacity = 1.0;
uniform float mouth_radius = 105.0;   // must match _build_funnel_mesh()'s own mouth_r for this instance
uniform float throat_radius = 13.0;   // must match _build_funnel_mesh()'s own throat_r for this instance
uniform float profile_exp = 0.45;     // must match _build_funnel_mesh()'s own exp_v for this instance

void fragment() {
	float v = UV.y;          // 0 = mouth/rim, 1 = throat/drain
	float ang = UV.x * TAU;  // 0..2π around the circumference

	// Physical radius at this depth — SAME formula as _build_funnel_mesh(), so the log-spiral below winds
	// against the funnel's actual (curved, not straight-cone) wall shape.
	float r = throat_radius + (mouth_radius - throat_radius) * pow(1.0 - v, profile_exp);

	// Logarithmic-spiral winding: θ(r) = ln(mouth_radius/r) / k, k = 1/swirl_strength. Positive and growing as r
	// shrinks toward the throat — this IS the "tightening coil" a real vortex's streaklines trace, per the
	// spiral-sink model in this shader's header (replaces rewrite #1's ad-hoc v² term, which still read as
	// straight parallel stripes because it wasn't actually modeling a spiral's geometry).
	float wind = swirl_strength * log(max(mouth_radius, 1.0) / max(r, 0.01));
	// Rotation — the whole winding pattern spins together over time, uniformly at every radius. Negative sign =
	// counter-clockwise on screen (see atlantic_clouds.gd's tangential_accel comment for the derivation).
	float rot = -spin_speed * TIME * arm_count;

	float phase = ang * arm_count + rot - wind;
	float spiral = sin(phase) * 0.5 + 0.5;
	float arms = pow(spiral, 3.0);

	float core_shade = smoothstep(0.0, 0.8, v);   // darker toward the throat (looking down into the funnel)
	float rim_glow = 1.0 - smoothstep(0.0, 0.22, v);   // bright foam right at the mouth

	vec3 col = tint.rgb * (0.20 + 0.55 * core_shade);
	col += vec3(0.9, 1.0, 1.0) * arms * 0.5 * core_shade;
	col += vec3(1.0) * rim_glow * 0.6;
	// Hard LDR clamp — this project runs hdr_2d with glow_hdr_threshold=1.0 (arena.gd's _make_glow_world_env),
	// so any channel left above 1.0 blooms. See atlantic_whirlpool_funnel.gdshader's own header for the exact
	// bug this caused once already (a screen-covering white blob) — same precaution here.
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ALPHA = clamp(0.35 + 0.55 * arms, 0.0, 1.0) * opacity;
}
