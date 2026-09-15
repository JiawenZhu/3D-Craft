shader_type spatial;
render_mode cull_disabled;
uniform sampler2D skin : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color=vec4(1.0);
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_map : filter_linear_mipmap_anisotropic;
uniform bool has_normal=false;
uniform bool has_roughness=false;
uniform bool has_metallic=false;
uniform float normal_strength=1.0;
uniform float roughness_value=.74;
uniform float metallic_value=0.0;
uniform float phase=0.0;
uniform float running=0.0;
void vertex(){
    float foot=1.0-smoothstep(-.65,-.28,VERTEX.y);
    float side=sign(VERTEX.x);
    VERTEX.z+=sin(phase*12.0+side*1.5708)*.13*foot*running;
    VERTEX.y+=max(0.0,cos(phase*12.0+side*1.5708))*.085*foot*running;
    float arm=smoothstep(.28,.48,abs(VERTEX.x))*smoothstep(-.65,-.35,VERTEX.y)*(1.0-smoothstep(.05,.3,VERTEX.y));
    VERTEX.z+=sin(phase*12.0-side*1.5708)*.11*arm*running;
    float tail=(1.0-smoothstep(-.4,-.2,VERTEX.z))*(1.0-smoothstep(-.35,.05,VERTEX.y));
    VERTEX.x+=sin(phase*3.0+VERTEX.z*6.0)*.018*tail;
}
void fragment(){ALBEDO=texture(skin,UV).rgb*tint.rgb;ROUGHNESS=roughness_value*(has_roughness ? texture(roughness_map,UV).g : 1.0);METALLIC=metallic_value*(has_metallic ? texture(metallic_map,UV).b : 1.0);SPECULAR=.25;if(has_normal){NORMAL_MAP=texture(normal_map,UV).rgb;NORMAL_MAP_DEPTH=normal_strength;}}
