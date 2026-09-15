shader_type spatial;
render_mode cull_disabled;
uniform sampler2D skin : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float phase = 0.0;
uniform float flight = 0.0;
uniform float running = 0.0;
uniform float breathing = 0.0;
void vertex() {
    vec3 p=VERTEX;
    float side=sign(p.x);
    float wing=smoothstep(.20,.34,abs(p.x))*(1.0-smoothstep(.04,.13,p.y))*smoothstep(-.24,-.14,p.y);
    float flap=sin(phase*10.0)*.8*flight*side;
    vec2 arm=p.xy-vec2(side*.19,-.025);
    p.xy+=wing*(mat2(vec2(cos(flap),sin(flap)),vec2(-sin(flap),cos(flap)))*arm-arm);
    float foot=(1.0-smoothstep(-.40,-.28,p.y))*smoothstep(.10,.18,abs(p.x))*smoothstep(-.08,.05,p.z);
    p.z+=sin(phase*13.0+side*1.57)*.065*running*foot;
    p.y+=max(0.0,cos(phase*13.0+side*1.57))*.045*running*foot;
    float tail=(1.0-smoothstep(-.32,-.22,p.y))*(1.0-smoothstep(-.22,-.08,p.z));
    p.x+=sin(phase*4.0+p.z*8.0)*.045*tail;
    float jaw=smoothstep(.22,.30,p.z)*(1.0-smoothstep(-.03,.04,p.y))*smoothstep(-.15,-.09,p.y);
    p.y-=jaw*breathing*.025;
    VERTEX=p;
}
void fragment(){ ALBEDO=texture(skin,UV).rgb*tint.rgb; ROUGHNESS=.68; SPECULAR=.35; }
