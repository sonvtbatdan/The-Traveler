shader_type canvas_item;

// Blue-grass / dark-sand blotchy ground for the Rubicon map. Screen-filling rect (rubicon_ground.gd),
// world_offset uniform makes the pattern scroll continuously with the player instead of the rect itself
// moving. Noise is BAKED into seamless textures at load time (FastNoiseLite/NoiseTexture2D, script side) —
// same "Luna's Wandering Stars" technique as assets/shaders/nebula_baked.gdshader — this shader only
// SAMPLES + tiles them via repeat wrap. An earlier hand-rolled live fbm() here showed a real banding
// artifact; the baked-texture approach is the one already proven artifact-free in this codebase.

uniform sampler2D tex_zone : repeat_enable, filter_linear;     // blue-vs-sand split (low frequency, big blotches)
uniform sampler2D tex_mottle : repeat_enable, filter_linear;   // canopy variant-region field (higher frequency)
uniform sampler2D tex_river : repeat_enable, filter_linear;    // river contour field (very low frequency)
uniform sampler2D tex_canopy_a : repeat_enable, filter_linear_mipmap;   // real top-down jungle-canopy photos,
uniform sampler2D tex_canopy_b : repeat_enable, filter_linear_mipmap;   // each sampled at its own UV scale/
uniform sampler2D tex_canopy_c : repeat_enable, filter_linear_mipmap;   // offset — see fragment() below
uniform sampler2D tex_canopy_a_normal : repeat_enable, filter_linear_mipmap;   // real tangent-space normal map
uniform sampler2D tex_canopy_b_normal : repeat_enable, filter_linear_mipmap;   // per canopy_a/b/c (tools/
uniform sampler2D tex_canopy_c_normal : repeat_enable, filter_linear_mipmap;   // generate_canopy_normal.py)
uniform sampler2D tex_water_wave : repeat_enable, filter_linear_mipmap;   // genuinely seamless wave-crest photo

uniform vec2 world_offset = vec2(0.0, 0.0);
uniform vec2 rect_size = vec2(1000.0, 1000.0);
uniform float zone_uv_scale = 0.0035;     // world px -> tex_zone UV
uniform float mottle_uv_scale = 0.02;     // world px -> tex_mottle UV
uniform float river_uv_scale = 0.0009;    // world px -> tex_river UV
uniform float canopy_uv_scale = 0.000625; // world px -> tex_canopy_a/b UV (1/1600 — see rubicon_ground.gd)
uniform float canopy_tint_strength = 0.5; // 0 = photo colors as-is, 1 = fully multiply-tinted by zone color
uniform float blend_softness = 0.06;

// Real per-pixel directional lighting against tex_canopy_*_normal (replaces an earlier flat "bump" emboss-
// multiply hack — see tools/generate_canopy_normal.py's header for why a real normal + N.L reads as much more
// convincingly "3D" than a single baked highlight/shadow channel). Deliberately NOT a Godot Light2D (every
// other 2D layer here stays unlit — adding a real light source would mean masking it off everything else too)
// — this is a self-contained, manually-computed Lambert + Blinn-Phong term, tunable live via the Terrain Edit
// panel (rubicon_ground.gd's apply_canopy_lighting).
uniform vec3 canopy_light_dir = vec3(0.6, 0.6, 0.6);   // normalized-ish "sun" direction; z = how overhead it is
uniform vec4 canopy_light_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);   // "sun" tint — neutral on the
                                                                                 // shadow side, full strength
                                                                                 // on lit faces + specular
uniform float canopy_ambient = 0.45;      // floor brightness on the shadow side (0 = can go pure black)
uniform float canopy_contrast = 1.0;      // pivot-at-0.5 contrast on the diffuse term — 1 = unchanged, >1 =
                                           // punchier highlight/shadow separation, <1 = flatter
uniform float canopy_specular_strength = 0.3;
uniform float canopy_specular_power = 18.0;
uniform float blue_threshold = 0.5;
uniform vec4 col_blue_light : source_color = vec4(0.30, 0.56, 0.90, 1.0);
uniform vec4 col_sand_light : source_color = vec4(0.46, 0.36, 0.15, 1.0);

uniform float river_level = 0.5;    // RubiconConfig.RIVER_LEVEL — which contour becomes the river centerline
uniform float river_width = 0.035;  // half-width of the river band, in noise-value space (0 = no rivers)
uniform vec4 river_color_dark : source_color = vec4(0.05, 0.18, 0.35, 1.0);
uniform vec4 river_color_light : source_color = vec4(0.15, 0.45, 0.65, 1.0);
uniform vec4 river_bank_color : source_color = vec4(0.87, 0.74, 0.40, 1.0);   // golden riverbank sand
uniform float river_bank_width = 0.022;   // extra noise-value half-width beyond river_width the bank extends
uniform float water_wave_uv_scale = 0.00385;   // world px -> tex_water_wave UV (1/260 — see rubicon_ground.gd)
uniform float water_wave_speed = 26.0;         // world-px/sec the wave texture scrolls, along wave_dir_a below

// Landmark ground (e.g. the temple boss, rubicon_temple_layer.gd) — a worn-clearing area SOLID-filled from
// each currently-alive landmark's own center out to [base footprint + ring_width] (no inner hole), same
// river_bank_color as the riverbank fringe above (deliberately reuses that one uniform directly, not a
// separate color, so adjusting River Bank Color updates both at once) — and this fill also suppresses the
// river mask beneath it (see final_river_mask below), so ground is guaranteed under a landmark's whole base
// no matter where it spawned relative to the river field, without the spawner needing to search for dry land.
// Shaped as an oriented BOX (half_extent/yaw, from RubiconTrees.spawn_landmark's raw AABB measurement)
// matching the model's actual base footprint where it touches the terrain, rather than a circle centered on
// the landmark's position — a circle built from the AABB's diagonal floats visibly outside the real base on
// any non-square footprint.
//
// `yaw` is the same random Y-axis rotation the 3D model itself spawned with. The box test below maps
// world_pos back into the model's own local mesh space via the exact INVERSE of the real forward transform a
// base-level (y=0) mesh point goes through to reach the screen: rotate by yaw, then the camera-tilt-induced
// Z-foreshortening scales only the resulting Z-ish screen axis by 1/LANDMARK_Z_COMP (see RubiconAssetLayer.
// CAM_ISO_DEG / rubicon_trees.gd's _z_comp — same tilt, same constant, duplicated here since this is a
// separate canvas_item shader with no access to that script's uniform). An earlier version divided
// half_extent by that factor BEFORE rotating (in GDScript, once, not per-pixel) — that's only exact at
// yaw = 0/90/180/270; at other angles scale-then-rotate != rotate-then-scale, and the box visibly skewed off
// the model's real screen silhouette. Inverting the FULL rotate-then-shear transform here (per-pixel, exactly
// undoing forward = rotate(yaw) then scale-Z-by-1/LANDMARK_Z_COMP) makes the box edge land exactly on the
// model's true projected outline at any yaw. Fixed-size array (Godot canvas_item shaders don't support
// dynamic-length uniform arrays) — unused slots are pushed far away / zeroed (rubicon_ground.gd's
// apply_landmarks) so they never contribute.
uniform vec2 landmark_pos[8];
uniform vec2 landmark_half_extent[8];
uniform float landmark_yaw[8];
uniform int landmark_count = 0;
const float LANDMARK_Z_COMP = 1.1547005383792515;   // 1.0 / cos(radians(30.0)) — must match RubiconAssetLayer.CAM_ISO_DEG
uniform float landmark_ring_width = 32.0;

// How far beyond landmark_ring_width the guaranteed-dry "ground patch" extends, and how much its outer edge
// wobbles away from a clean rounded-box outline (sampled from tex_mottle, same noise field already used for
// canopy variant regions — see fragment() below) so the patch reads as an organic land shape, matching the
// naturally-occurring ground islands the zone/river noise already produces elsewhere on the map, rather than a
// flat solid-color box.
uniform float landmark_patch_radius = 320.0;
uniform float landmark_patch_edge_noise = 70.0;

void fragment() {
	vec2 world_pos = (UV - 0.5) * rect_size + world_offset;
	float n = texture(tex_zone, world_pos * zone_uv_scale).r;
	float zone = smoothstep(blue_threshold - blend_softness, blue_threshold + blend_softness, n);

	// Real top-down jungle-canopy photos give the ground actual leaf-cluster detail flat noise-color
	// blotches never could. Neither source photo is itself seamless (see rubicon_ground.gd's header — same
	// "occasional seam at long-flight distance is an accepted tradeoff" precedent already used for
	// tex_zone/tex_mottle above), and each is sampled at its OWN UV scale/offset so their tiling seams don't
	// line up with each other. Picking between the 3 photos is a mostly-HARD region split (only a narrow
	// smoothstep band right at each threshold) rather than a continuous cross-fade across the whole 0..1
	// mottle range — cross-fading two full photos over a wide area reads as a ghostly double-exposure
	// dissolve, whereas a thin blended seam between two otherwise-clean regions barely registers.
	float mottle = texture(tex_mottle, world_pos * mottle_uv_scale).r;
	vec2 uv_a = world_pos * canopy_uv_scale;
	vec2 uv_b = world_pos * canopy_uv_scale * 1.37 + vec2(311.0, -173.0);
	vec2 uv_c = world_pos * canopy_uv_scale * 0.79 + vec2(-197.0, 421.0);
	vec3 canopy_a = texture(tex_canopy_a, uv_a).rgb;
	vec3 canopy_b = texture(tex_canopy_b, uv_b).rgb;
	vec3 canopy_c = texture(tex_canopy_c, uv_c).rgb;

	// Real tangent-space normal maps (tools/generate_canopy_normal.py), sampled at the EXACT SAME uv as their
	// color counterpart, decoded from 0..1 texture space to a -1..1 surface normal.
	vec3 nrm_a = texture(tex_canopy_a_normal, uv_a).rgb * 2.0 - 1.0;
	vec3 nrm_b = texture(tex_canopy_b_normal, uv_b).rgb * 2.0 - 1.0;
	vec3 nrm_c = texture(tex_canopy_c_normal, uv_c).rgb * 2.0 - 1.0;

	const float region_softness = 0.04;
	float t_ab = smoothstep(1.0 / 3.0 - region_softness, 1.0 / 3.0 + region_softness, mottle);
	float t_bc = smoothstep(2.0 / 3.0 - region_softness, 2.0 / 3.0 + region_softness, mottle);
	vec3 canopy_col = mix(mix(canopy_a, canopy_b, t_ab), canopy_c, t_bc);
	vec3 canopy_nrm = normalize(mix(mix(nrm_a, nrm_b, t_ab), nrm_c, t_bc));

	// Terrain Edit panel's 2 color pickers stay meaningful as a multiply-tint over the photo (not a full
	// replacement) — canopy_tint_strength=0 would show the photo's own colors untouched, 1 fully recolors it.
	vec3 zone_tint = mix(col_sand_light.rgb, col_blue_light.rgb, zone);
	vec4 ground_col = vec4(mix(canopy_col, canopy_col * zone_tint * 2.0, canopy_tint_strength), 1.0);

	// Manual Lambert + Blinn-Phong shading against the blended normal — see the uniform block comment above
	// for why this is a hand-rolled term instead of a real Light2D. View direction assumed straight up (0,0,1)
	// since the camera is effectively top-down for this flat layer. canopy_light_color tints only the LIT
	// portion (mix toward it by ndotl, staying neutral white in full shadow) + the specular highlight, so a
	// warm/cool "sun" reads as actual colored light hitting the surface rather than a flat color wash.
	vec3 light_dir = normalize(canopy_light_dir);
	float ndotl = max(dot(canopy_nrm, light_dir), 0.0);
	float diffuse = canopy_ambient + (1.0 - canopy_ambient) * ndotl;
	diffuse = clamp((diffuse - 0.5) * canopy_contrast + 0.5, 0.0, 2.5);   // pivot-at-mid-gray contrast push
	vec3 light_tint = mix(vec3(1.0), canopy_light_color.rgb, ndotl);
	vec3 half_vec = normalize(light_dir + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(canopy_nrm, half_vec), 0.0), canopy_specular_power) * canopy_specular_strength;
	ground_col.rgb = ground_col.rgb * diffuse * light_tint + canopy_light_color.rgb * spec;

	// River: extract the near-river_level contour of a separate, much-lower-frequency noise field — a soft
	// winding band, not a hard-edged shape.
	float rv = texture(tex_river, world_pos * river_uv_scale).r;
	float river_dist = abs(rv - river_level);
	float river_mask = 1.0 - smoothstep(river_width * 0.6, river_width, river_dist);

	// Real (genuinely seamless — see rubicon_ground.gd) wave-crest photo, scrolled in two different
	// directions/scales/speeds and added together — replaces an earlier two-sine "shimmer" hack whose crossed
	// gradients interfered into an ugly plaid/grid pattern instead of reading as water. Two independent scroll
	// passes avoid the single-texture's own repeat ever being obviously visible as a moving grid.
	vec2 wave_dir_a = vec2(0.85, 0.53);
	vec2 wave_dir_b = vec2(-0.40, 0.92);
	vec2 wave_uv_a = world_pos * water_wave_uv_scale + wave_dir_a * TIME * water_wave_speed * water_wave_uv_scale;
	vec2 wave_uv_b = world_pos * water_wave_uv_scale * 1.7 - wave_dir_b * TIME * water_wave_speed * 0.6 * water_wave_uv_scale;
	float wave_a = texture(tex_water_wave, wave_uv_a).r;
	float wave_b = texture(tex_water_wave, wave_uv_b).r;
	float wave_mix = clamp(wave_a * 0.65 + wave_b * 0.5, 0.0, 1.0);
	vec3 water_rgb = mix(river_color_dark.rgb, river_color_light.rgb, wave_mix);
	water_rgb += vec3(pow(wave_mix, 5.0) * 0.4);   // bright glints on the sharpest wave crests

	// Foam right at the shoreline (where water meets the sand bank), textured by the same wave field instead
	// of a perfectly smooth ring so it reads as irregular surf, not a drawn outline. Uses river_bank_color
	// DIRECTLY (no white mix) — an earlier version lightened it 55% toward white, which the ONE River Bank
	// Color picker could only nudge subtly, reading as "this ring doesn't respond to the color picker" even
	// though it technically did. Both bands now track the exact same color; the wave-modulated intensity
	// below is what still reads as "foam" rather than a second flat ring.
	vec3 foam_tint = river_bank_color.rgb;
	float shore_dist = abs(river_dist - river_width * 0.88);
	float foam_band = 1.0 - smoothstep(0.0, river_width * 0.16, shore_dist);
	water_rgb = mix(water_rgb, foam_tint, foam_band * (0.35 + 0.5 * wave_a));
	vec4 water_col = vec4(water_rgb, 1.0);

	// Golden sand fringe between canopy and water — bank_mask is 1 all the way from the river center out to
	// river_width (harmlessly UNDER the water, which composites on top of it below) and fades to 0 by
	// river_width + river_bank_width, so the only place it actually SHOWS is that outer ring: canopy fades to
	// sand, sand fades to water, instead of canopy running straight into the riverbed.
	float bank_mask = 1.0 - smoothstep(river_width, river_width + river_bank_width, river_dist);

	// Ground patch around each landmark — guarantees dry land under the model's whole base (no gap, no water
	// peeking through) same as before, but now reads as an actual "mảng ground" (a real patch of jungle,
	// same canopy texture as the rest of the map) instead of a flat solid-color box. landmark_ring stays a
	// tight SOLID fill right at the model's own base (0 gap under its feet); landmark_patch extends further
	// out with an organic, noise-wobbled edge (landmark_patch_edge_noise) and keeps the normal ground_col —
	// only landmark_bank (a thin band straddling the patch's outer edge) gets the golden riverbank fringe, so
	// a nearby river reads as encircling a natural island instead of the whole area being one gold disc. Uses
	// a rotated-box signed distance in the model's own local mesh space (see the uniform block comment above
	// for the exact inverse-transform math) so the inner fill lands exactly on the model's true base silhouette
	// at any yaw, not an approximation.
	float landmark_ring = 0.0;
	float landmark_patch = 0.0;
	float landmark_bank = 0.0;
	for (int i = 0; i < landmark_count; i++) {
		vec2 rel = world_pos - landmark_pos[i];
		float c = cos(landmark_yaw[i]);
		float s = sin(landmark_yaw[i]);
		vec2 local = vec2(c * rel.x - s * LANDMARK_Z_COMP * rel.y, s * rel.x + c * LANDMARK_Z_COMP * rel.y);
		vec2 q = abs(local) - landmark_half_extent[i];
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);   // 0 at the base edge, + outside, - inside
		landmark_ring = max(landmark_ring, 1.0 - smoothstep(landmark_ring_width - 8.0, landmark_ring_width + 8.0, d));

		float wobble = (texture(tex_mottle, world_pos * mottle_uv_scale + landmark_pos[i] * 0.001).r - 0.5) * 2.0 * landmark_patch_edge_noise;
		float patch_dist = d - landmark_ring_width - landmark_patch_radius - wobble;   // 0 at the patch's organic outer edge
		landmark_patch = max(landmark_patch, 1.0 - smoothstep(-40.0, 40.0, patch_dist));
		landmark_bank = max(landmark_bank, 1.0 - smoothstep(0.0, 60.0, abs(patch_dist)));
	}
	float landmark_dry = max(landmark_ring, landmark_patch);   // guaranteed-dry area (fill + patch combined)

	// Only the model's own base (landmark_ring) and the patch's outer edge (landmark_bank) get the golden
	// riverbank color; the rest of the patch interior keeps ground_col so it blends with the surrounding jungle.
	vec4 banked_col = mix(ground_col, river_bank_color, max(bank_mask, max(landmark_ring, landmark_bank)));

	// Suppress water across the whole guaranteed-dry area — this is what guarantees "always ground under the
	// temple" regardless of where it spawned relative to the river field, instead of relying on the spawner
	// finding a dry spot. Beyond the patch's edge, the natural river field takes back over, so an actual nearby
	// river reads as surrounding the patch like any other naturally-occurring ground island.
	float final_river_mask = river_mask * (1.0 - landmark_dry);

	COLOR = mix(banked_col, water_col, final_river_mask);
}
