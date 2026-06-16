shader_type canvas_item;
// Diagnostic: render the warped density field with GRADIENT noise (use_simplex=0) vs SIMPLEX (=1) so we can
// see whether the straight facets are intrinsic to the square-grid gradient noise (cured by simplex).

uniform vec2 world_offset = vec2(0.0);
uniform int  use_simplex = 0;
const float base_scale = 2.0;
const float warp_strength = 3.0;
const int octaves = 6;

float hash(vec2 p){ vec3 p3=fract(vec3(p.xyx)*0.1031); p3+=dot(p3,p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
vec2 grad(vec2 ip){ float a=hash(ip)*6.28318530718; return vec2(cos(a),sin(a)); }
float gnoise(vec2 p){
	vec2 i=floor(p); vec2 f=fract(p);
	vec2 u=f*f*f*(f*(f*6.0-15.0)+10.0);
	float a=dot(grad(i+vec2(0.0,0.0)),f-vec2(0.0,0.0));
	float b=dot(grad(i+vec2(1.0,0.0)),f-vec2(1.0,0.0));
	float c=dot(grad(i+vec2(0.0,1.0)),f-vec2(0.0,1.0));
	float d=dot(grad(i+vec2(1.0,1.0)),f-vec2(1.0,1.0));
	return mix(mix(a,b,u.x),mix(c,d,u.x),u.y)*0.5+0.5;
}
vec3 mod289(vec3 x){return x-floor(x*(1.0/289.0))*289.0;}
vec2 mod289(vec2 x){return x-floor(x*(1.0/289.0))*289.0;}
vec3 permute(vec3 x){return mod289(((x*34.0)+1.0)*x);}
float snoise(vec2 v){
	const vec4 C=vec4(0.211324865405187,0.366025403784439,-0.577350269189626,0.024390243902439);
	vec2 i=floor(v+dot(v,C.yy));
	vec2 x0=v-i+dot(i,C.xx);
	vec2 i1=(x0.x>x0.y)?vec2(1.0,0.0):vec2(0.0,1.0);
	vec4 x12=x0.xyxy+C.xxzz; x12.xy-=i1;
	i=mod289(i);
	vec3 p=permute(permute(i.y+vec3(0.0,i1.y,1.0))+i.x+vec3(0.0,i1.x,1.0));
	vec3 m=max(0.5-vec3(dot(x0,x0),dot(x12.xy,x12.xy),dot(x12.zw,x12.zw)),0.0);
	m=m*m; m=m*m;
	vec3 x=2.0*fract(p*C.www)-1.0;
	vec3 h=abs(x)-0.5;
	vec3 ox=floor(x+0.5);
	vec3 a0=x-ox;
	m*=1.79284291400159-0.85373472095314*(a0*a0+h*h);
	vec3 g;
	g.x=a0.x*x0.x+h.x*x0.y;
	g.yz=a0.yz*x12.xz+h.yz*x12.yw;
	return 130.0*dot(m,g);
}
float noise(vec2 p){ return (use_simplex==1) ? (snoise(p)*0.5+0.5) : gnoise(p); }
float fbm(vec2 p, int oct){
	float v=0.0, amp=0.5, norm=0.0;
	mat2 rot=mat2(vec2(0.80,0.60),vec2(-0.60,0.80));
	p=rot*p;
	for(int k=0;k<8;k++){ if(k>=oct){break;} v+=amp*noise(p); norm+=amp; p=rot*p*2.0; amp*=0.5; }
	return v/max(norm,0.0001);
}
void fragment(){
	vec2 p=UV*base_scale+world_offset;
	vec2 q=vec2(fbm(p,octaves),fbm(p+vec2(5.2,1.3),octaves));
	vec2 r=vec2(fbm(p+warp_strength*q+vec2(1.7,9.2),octaves), fbm(p+warp_strength*q+vec2(8.3,2.8),octaves));
	float dens=fbm(p+warp_strength*r,octaves);
	COLOR=vec4(vec3(dens),1.0);
}
