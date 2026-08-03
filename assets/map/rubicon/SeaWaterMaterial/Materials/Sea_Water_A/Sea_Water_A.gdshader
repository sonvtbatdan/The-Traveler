/* 
 * Title : Sea Water Base Shader
 * Author : Michael Herman
 * Desc : This code is the foundation for other derivative style
 * Last Updated : 15/02/2022
 * Version : 1.0
*/

shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// User assigned uniforms
uniform float uv_scale : hint_range(0.0, 100.0, 0.1) = 10.0;
uniform float texture_lod : hint_range(0.0, 10.0, 0.1) = 0.0;
uniform vec4 base_color_a : hint_color = vec4(0.0, 0.6, 1.0, 1.0);
uniform vec4 base_color_b : hint_color = vec4(0.0, 0.6, 0.9, 1.0);
uniform vec4 shallow_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.1;
uniform float metallic : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform float rim : hint_range(0.0, 1.0, 0.1) = 0.1;
uniform bool hide_foam = false;
uniform vec4 foam_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float foam_detail : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform float foam_dynamic : hint_range(0.0, 10.0) = 1.0;
uniform float foam_strength : hint_range(0.0, 10.0) = 1.0;
uniform bool hide_refraction = false;
uniform float refraction_detail : hint_range(0.0, 10.0, 0.1) = 5.0;
uniform float refraction_dynamic : hint_range(0.0, 10.0, 0.1) = 0.5;
uniform float refraction_strength : hint_range(0.0, 10.0, 0.01) = 5.0;
uniform float wave_speed : hint_range(0.0, 10.0, 0.1) = 1.0;
uniform float wave_length : hint_range(1.0, 200.0, 0.01) = 10.0;
uniform float wave_height : hint_range(0.0, 50.0, 0.01) = 0.1;
uniform vec2 wave_direction = vec2(1.0, 0.0);
uniform float wave_turbulence : hint_range(0.0, 1.5) = 0.5;
uniform float wave_sharpness : hint_range(0.0, 2.0, 0.1) = 0.7;
uniform float ground_visibility : hint_range(0.0, 100.0, 0.1) = 1.0;
uniform float ground_influence : hint_range(0.0, 5.0, 0.01) = 0.5;
uniform bool use_ground_average = false;
uniform bool use_center_average = false;
uniform bool show_influence_mask = false;
uniform bool show_normals = true;
// Script assigned uniforms
uniform sampler2D noise;
uniform sampler2D grounds_arr;
uniform int grounds_arr_length;
uniform vec2 mesh_size = vec2(100.0, 100.0);
uniform vec3 ground_position = vec3(0.0, 0.0, 0.0);

const vec3 BLUE = vec3(0.0, 0.5, 1.0);
const vec3 GREEN = vec3(0.0, 1.0, 0.2);
const vec3 RED = vec3(1.0, 0.0, 0.1);
const vec3 BLACK = vec3(0.0,0.0,0.0);
const vec3 WHITE = vec3(1.0,1.0,1.0);
const float PI = 3.14159;
const float INF = 1.0 / 0.0;

varying float wave_mask;
varying float distance_mask;
varying float influence_map;
//varying float noise_value;
varying float size_factor;
varying float power_factor;


/* -----------------
 * Utility Functions 
 * ----------------*/

float log10(float x) {
	// return result of base 10 logarithm of x
	return log(x) / log(10.0);
}

float random (vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

mat3 tbn(float y){
	vec3 tangent = vec3(1.0, y, 0.0);
	vec3 bitangent = vec3(0.0, y, 1.0);
	vec3 normal = cross(bitangent, tangent);
	return mat3(tangent, bitangent, normal);
}

vec2 map_ndc(vec2 uv) {
	// Map UV from range (0-1) to range(-1,1)
	return (uv * 2.0) - 1.0;
}

vec2 linear_uv_panner(vec2 uv, vec2 direction, float speed, float t){
	return (map_ndc(uv) + (normalize(direction) * speed * t));
}

vec2 circular_uv_panner(vec2 uv, float r, float t){
	return map_ndc(uv) + (r * vec2(cos(t), sin(t)));
}

vec2 rotated2D(vec2 uv, float angle){
	mat2 R = mat2(vec2(sin(angle), -cos(angle)),
						vec2(cos(angle), sin(angle)));
	return R * uv;
}

vec4 fetch_array_data(sampler2D arr, ivec2 index){
	return texelFetch(arr, index, 0).rgba;
}

float turbulence_noise(sampler2D _noise, vec2 uv, float scale, float turbulence){
	vec4 nv = textureLod(_noise, uv * scale, texture_lod);
	nv = abs(nv - 0.5);
	float sum = (nv.r + nv.g + nv.b + nv.a);
	return 1.0-clamp(sum * turbulence, 0.0, 1.0);
}

float marble_noise(sampler2D _noise, vec2 uv, float scale, float turbulence){
	vec4 nv = textureLod(_noise, uv * scale * 0.5, texture_lod);
	nv = abs(nv - 0.5);
	float sum = nv.r + nv.g + nv.b + nv.a;
	sum = clamp(sum, 0.0, 1.0);
	float x = dot(uv * turbulence, wave_direction);
	float strength = sum * (turbulence * 2.0);
	return (1.0 + foam_strength) * sin(x + strength);
}

float grid_noise(sampler2D _noise, vec2 uv, float scale, float turbulence, float sharpness, float angle){
	uv = rotated2D(uv, angle);
	float nv = textureLod(_noise, uv * (scale * 0.2) * turbulence, texture_lod).r;
	vec2 wv = 1.0-abs(sin((uv * scale) + nv));
	float f = pow(1.0 - pow(wv.y * wv.x, 0.5 * (1.0/sharpness)), 2.0);
	return f;
}

float refraction_noise(sampler2D _noise, vec2 uv, float scale){
	uv *= 0.1;
	float t = wave_speed * (4.0 / size_factor);
	float trb = 1.0 + (refraction_dynamic / 10.0);
	float str = refraction_strength;
	
	float r = str * turbulence_noise(_noise, linear_uv_panner(uv, vec2(1.0,0.0), t, TIME), scale, trb);
	r += turbulence_noise(_noise, linear_uv_panner(uv + vec2(3.2, 0.1), vec2(-1.0,0.0), t, TIME), scale, trb);
	r *= str * turbulence_noise(_noise, linear_uv_panner(uv, vec2(0.0,1.0), t, TIME), scale, trb - 0.3);
	//r += str * turbulence_noise(_noise, linear_uv_panner(uv + vec2(1.2, 2.0), vec2(0.0,-1.0), t, TIME), scale, trb);
	
	/*
	float r = str  * grid_noise(_noise, linear_uv_panner(uv, vec2(1.0,0.0), t, TIME), scale-2.0, trb, refraction_detail, 0.0);
	r *= str * grid_noise(_noise, linear_uv_panner(uv + vec2(10.0, 0.0), vec2(-1.0,0.0), t, TIME), scale + 1.0, trb, refraction_detail, 0.5);
	r *= str * grid_noise(_noise, linear_uv_panner(uv, vec2(1.0, 1.0), t, TIME), scale-1.0, trb, refraction_detail, 1.0);
	r *= str * grid_noise(_noise, linear_uv_panner(uv + vec2(20, 20), vec2(0.0,-1.0), t, TIME), scale, trb, refraction_detail, 2.5);
	*/
	return r;//step(0.7, r);
}

vec3 custom_mix(vec3 a, vec3 b, sampler2D _noise, vec2 uv, float scale) {
	uv = map_ndc(uv);
	float alpha = textureLod(_noise, uv * scale, scale).r;
	alpha = smoothstep(0.2, 0.8, alpha);
	return mix(a, b, alpha);
}

vec2 surface_to_ground_depth(sampler2D depth, vec4 fragcoord, vec2 screen_uv, mat4 inv_proj_mat, float height_scale){
	// Read depth texture values
	float d = texture(depth, screen_uv).r;
	vec3 ndc = vec3(screen_uv, d) * 2.0 - 1.0;
	vec4 view = inv_proj_mat * vec4(ndc, 1.0);
	
	// Depth difference between water surface and ground
	float surface = (fragcoord.z * height_scale) / fragcoord.w;
	float ground = -(view.z * height_scale) / view.w;
	float diff = ground - surface;
	float shallow_diff = clamp(diff, 0.0, 2.0);
	float shallower_diff = clamp(diff, 0.0, 1.0);
	return vec2(shallow_diff, shallower_diff);
}

vec2 generate_distance_mask(vec3 vertex){
	int col = grounds_arr_length;
	float final_distance = 0.0;
	vec2 center_of_mass = vec2(0.0, 0.0);
	float average_distance = 0.0;
	float shortest_distance_out = length(mesh_size); 	// outer influence (distance_mask)
	float shortest_distance_in = length(mesh_size); 	// inner influence (wave_mask)
	
	for(int x = 0; x < col; x++){
		vec4 position = fetch_array_data(grounds_arr, ivec2(x, 0));
		float d_out = distance(position.xz, vertex.xz) - (position.w / 1.5);
		float d_in = distance(position.xz, vertex.xz) - (position.w * 1.1);
		d_out = max(d_out, 1.0);
		d_in = max(d_in, 0.1);
		average_distance += d_out;
		shortest_distance_in = min(d_in, shortest_distance_in);
		shortest_distance_out = min(d_out, shortest_distance_out);
		center_of_mass += position.xz / float(col);
	}

	if (use_ground_average) {
		final_distance = average_distance / float(col);
		shortest_distance_in = final_distance;
	}else if(use_center_average){
		final_distance = distance(center_of_mass, vertex.xz);
		shortest_distance_in = final_distance;
	}else{
		final_distance = shortest_distance_out;
	}
	return vec2(final_distance, shortest_distance_in);
}

/* -----------------
 * Waves Functions 
 * ---------------- */

mat3 base_wave(float period, float wavelength, float amplitude, vec2 direction, float mask, vec3 vertex){
	float L = wavelength;
	float k = (2.0 * PI) / L;
	float w = 2.0 / period;
	float t = TIME;
	float x = dot(direction, vertex.xz); //(direction.x * vertex.x) + (direction.y * vertex.y);
	float carrier_y = pow(sin(mask), 3.5);
	float y = sin((k * x) - (w * t));
	float combined_y = amplitude * (carrier_y * y);
	float dydx = amplitude * k * cos((k * x) - (w * t)) * pow(sin(mask), 3.5);
	vec3 norm = tbn(dydx)[2];
	return mat3(vec3(combined_y), vec3(norm), vec3(0.0));
}

vec3 forward_wave(float period, float wavelength, float amplitude, vec2 direction, float mask, vec3 vertex){
	float w = 2.0 / period;
	float k = (2.0 * PI) / wavelength;
	float x = direction.x * vertex.z;
	float z = direction.y * vertex.x;
	float tx = direction.x * TIME;
	float tz = direction.y * TIME;
	float z_of_x = amplitude * cos((k * x) - (w * tx)); // z(x) = x
	float x_of_z = amplitude * cos((k * z) - (w * tz)); // x(z) = z
	return (vec3(z_of_x, 0.0 , x_of_z) * mask);
}

float detail_wave(sampler2D wavenoise, vec2 uv, float scale, float turbulence){
	float wave = 0.0;
	float v = wave_speed;
	float angle = atan(wave_direction.y / wave_direction.x);
	float variance = turbulence;
	vec2 pan_r = linear_uv_panner(uv, vec2(1.0, 0.0), (0.05 * v), TIME);
	vec2 pan_l = linear_uv_panner(uv, vec2(-1.0, 0.0), (0.05 * v), TIME);
	vec2 pan_up = linear_uv_panner(uv, vec2(0.0, 1.0), (0.05 * v), TIME);
	vec2 pan_down = linear_uv_panner(uv, vec2(0.0, -1.0), (0.013 * v), TIME);
	vec2 pan_diagonal = linear_uv_panner(uv, vec2(1.0, 1.0), (0.011 * v), TIME);
	wave += grid_noise(wavenoise, pan_r, scale, turbulence, wave_sharpness, angle + variance);
	wave += grid_noise(wavenoise, pan_l + vec2(1.0, 1.0), scale, turbulence, wave_sharpness, angle + variance);
	wave += grid_noise(wavenoise, pan_up, scale, turbulence,wave_sharpness, angle - variance);
	wave += grid_noise(wavenoise, pan_down + vec2(-1.0, -1.0), scale, turbulence, wave_sharpness, angle + variance);
	wave += grid_noise(wavenoise, pan_diagonal, scale + 2.0, turbulence, wave_sharpness, angle - variance);
	return wave;
}

mat3 detail_wave_with_normals(sampler2D wavenoise, vec2 uv, float scale, float turbulence){
	float d = detail_wave(wavenoise, uv, scale, turbulence);
	float dx = detail_wave(wavenoise, uv + vec2(1.0/size_factor, 0.0), scale, turbulence);
	float dz = detail_wave(wavenoise, uv + vec2(0.0, 1.0/size_factor), scale, turbulence);
	vec3 wn = vec3(d - dx, 0.1, d - dz);
	return mat3(vec3(d), wn, vec3(dx, 0.0, dz));
}


/* -----------------
 * Built-in Functions 
 * ---------------- */

void vertex(){
	power_factor = log10(mesh_size.x);
	size_factor = pow(10.0, power_factor);
	
	vec3 world_vertex = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 distance_map = generate_distance_mask(world_vertex) / size_factor;
	float distance_to_ground = pow(distance_map.x, ground_influence / 10.0);
	wave_mask = pow(distance_map.y, ground_influence / 10.0);

	mat3 wave_a = base_wave(1.0 / wave_speed, 
				wave_length * distance_to_ground, 
				wave_height, normalize(wave_direction), 
				wave_mask, VERTEX);
	vec3 wave_b = forward_wave(1.0 / (wave_speed * 0.5), 
				wave_length * (4.0),
				wave_height * (2.0),
				normalize(wave_direction), 
				1.0-smoothstep(0.3, 0.95, wave_mask), VERTEX);
	mat3 wave_c = detail_wave_with_normals(noise, UV, uv_scale * (wave_turbulence * 0.1), wave_turbulence);
	
	VERTEX.y += wave_a[0].r;
	VERTEX.y += wave_c[0].r * wave_sharpness * wave_turbulence;
	VERTEX.z += wave_b.z;
	VERTEX.x += wave_b.x;
	if(show_normals) {
		NORMAL = wave_a[1];
		NORMAL += normalize(wave_c[1]);
	}
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	
	distance_mask = smoothstep(-1.5, 0.8, pow(distance_to_ground, 2.0));
	wave_mask = smoothstep(0.5, 0.8, wave_mask);
	influence_map = smoothstep(.8, .9, distance_to_ground);
}

void fragment(){
	float _distance_mask = (wave_mask + distance_mask) / 2.0;
	vec2 depth = surface_to_ground_depth(DEPTH_TEXTURE, FRAGCOORD, SCREEN_UV, INV_PROJECTION_MATRIX, 1.0/ground_visibility);
	vec3 shallow = vec3(2.0 - depth.x) * shallow_color.rgb;
	
	float refraction = refraction_noise(noise, UV, uv_scale * (refraction_detail/10.0));
	float foam = marble_noise(noise, 
				linear_uv_panner(UV, (-1.0 * wave_direction), (wave_speed * 2.0) / size_factor, TIME), 
				uv_scale * (foam_detail/10.0), 
				foam_dynamic);
	//foam = clamp(foam, 0.0, 5.0);
	foam = smoothstep(0.5,0.7, foam);
	
	if(grounds_arr_length == 0) {
		_distance_mask = depth.y;
	}
	
	if (show_influence_mask){
		vec3 mix_1 = (vec3(1.0-influence_map) * RED) + (vec3(1.0-wave_mask) * BLUE);
		ALBEDO = mix_1 + BLACK;
	}else{
		vec3 foam_mix = vec3(foam * (1.0 - _distance_mask)) * foam_strength * foam_color.rgb;
		vec3 base_mix = vec3(shallow) + base_color_a.rgb;
		vec3 refraction_mix = vec3(refraction * (1.0 - _distance_mask)) * (refraction_strength);// * smoothstep(0.1, 0.9, (1.0-dot(VIEW, NORMAL))));
		
		if (hide_refraction) refraction_mix = vec3(0.0);
		if (hide_foam) foam_mix = vec3(0.0);
		
		vec3 water_mix = foam_mix + base_mix + refraction_mix;
		ALBEDO = custom_mix(base_color_b.rgb, water_mix, noise, UV, (uv_scale * 1.0) / size_factor);
		ALPHA = pow(depth.y, 0.1 * power_factor);
		//ALBEDO = vec3(refraction);
	}
	
	METALLIC = metallic;
  	ROUGHNESS = roughness * sqrt(1.0 - dot(NORMAL, VIEW));
	RIM = rim;
}