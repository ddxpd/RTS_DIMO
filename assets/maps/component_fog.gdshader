shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
uniform sampler2D fog_map : filter_nearest, repeat_disable;
uniform bool reveal_all = true;
varying vec2 ground_position;
void vertex() {
    ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
    ALBEDO = vec3(0.025, 0.024, 0.023);
    ALPHA = reveal_all ? 0.0 : texture(fog_map, ground_position / vec2(4800.0, 3200.0)).a;
}
