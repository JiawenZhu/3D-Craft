shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.5, 0.4, 0.3, 1.0);
uniform float grain_scale = 1.0;
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p=world_position.xz*grain_scale;
    float broad=noise(p*.35);
    float detail=noise(p*4.0);
    float grain=hash(floor(p*70.0));
    ALBEDO=base_color.rgb*COLOR.rgb*(.77+.3*broad+.14*detail+.035*grain);
    ROUGHNESS=.94;
}
