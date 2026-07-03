shader_type canvas_item;
// "Selected" cell overlay for the level-up board: animated CRT scanlines + grain noise fill, with a solid
// bright border ring using the cell's own rect as the frame. Draw this as a Control sized/positioned exactly
// over the WeaponFrame / UpgradeIcon / CodeName / UpgradeName rect of a choice. Normal (mix) blend — the
// sweeping bright band (icon cells only) is a separate additive layer, see selection_sweep.gdshader.
// Optional gentle flicker (name-plate cells): set flicker_strength > 0 and a per-instance flicker_phase so
// multiple cells don't pulse in lockstep.

uniform vec4 scan_color : source_color = vec4(0.35, 1.0, 0.45, 1.0);
uniform float noise_strength : hint_range(0.0, 1.0) = 0.10;
uniform float scanline_freq : hint_range(1.0, 400.0) = 90.0;
uniform float scan_speed : hint_range(0.0, 10.0) = 2.0;
uniform float border_width : hint_range(0.0, 0.2) = 0.03;
uniform float border_strength : hint_range(0.0, 2.0) = 1.0;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.0;   // 0 = no flicker (icon cells)
uniform float flicker_speed : hint_range(0.1, 10.0) = 2.2;
uniform float flicker_phase : hint_range(0.0, 100.0) = 0.0;    // per-instance random offset, avoids unison

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	// Horizontal CRT scanlines, slowly drifting.
	float scan = sin(uv.y * scanline_freq - TIME * scan_speed) * 0.5 + 0.5;
	scan = pow(scan, 3.0) * 0.35;
	// Animated grain (re-hashed every frame via TIME so it flickers like static).
	float n = hash(uv * vec2(512.0, 384.0) + floor(TIME * 20.0));
	// Solid ring at the rect's own edge (this cell IS the frame — no separate border art needed).
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float border = (1.0 - smoothstep(0.0, border_width, edge)) * border_strength;
	float fill = scan + n * noise_strength;
	float alpha = clamp(fill * (1.0 - border) + border, 0.0, 1.0);
	// Gentle breathing flicker (name-plate cells) — 0 strength leaves icon cells untouched.
	float flicker = 1.0 - flicker_strength * (0.5 + 0.5 * sin(TIME * flicker_speed + flicker_phase));
	COLOR = vec4(scan_color.rgb, alpha * scan_color.a * flicker);
}
