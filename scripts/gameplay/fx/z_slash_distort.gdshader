shader_type canvas_item;
// Z-Sword slash LAYER 4 — screen-space distortion (the scythe tutorial's distortion layer). On a fullscreen
// ColorRect/CanvasLayer: reads the rendered screen and refracts it within the slash's CRESCENT band (an arc
// segment), so the background warps along the blade's path → real depth/weight. Invisible on a flat colour
// (needs background detail). Works in PIXEL space so the arc is correct on any aspect ratio. The band spans the
// swept arc [ang_lead - ang_span, ang_lead] at radius_px ± thickness_px from `center` (UV).

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);     // slash centre in screen UV
uniform float radius_px = 180.0;     // band radius in pixels
uniform float thickness_px = 26.0;   // band half-width in pixels
uniform float ang_lead = 0.0;        // leading-edge angle (screen == world, no camera rotation)
uniform float ang_span = 1.0;        // swept arc width
uniform float force = 0.03;          // UV displacement strength
uniform float aberration = 0.5;

void fragment() {
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;        // pixel coords
	vec2 cpx = center / SCREEN_PIXEL_SIZE;
	vec2 dpx = px - cpx;
	float dist = length(dpx);
	float ang = atan(dpx.y, dpx.x);
	float rband = 1.0 - smoothstep(0.0, thickness_px, abs(dist - radius_px));
	float rel = mod(ang - ang_lead + PI, TAU) - PI;                 // wrap to [-PI, PI]
	float amask = smoothstep(0.0, 0.12, rel + ang_span) * (1.0 - smoothstep(-0.1, 0.04, rel));
	float m = rband * amask;
	vec2 dir = dist > 1e-3 ? dpx / dist : vec2(0.0);                // unit screen direction (outward)
	vec2 disp = dir * m * force;
	float r = texture(screen_tex, SCREEN_UV - disp * (1.0 + aberration)).r;
	float g = texture(screen_tex, SCREEN_UV - disp).g;
	float b = texture(screen_tex, SCREEN_UV - disp * (1.0 - aberration)).b;
	COLOR = vec4(r, g, b, 1.0);
}
