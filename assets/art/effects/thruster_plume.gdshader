shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform bool core = false;
instance uniform float power = 0.0;
instance uniform float phase = 0.0;
instance uniform float ground_height = -100000.0;
varying float axial;
varying float world_height;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
    axial = 0.5 - VERTEX.y;
    float flutter = sin(axial * 18.0 - TIME * 19.0 + phase);
    VERTEX.xz *= 1.0 + axial * (core ? 0.025 : 0.12) * flutter;
    world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
    float t = clamp(axial, 0.0, 1.0);
    float flow = noise(vec2(UV.x * 7.0 + phase, t * 9.0 - TIME * 8.0));
    float streak = noise(vec2(UV.x * 17.0, t * 4.0 - TIME * 12.0 + phase));
    float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
    float width = mix(0.95, 0.055, t) * (1.0 + (flow - 0.5) * t * 0.35);
    float edge = abs(UV.x * 2.0 - 1.0) / width;
    float profile = 1.0 - smoothstep(0.08, 1.0, edge);
    float tail = 1.0 - smoothstep(0.32, 1.0, t + (flow - 0.5) * 0.2);
    float inlet = smoothstep(0.0, 0.055, t);
    float bands = 0.86 + 0.14 * sin(t * 36.0 - TIME * 8.0 + phase);
    vec3 blue = mix(vec3(0.015, 0.14, 0.8), vec3(0.09, 0.72, 1.0), flow);
    ALBEDO = core ? vec3(0.62, 0.89, 1.0) : blue;
    EMISSION = ALBEDO * (core ? 3.4 : 1.7);
    float ground_fade = smoothstep(ground_height + 0.1, ground_height + 3.0, world_height);
    ALPHA = power * facing * profile * tail * inlet * bands * ground_fade * (core ? 0.8 : (0.25 + 0.35 * streak));
}
