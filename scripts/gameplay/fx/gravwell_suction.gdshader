shader_type canvas_item;
// Graviton Well screen-space SUCTION distortion (2026-08-06, on request: "Vòng màu tím giờ chuyển thành
// dạng vfx hút vào tâm đường tròn, làm không gian bị hút hơi bị kéo giãn vào trong") — Godot 4. Applied to a
// fullscreen ColorRect on a CanvasLayer (arena_weapons.gd's _build_gravwell_fx/_drive_gravwell_fx): reads the
// rendered screen and pulls pixels INWARD + slightly SWIRLING toward the well's centre within its current
// radius, so nearby space visibly stretches/warps toward the singularity — replaces the old flat
// draw_circle+draw_arc purple ring. Same SCREEN_TEXTURE UV-displacement technique as explosion_shockwave.
// gdshader/z_slash_distort.gdshader, but a CONTINUOUS effect driven every frame the well is open, not a
// one-shot travelling wave — and the pull is INWARD, not outward.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);       // well centre, screen UV
uniform float radius_px = 120.0;       // well's current radius, screen pixels
uniform float strength = 22.0;         // peak inward displacement, screen pixels
uniform float swirl = 1.8;             // extra rotational pull (radians) toward the centre — vortex feel
uniform float time = 0.0;
uniform float aberration = 0.35;
uniform vec3 tint = vec3(0.0, 0.0, 0.0);   // ring tint — black (2026-08-06, on request: "cho nổi bật"; was purple)

void fragment() {
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 cpx = center / SCREEN_PIXEL_SIZE;
	vec2 dpx = px - cpx;
	float dist = length(dpx);
	// 2026-08-06, bug fix: Godot's fragment() processor rejects an early `return;` ("Using 'return' in the
	// 'fragment' processor function is incorrect") — that compile failure silently broke the WHOLE material,
	// so the fullscreen ColorRect fell back to its flat default white fill the instant Graviton Well opened
	// (reported as "màn hình trắng xóa" the moment the weapon was picked up). Restructured as if/else instead
	// of an early return so the shader actually compiles.
	if (dist >= radius_px || dist < 0.001) {
		COLOR = texture(screen_tex, SCREEN_UV);
	} else {
		float t = 1.0 - dist / radius_px;                     // 0 at the well's edge → 1 at its centre
		float pull = smoothstep(0.0, 1.0, t);
		// Fade the pull back down right at the very centre so it never collapses to a single infinitely-
		// sampled point — reads as a small stable "eye", not a pixelated singularity.
		pull *= 1.0 - smoothstep(0.75, 1.0, t);
		vec2 inward = -dpx / dist;                                     // unit vector toward centre
		float ang = atan(inward.y, inward.x) + swirl * pull;           // swirl tightens toward the centre
		vec2 dir = vec2(cos(ang), sin(ang));
		// Gentle breathing pulse so a held-open well doesn't look perfectly static.
		float breathe = 0.85 + 0.15 * sin(time * 3.0 + dist * 0.08);
		vec2 disp = dir * pull * strength * breathe * SCREEN_PIXEL_SIZE;
		float r = texture(screen_tex, SCREEN_UV - disp * (1.0 + aberration)).r;
		float g = texture(screen_tex, SCREEN_UV - disp).g;
		float b = texture(screen_tex, SCREEN_UV - disp * (1.0 - aberration)).b;
		vec3 col = vec3(r, g, b);
		// 2026-08-06, on request ("phần bên trong đen đậm hơn bên ngoài, không rỗng như donut"): the previous
		// `rim` band was zero at BOTH the edge AND the dead centre (a ring shape with nothing behind it),
		// which read as a hollow transparent hole inside the dark ring. Replaced with a monotonic gradient —
		// 0 (no tint) at the well's own edge, ramping up to 1 (fully opaque tint) at its centre — so the
		// middle is a solid dark core, darkest exactly where the well is deepest, no hollow spot.
		float shade = smoothstep(0.0, 1.0, t);
		col = mix(col, tint, shade);
		COLOR = vec4(col, 1.0);
	}
}
