shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D mineral_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mineral_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float emission_strength : hint_range(0.0, 5.0) = 3.1;
varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
    local_position = VERTEX;
    local_normal = NORMAL;
}

vec3 mineral_sample(sampler2D tex, vec3 point, vec3 weights) {
    return texture(tex, point.zy).rgb * weights.x
        + texture(tex, point.xz).rgb * weights.y
        + texture(tex, point.xy).rgb * weights.z;
}

void fragment() {
    vec3 weights = pow(abs(local_normal), vec3(7.0));
    weights /= max(weights.x + weights.y + weights.z, 0.0001);
    vec3 coord = local_position * 0.62 + vec3(0.38, 0.07, 0.41);
    vec3 detail = mineral_sample(mineral_detail, coord, weights);
    // An offset internal fracture layer suggests depth without overlapping transparent shells.
    vec3 offset = vec3(VIEW.xy, VIEW.z) * 0.023;
    float internal = mineral_sample(mineral_detail, coord * 0.83 + offset + vec3(0.13, 0.27, 0.14), weights).r;
    float micro_fractures = mineral_sample(mineral_detail, coord * 3.7 + vec3(0.2), weights).r;
    float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float rim = pow(1.0 - facing, 3.4);
    float root_light = 1.0 - smoothstep(0.05, 0.75, local_position.y);
    float pulse = 0.97 + 0.03 * sin(TIME * 1.15 + local_position.y * 2.0);
    vec3 sapphire = mineral_sample(mineral_color, coord, weights);
    float facet = pow(abs(dot(normalize(local_normal), normalize(vec3(0.65, 0.32, -0.58)))), 2.0);
    ALBEDO = sapphire * mix(0.40, 1.12, facet) * mix(0.75, 1.05, COLOR.r);
    METALLIC = 0.05;
    ROUGHNESS = mix(0.16, 0.28, detail.g);
    SPECULAR = 0.65;
    CLEARCOAT = 0.65;
    CLEARCOAT_ROUGHNESS = 0.2;
    float edge = 1.0 - smoothstep(0.004, 0.023, min(UV2.x, 1.0 - UV2.x));
    float veins = pow(detail.r, 2.0) * 0.40 + internal * 0.045 + micro_fractures * 0.08;
    EMISSION = (vec3(0.008, 0.22, 0.85) * (veins + root_light * 0.18 + rim * 0.13)
        + vec3(0.23, 0.78, 1.0) * (pow(detail.r, 4.0) * 0.48 + edge * 0.16)
        + vec3(0.035, 0.37, 0.57) * facet * (0.15 + detail.g * 0.30)
        + vec3(0.02, 0.43, 0.65) * root_light * root_light * 0.24) * emission_strength * pulse;
}
