shader_type spatial;
render_mode cull_disabled;

uniform sampler2D fog_map : filter_nearest, repeat_disable;
uniform bool reveal_all = false;
uniform bool rock_surface = false;
varying vec3 world_position;

float hash_noise(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash_noise(i), hash_noise(i + vec2(1, 0)), f.x), mix(hash_noise(i + vec2(0, 1)), hash_noise(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = world_position.xz;
    float broad = noise(p * 0.008);
    float grain = noise(p * 0.7);
    float gravel = smoothstep(0.73, 0.86, noise(p * 0.19));
    vec3 color = COLOR.rgb * (0.82 + broad * 0.3 + grain * 0.12);
    color = mix(color, color * 0.63, gravel * 0.36);
    float dune = sin(p.x * 0.043 + p.y * 0.027 + noise(p * 0.007) * 7.0);
    color *= 1.0 + dune * 0.025 * (1.0 - UV.x);
    if (rock_surface) {
        float strata = sin(world_position.y * 0.19 + noise(p * 0.032) * 1.4);
        color *= 0.95 + strata * 0.07;
        color += vec3(0.025, 0.014, 0.006) * smoothstep(0.8, 0.96, strata);
    } else {
        color = mix(color, vec3(0.47, 0.31, 0.17) * (0.9 + grain * 0.22), UV.x * 0.62);
    }
    float fog = reveal_all ? 0.0 : texture(fog_map, p / vec2(4800.0, 3200.0)).a;
    ALBEDO = color * (1.0 - fog);
    EMISSION = vec3(0.025, 0.024, 0.023) * fog;
    ROUGHNESS = 0.95;
    SPECULAR = 0.15;
}
