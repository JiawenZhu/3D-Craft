shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
void vertex(){
    vec3 sizes=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
    MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*sizes.x,INV_VIEW_MATRIX[1]*sizes.y,INV_VIEW_MATRIX[2]*sizes.z,MODEL_MATRIX[3]);
}
void fragment(){
    vec2 p=UV-.5;
    float ripple=sin(p.x*27.0+TIME*19.0)*sin(p.y*31.0-TIME*13.0)*.045;
    float fade=pow(max(0.0,1.0-length(p)*2.0+ripple),2.0);
    ALBEDO=COLOR.rgb;
    ALPHA=COLOR.a*fade*.65;
}
