shader_type spatial;
uniform vec4 base_color : source_color = vec4(.5,.3,.2,1);
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    float strata=sin(world_position.y*4.2+sin(world_position.x*.7)*.4+sin(world_position.z)*.2);
    float broad=sin(world_position.x*1.2+world_position.z*2.3)*.06;
    float stone=fract(sin(dot(floor(world_position.xz*35.0),vec2(127.1,311.7)))*43758.5453);
    ALBEDO=base_color.rgb*(.76+.13*strata+broad+.035*stone);
    ROUGHNESS=.95;
}
