shader_type canvas_item;
// Green "wave column" XP progress fill that grows left→right to `progress` (0..1), with a soft
// glowing leading edge and an animated vertical wave shimmer. Drawn inside the levelband frame.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.18, 0.85, 0.32, 1.0);
uniform vec4 glow_color : source_color = vec4(0.45, 1.0, 0.55, 1.0);
uniform float wave_speed = 5.0;
uniform float wave_freq  = 26.0;

void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	float x = UV.x;

	// Body: filled where x < p. Animated wavy shimmer along the column (moving right).
	float inside = step(x, p);
	float shimmer = 0.80 + 0.20 * sin(x * wave_freq - TIME * wave_speed);
	// Gentle vertical wave so the band reads as flowing energy, not a flat bar.
	float vwave = 0.88 + 0.12 * sin(UV.y * 8.0 + x * 18.0 - TIME * (wave_speed * 0.7));
	vec3 body = fill_color.rgb * shimmer * vwave;

	// Soft glow hugging the leading edge (slightly spills past `progress`).
	float d = abs(p - x);
	float glow = smoothstep(0.07, 0.0, d) * (p > 0.001 ? 1.0 : 0.0);

	vec3 col = body * inside + glow_color.rgb * glow * 0.7;
	float a = fill_color.a * inside;
	a = max(a, glow * glow_color.a * 0.8);
	COLOR = vec4(col, a);
}
