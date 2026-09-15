shader_type spatial;
uniform vec4 deep_color : source_color = vec4(.08,.38,.42,1);
uniform vec4 crest_color : source_color = vec4(.29,.65,.64,1);
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p=world_position.xz;
    float wave=sin(p.x*.8+p.y*.5+TIME*.7)*sin(p.y*1.4-p.x*.25-TIME*.5);
    float ripple=pow(max(0.0,sin(p.x*2.3+p.y*3.0+wave*.4+TIME*.45)),24.0);
    ALBEDO=mix(deep_color.rgb,crest_color.rgb,.27+wave*.18)+ripple*.045;
    ROUGHNESS=.25;
    METALLIC=.18;
}
