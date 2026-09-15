shader_type spatial;
render_mode specular_schlick_ggx;
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
float relief(vec2 p) {
 vec2 q=p/vec2(.68,.42); q.x+=mod(floor(q.y),2.0)*.5;
 vec2 f=fract(q); float edge=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
 return smoothstep(.025,.15,edge)*(.065+.012*noise(p*15.0));
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p=world_position.xz;
 vec2 q=p/vec2(.68,.42); q.x+=mod(floor(q.y),2.0)*.5;
 float stone=hash(floor(q)); float h=relief(p);
 float wet=smoothstep(.48,.7,noise(p*.16));
 vec3 color=mix(vec3(.16,.20,.23),vec3(.31,.35,.37),stone);
 float curb=1.0-smoothstep(.12,.5,min(abs(abs(p.x)-9.5),abs(abs(p.y)-9.5)));
 float moss=curb*smoothstep(.47,.7,noise(p*1.1))*.58;
 color=mix(color,vec3(.13,.21,.15),moss);
 ALBEDO=color*(.46+smoothstep(0.0,.052,h)*.54)*(1.0-wet*.24);
 ROUGHNESS=mix(.68,.25,wet); SPECULAR=.65;
 float e=.018;
 vec3 n=normalize(vec3((relief(p-vec2(e,0))-relief(p+vec2(e,0)))/(e*2.0),1.0,(relief(p-vec2(0,e))-relief(p+vec2(0,e)))/(e*2.0)));
 NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
}
