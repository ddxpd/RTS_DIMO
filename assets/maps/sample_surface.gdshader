shader_type spatial;
render_mode cull_back;

uniform sampler2D sand_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool reveal_all = true;
uniform float tile_scale = 96.0;
uniform float macro_scale = 460.0;
uniform float detail_fade = 2200.0;
uniform bool decoration = false;
varying vec3 world_position;
varying vec3 world_normal;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i+vec2(1,0)), f.x), mix(hash2(i+vec2(0,1)), hash2(i+vec2(1,1)), f.x), f.y);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    vec2 p = world_position.xz;
    vec3 surface_normal = normalize(world_normal);
    float distance_to_eye = length(world_position - CAMERA_POSITION_WORLD);
    float detail = 1.0 - smoothstep(detail_fade * 0.55, detail_fade, distance_to_eye);
    float macro = noise2(p / macro_scale);
    float medium = noise2(p / 68.0);
    vec2 uv = p / tile_scale;
    vec2 uv_b = mat2(vec2(0.8,0.6),vec2(-0.6,0.8)) * uv * 0.73 + vec2(0.37,0.81);
    vec3 sand = mix(texture(sand_color, uv).rgb, texture(sand_color, uv_b).rgb, 0.35);
    vec3 soil = texture(soil_color, uv * 0.72).rgb;
    vec3 gravel = texture(gravel_color, uv * 0.90).rgb;
    vec3 axis_weights = pow(abs(surface_normal), vec3(5.0));
    axis_weights /= max(dot(axis_weights, vec3(1.0)), 0.001);
    vec3 rock = texture(rock_color, world_position.zy / 112.0).rgb * axis_weights.x;
    rock += texture(rock_color, world_position.xz / 112.0).rgb * axis_weights.y;
    rock += texture(rock_color, world_position.xy / 112.0).rgb * axis_weights.z;
    vec4 sn = texture(sand_nr, uv), dn = texture(soil_nr, uv * 0.72), gn = texture(gravel_nr, uv * 0.90);
    vec4 rn_x = texture(rock_nr, world_position.zy / 112.0);
    vec4 rn_y = texture(rock_nr, world_position.xz / 112.0);
    vec4 rn_z = texture(rock_nr, world_position.xy / 112.0);
    float slope = 1.0 - abs(surface_normal.y);
    float rocky = smoothstep(0.16, 0.50, slope);
    rocky = max(rocky, smoothstep(0.76, 0.94, medium + macro * 0.15) * COLOR.g * 0.45);
    float stony = clamp(COLOR.g * (0.5 + medium * 0.65) + smoothstep(0.61, 0.78, macro) * 0.6, 0.0, 0.88);
    float road = clamp(COLOR.r + (medium - 0.5) * 0.16 * sin(COLOR.r * 3.14159), 0.0, 1.0);
    vec3 ground = mix(sand, gravel, stony);
    ground = mix(ground, soil * 1.04, road * 0.84);
    vec4 ground_nr = mix(mix(sn, gn, stony), dn, road);
    vec3 color = mix(ground, rock, rocky);
    // Long wavelength color and shorter strata retain form at RTS zoom levels.
    float strata = sin(world_position.y * 0.23 + noise2(p / 75.0) * 0.75);
    color *= mix(0.92 + macro * 0.16, 0.96 + strata * 0.045, rocky);
    float tracks = 1.0 - smoothstep(3.0, 6.0, abs(abs(UV.x) - 28.0));
    float breaks = smoothstep(0.18, 0.42, noise2(vec2(UV.y * 0.032, 2.7)));
    float tread = (0.5 + 0.5 * sin(UV.y * 0.60 + UV.x * 0.035)) * detail;
    tracks *= road * breaks * (1.0 - rocky);
    color *= 1.0 - tracks * (0.12 + tread * 0.06);
    float shoulder = smoothstep(0.0, 0.25, road) * (1.0 - smoothstep(0.4, 0.8, road));
    color = mix(color, sand * 1.04, shoulder * 0.28);
    if (decoration) { color = rock * COLOR.rgb; rocky = 1.0; }
    ALBEDO = color;
    AO = decoration ? 1.0 : 1.0 - COLOR.b * 0.28;
    AO_LIGHT_AFFECT = 0.4;
    ROUGHNESS = mix(ground_nr.a, dot(vec3(rn_x.a,rn_y.a,rn_z.a), axis_weights), rocky);
    SPECULAR = 0.18;
    // Transform small normal perturbations in world space, then into view space.
    vec2 micro = ground_nr.rg * 2.0 - 1.0;
    vec3 ground_bump = vec3(micro.x, 0.0, -micro.y);
    vec3 cliff_bump = vec3(0.0, -(rn_x.g * 2.0 - 1.0), rn_x.r * 2.0 - 1.0) * axis_weights.x;
    cliff_bump += vec3(rn_y.r * 2.0 - 1.0, 0.0, -(rn_y.g * 2.0 - 1.0)) * axis_weights.y;
    cliff_bump += vec3(rn_z.r * 2.0 - 1.0, -(rn_z.g * 2.0 - 1.0), 0.0) * axis_weights.z;
    vec3 bump = mix(ground_bump * 0.40, cliff_bump * 0.65, rocky) * mix(0.20, 1.0, detail);
    bump -= surface_normal * dot(bump, surface_normal);
    NORMAL = normalize((VIEW_MATRIX * vec4(normalize(surface_normal + bump), 0.0)).xyz);
}
