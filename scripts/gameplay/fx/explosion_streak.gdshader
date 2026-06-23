shader_type canvas_item;
render_mode blend_add, unshaded;
// OPTIONAL streak shader (off by default; enabled via Explosion.streak_use_4cell). Replicates the 3D tutorial's
// "pick 1 of 4 streak cells per particle" trick: each particle gets a random RED channel (CPUParticles2D hue
// variation), and that red value selects one quarter of a 4-cell horizontal streak sheet via a UV.x offset.
// When this shader is NOT used, the streaks fall back to a single procedural streak texture + velocity
// alignment (the simpler, robust default).

void fragment() {
	float cell = floor(clamp(COLOR.r, 0.0, 0.999) * 4.0);   // 0..3 from the per-particle red channel
	vec2 uv = UV;
	uv.x = uv.x * 0.25 + cell * 0.25;                       // map UV.x into the chosen quarter of the sheet
	vec4 t = texture(TEXTURE, uv);
	float a = t.a * max(t.r, max(t.g, t.b));                // keep additive-clean (works opaque-on-black too)
	COLOR = vec4(COLOR.rgb, a);                             // COLOR.rgb carries the additive streak tint
}
