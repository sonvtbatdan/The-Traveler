/* 
 * Title : Sea Water D Shader
 * Author : Michael Herman
 * Desc : Variance on Sea Water A, Oriental Stylized
 * Last Updated : 15/02/2022
*/

shader_type spatial;

// User assigned uniforms
uniform float uv_scale : hint_range(0.0, 100.0, 0.1) = 10.0;
uniform float texture_lod : hint_range(0.0, 10.0, 0.1) = 1.0;
uniform vec4 base_color_a : hint_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform vec4 base_color_b : hint_color = vec4(0.0, 0.5, 0.9, 1.0);
uniform vec4 shallow_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0, 0.1) = 0.5;
uniform float reflectiveness : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float rim : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform bool hide_foam = false;
uniform vec4 foam_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float foam_detail : hint_range(-10.0, 10.0, 0.1) = 1.0;
uniform float foam_strength : hint_range(0.0, 30.0) = 2.0;
uniform vec4 rim_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0, 0.1) = 1.0;
uniform float wave_length : hint_range(1.0, 200.0, 0.01) = 10.0;
uniform float wave_height : hint_range(0.0, 50.0, 0.01) = 0.07;
uniform vec2 wave_direction = vec2(1.0, 0.0);
uniform float wave_turbulence : hint_range(0.0, 1.0) = 0.5;
uniform float ground_visibility : hint_range(0.1, 100.0, 0.1) = 1.0;
uniform float ground_influence : hint_range(0.0, 5.0, 0.01) = 0.5;
uniform bool use_ground_average = false;
uniform bool use_center_average = false;
uniform bool show_influence_mask = false;
uniform bool show_normals = true;
// Script assigned uniforms
uniform sampler2D noise;
uniform sampler2D noise_wave_height;
uniform sampler2D noise_wave_norm;
uniform sampler2D noise_wave_base;
uniform sampler2D noise_foam_base;
uniform sampler2D grounds_arr;
uniform int grounds_arr_length;
uniform vec2 mesh_size = vec2(100.0, 100.0);
uniform vec3 ground_position = vec3(0.0, 0.0, 0.0);

const vec3 BLUE = vec3(0.0, 0.5, 1.0);
const vec3 GREEN = vec3(0.0, 1.0, 0.2);
const vec3 RED = vec3(1.0, 0.0, 0.1);
const vec3 BLACK = vec3(-1.0, -1.0, -1.0);
const vec3 WHITE = vec3(1.0,1.0,1.0);
const float PI = 3.14159;
const float INF = 1.0 / 0.0;

varying float wave_mask;
varying float influence_map;
varying float size_factor;
varying float power_factor;


/* -----------------
 * Utility Functions 
 * ----------------*/

float log10(float x) {
	// return result of base 10 logarithm of x
	return log(x) / log(10.0);
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

vec3 map_ndc3(vec3 uv) {
	return (uv * 2.0) - 1.0;
}

vec2 linear_uv_panner(vec2 uv, vec2 direction, float speed, float t){
	return (map_ndc(uv) + (normalize(direction) * speed * t));
}

vec2 circular_uv_panner(vec2 uv, float r, float t){
	return map_ndc(uv) + (r * vec2(cos(t), sin(t)));
}

int check_vector_quadrant(vec2 dir){
	if(dir.x > 0.0 && dir.y >= 0.0){
		return 4;
	}else if(dir.x <= 0.0 && dir.y > 0.0){
		return 3;
	}else if(dir.x < 0.0 && dir.y <= 0.0){
		return 2;
	}else if(dir.x >= 0.0 && dir.y < 0.0){
		return 1;
	}else{
		return 4;
	}
}

float vector_angle(vec2 dir){
	float angle = atan(abs(dir.y) / abs(dir.x));
	switch (check_vector_quadrant(dir)) {
		case 2 : angle = PI - angle; break;
		case 3 : angle = PI + angle; break;
		case 4 : angle = 2.0 * PI - angle; //;(0.0) - angle; break; 
		default : break;
	}
	return angle;
}

vec2 rotated2D(vec2 uv, float angle){
	mat2 R = mat2(vec2(sin(angle), -cos(angle)),
						vec2(cos(angle), sin(angle)));
	return R * uv;
}

vec4 fetch_array_data(sampler2D arr, ivec2 index){
	return texelFetch(arr, index, 0).rgba;
}

float foam_noise(sampler2D _noise, vec2 uv, vec2 dir,float scale) {
	float angle = vector_angle(dir);
	float f1 = textureLod(_noise, rotated2D(uv, angle) * scale, texture_lod).r;
	return f1;
}

float glitter_noise(sampler2D _noise, vec2 uv, float scale){
	float g = textureLod(_noise, linear_uv_panner(uv * scale, vec2(1.0, 1.0), wave_speed/10.0, TIME), texture_lod).r;
	float g2 = textureLod(_noise, linear_uv_panner(uv * scale / 2.0, vec2(-10.0, 10.0), wave_speed/10.0, TIME), texture_lod).r;
	g = smoothstep(0.65, 0.85, g);
	g2 = smoothstep(0.65, 0.85, g2);
	g *= abs(sin(TIME * wave_speed));
	g2 *= abs(-1.0 * sin(TIME * wave_speed + (PI/1.15)));
	return (g * 2.0) + g2;
}

vec3 custom_mix(vec3 a, vec3 b, sampler2D _noise, vec2 uv, float scale) {
	uv = map_ndc(uv);
	float alpha = textureLod(_noise, uv * scale, scale).r;
	alpha = smoothstep(0.3, 0.8, alpha);
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
		float d_in = distance(position.xz, vertex.xz) - (position.w / 1.0);
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
 * Rendering Functions 
 * ---------------- */


vec3 schlick_approximation(vec3 fo, vec3 l, vec3 h){
	return fo + (1.0 - fo) * (1.0 - pow(dot(l, h), 5.0));
}

float ggx_distribution(vec3 n, vec3 h, float r){
	return pow(r, 4.0) / 
			(PI * 
				(pow(
					(pow(dot(n, h), 2.0) * (pow(r, 4.0) - 1.0)) + 1.0, 
				2.0))
			);
}

float geom(float nDotx, float r){
	float k = pow(r + 2.0, 2.0) / 8.0;
	return nDotx / k + (nDotx * (1.0 - k));
}

vec3 SPEC_BRDF(vec3 l, vec3 n, vec3 v, float r) {
	//Specular BRDF
	vec3 h = normalize(l + v);
	float g1 = geom(dot(n, v), r);
	float g2 = geom(max(0.0, dot(n, l)), r);
	vec3 fs = 0.25 * schlick_approximation(vec3(0.05), l, h) * (g1 * g2) * (ggx_distribution(n, h, r));
	return smoothstep(0.1, 0.7, (0.1 * PI * fs)) * (reflectiveness * 10.0);
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

mat3 detail_wave(sampler2D wavenoise, sampler2D wavenormal, vec2 uv, float scale, float turbulence){
	float angle = vector_angle(wave_direction);
	vec2 pan_default = rotated2D(linear_uv_panner(uv * scale, -wave_direction, (0.1 * wave_speed), TIME), angle);
	float wave = textureLod(wavenoise, pan_default, texture_lod + (1.0/turbulence)).r;
	vec3 wave_normal = textureLod(wavenormal, pan_default, texture_lod + (1.0/turbulence)).rgb;
	wave_normal = tbn(0.0) * normalize(map_ndc3(wave_normal));
	
	return mat3(vec3(wave), normalize(wave_normal), vec3(0.0));
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
	mat3 wave_c = detail_wave(noise_wave_height, noise_wave_norm, UV,
				wave_turbulence * uv_scale, wave_turbulence);
	
	VERTEX.y += wave_a[0].r;
	VERTEX.y += wave_c[0].r;
	VERTEX.z += wave_b.z;
	VERTEX.x += wave_b.x;
	if(show_normals) {
		NORMAL = wave_a[1];
		NORMAL += wave_c[1] * 1.0;
	}
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	
	wave_mask = smoothstep(0.3, 0.95, wave_mask);
	influence_map = smoothstep(.8, .9, distance_to_ground);
}

void fragment(){
	vec2 depth = surface_to_ground_depth(DEPTH_TEXTURE, FRAGCOORD, SCREEN_UV, INV_PROJECTION_MATRIX, 1.0/ground_visibility);
	vec3 shallow = vec3(2.0-depth.x) * (shallow_color.rgb * 2.0 - 1.0);
	float glitters = glitter_noise(noise, UV, uv_scale);
	float canvas_texture = texture(noise_wave_base, UV * (uv_scale * 0.1)).r * 0.8;
	float foam = foam_noise(noise_foam_base,
				linear_uv_panner(UV, -1.0 * wave_direction, wave_speed * 0.01, TIME),
				wave_direction,
				(uv_scale + foam_detail) * 0.1);
	foam += 0.2 * foam_noise(noise_foam_base,
			linear_uv_panner(UV, wave_direction, wave_speed * 0.01, TIME),
			wave_direction * -1.0,
			(uv_scale + foam_detail) * 0.1);

	float foam_mask = pow(influence_map, .2);
	if (grounds_arr_length == 0) {
		// if no grounds registered, use water depth mask
		foam_mask = pow(depth.y, 0.8);
	}
	
	if (show_influence_mask){
		vec3 mix_1 = (vec3(1.0-influence_map) * RED) + (vec3(1.0-wave_mask) * BLUE);
		ALBEDO = mix_1 + BLACK;
	}else{
		vec3 foam_mix = foam_strength * (vec3(foam * (1.0-foam_mask)) * foam_color.rgb);
		vec3 base_mix = custom_mix(base_color_b.rgb, base_color_a.rgb, noise_wave_base, UV, uv_scale) + vec3(shallow);
		
		if (hide_foam) foam_mix = vec3(0.0);
		
		vec3 water_mix = (foam_mix + base_mix) * canvas_texture;
		ALBEDO = water_mix;
		ALPHA = pow(depth.y, 0.2);
	}
	ROUGHNESS = roughness * sqrt(1.0-dot(NORMAL, VIEW));
}

void light(){
	float vDotn = dot(VIEW, NORMAL);
	vec3 fd = ATTENUATION * ALBEDO * max(0.0, dot(NORMAL, LIGHT));
	vec3 fs = ATTENUATION * SPEC_BRDF(LIGHT, NORMAL, VIEW, roughness) * max(0.0, dot(NORMAL, LIGHT));
	vec3 fr = (rim_color.rgb * 2.0 - 1.0) * smoothstep(0.1, rim, pow(1.0-vDotn, 8.0));
	DIFFUSE_LIGHT += fd;
	DIFFUSE_LIGHT += fr;
	SPECULAR_LIGHT += fs;
}



