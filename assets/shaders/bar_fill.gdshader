shader_type canvas_item;
// Bar VFX fill — a colored "wave column" that grows to `progress` (0..1) along `grow_dir`, MASKED by
// the band sprite's own alpha (TEXTURE). It only paints the band's non-transparent pixels and never
// spills past them, so the band silhouette IS the crop frame. Used for HP (red) / Shield (blue) /
// Level (green) bars. Same shimmer + leading-edge glow as level_fill.gdshader.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.18, 0.85, 0.32, 1.0);
uniform vec4 glow_color : source_color = vec4(0.45, 1.0, 0.55, 1.0);
uniform int  grow_dir = 0;                     // 0=Left→Right, 1=Right→Left, 2=Bottom→Top, 3=Top→Bottom
uniform float wave_speed = 5.0;
uniform float wave_freq  = 26.0;
uniform float mask_cutoff : hint_range(0.0, 1.0) = 0.02;

void fragment() {
	float mask = texture(TEXTURE, UV).a;       // band shape: alpha 0 → nothing drawn here
	if (mask <= mask_cutoff) {
		COLOR = vec4(0.0);
	} else {
		// Progress axis t: 0 at the growth origin, 1 at the far end.
		float t;
		if (grow_dir == 1)      t = 1.0 - UV.x; // right → left
		else if (grow_dir == 2) t = 1.0 - UV.y; // bottom → top
		else if (grow_dir == 3) t = UV.y;       // top → bottom
		else                    t = UV.x;       // left → right (default)
		// Perpendicular axis (for the gentle cross-wave shimmer).
		float perp = (grow_dir >= 2) ? UV.x : UV.y;

		float p = clamp(progress, 0.0, 1.0);
		float inside = step(t, p);
		float shimmer = 0.80 + 0.20 * sin(t * wave_freq - TIME * wave_speed);
		float vwave = 0.88 + 0.12 * sin(perp * 8.0 + t * 18.0 - TIME * (wave_speed * 0.7));
		vec3 body = fill_color.rgb * shimmer * vwave;

		// Soft glow hugging the leading edge (spills slightly past `progress`, still clipped by mask).
		float d = abs(p - t);
		float glow = smoothstep(0.07, 0.0, d) * (p > 0.001 ? 1.0 : 0.0);

		vec3 col = body * inside + glow_color.rgb * glow * 0.7;
		float a = fill_color.a * inside;
		a = max(a, glow * glow_color.a * 0.8);
		COLOR = vec4(col, a * mask);            // clip alpha to the band silhouette
	}
}
