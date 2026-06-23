shader_type canvas_item;
// Screen-space SHOCKWAVE distortion — Godot 4, multi-wave version. Applied to a fullscreen ColorRect on a
// CanvasLayer: reads the rendered screen and DISPLACES pixels outward within several concentric donut rings, so
// the background ripples/refracts. Up to 4 waves travel outward independently (radii[i]/amps[i] set per-frame
// from GDScript) — later waves are born later and die faster. Invisible on a flat colour (needs background
// detail: stars/nebula in game, the test grid). Chromatic aberration = the tutorial's homework.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);
uniform float radii[4];        // each wave's current ring radius (screen-height units); 0 = inactive
uniform float amps[4];         // each wave's current displacement strength; 0 = inactive
uniform float thickness = 0.05;
uniform float aberration = 0.6;

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;   // = width/height
	vec2 raw = SCREEN_UV - center;
	vec2 d = raw;
	d.x *= aspect;                                              // aspect-correct → circular rings
	float dist = length(d);
	vec2 dir = dist > 1e-5 ? normalize(raw) : vec2(0.0);        // displace outward in raw UV space
	vec2 disp = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		if (amps[i] <= 0.0) {
			continue;
		}
		float ring = 1.0 - smoothstep(0.0, thickness, abs(dist - radii[i]));
		disp += dir * ring * amps[i];
	}
	float r = texture(screen_tex, SCREEN_UV - disp * (1.0 + aberration)).r;
	float g = texture(screen_tex, SCREEN_UV - disp).g;
	float b = texture(screen_tex, SCREEN_UV - disp * (1.0 - aberration)).b;
	COLOR = vec4(r, g, b, 1.0);
}
