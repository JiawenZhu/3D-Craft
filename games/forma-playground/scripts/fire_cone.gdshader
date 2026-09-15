shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
varying vec2 flame_uv;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){
    flame_uv=UV;
    float ripple=1.0+sin(UV.y*32.0-TIME*24.0+UV.x*12.0)*.12*UV.y;
    VERTEX.xz*=ripple;
}
void fragment(){
    float n=noise(vec2(flame_uv.x*9.0,flame_uv.y*14.0-TIME*9.0));
    float core=1.0-flame_uv.y;
    ALBEDO=mix(vec3(1.0,.16,.008),vec3(1.0,.88,.27),core*core);
    ALPHA=smoothstep(.15,.85,n)*sin(flame_uv.y*3.14159)*.56*(1.0-smoothstep(.65,1.0,flame_uv.y));
}
