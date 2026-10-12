shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D mineral_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mineral_detail : filter_linear_mipmap, repeat_enable;
varying vec3 point;
varying vec3 facet_normal;

void vertex() {
    point = VERTEX;
    facet_normal = NORMAL;
}

void fragment() {
    vec3 weights = pow(abs(facet_normal), vec3(7.0));
    weights /= max(weights.x + weights.y + weights.z, 0.0001);
    vec3 p = point * 0.9;
    vec3 blue = texture(mineral_color, p.zy).rgb * weights.x
        + texture(mineral_color, p.xz).rgb * weights.y
        + texture(mineral_color, p.xy).rgb * weights.z;
    float cracks = texture(mineral_detail, p.zy).r * weights.x
        + texture(mineral_detail, p.xz).r * weights.y
        + texture(mineral_detail, p.xy).r * weights.z;
    float facet = abs(dot(normalize(facet_normal), normalize(vec3(0.65, 0.32, -0.58))));
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
    ALBEDO = blue * mix(0.3, 1.2, facet);
    METALLIC = 0.05;
    ROUGHNESS = 0.18;
    SPECULAR = 0.65;
    CLEARCOAT = 0.7;
    CLEARCOAT_ROUGHNESS = 0.15;
    EMISSION = vec3(0.015, 0.25, 0.9) * (0.13 + facet * 0.25 + cracks * 0.4)
        + vec3(0.20, 0.65, 1.0) * (pow(cracks, 4.0) * 0.6 + rim * 0.12);
}
