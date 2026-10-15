shader_type canvas_item;
render_mode unshaded;

uniform sampler2D artwork : source_color, filter_linear, repeat_disable;
uniform vec2 panel_size = vec2(432.0, 166.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
uniform float depression : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 half_size = panel_size * 0.5 - vec2(10.0);
    vec2 p = (UV - 0.5) * panel_size;
    vec2 q = abs(p);
    // Signed distance to a rectangle with four 11 px chamfered corners.
    float d = max(max(q.x - half_size.x, q.y - half_size.y),
        (q.x + q.y - half_size.x - half_size.y + 11.0) * 0.707107);
    float inside = 1.0 - smoothstep(-0.7, 0.7, d);
    vec2 art_uv = p / (half_size * 2.0);
    vec2 texture_size = vec2(textureSize(artwork, 0));
    float ratio = (half_size.x / half_size.y) / (texture_size.x / texture_size.y);
    art_uv *= vec2(min(ratio, 1.0), min(1.0 / ratio, 1.0));
    art_uv = art_uv / (1.0 + 0.035 * highlight) + 0.5;
    vec3 art = texture(artwork, art_uv).rgb;
    float cover = mix(0.75, 0.20, smoothstep(0.08, 0.85, UV.x));
    vec3 body = mix(art * vec3(0.68, 0.88, 1.06), vec3(0.015, 0.055, 0.10), cover);
    body += vec3(0.0, 0.12, 0.22) * highlight * (0.35 + 0.65 * UV.y);
    float edge = 1.0 - smoothstep(0.6, 1.7, abs(d + 0.7));
    float inner = (1.0 - smoothstep(0.3, 0.9, abs(d + 4.5))) * inside;
    vec3 cyan = mix(vec3(0.20, 0.50, 0.67), vec3(0.52, 0.91, 1.0), highlight);
    body = mix(body, cyan, edge);
    body += vec3(0.08, 0.27, 0.35) * inner * (0.5 + highlight);
    body *= 1.0 - 0.25 * depression;
    float halo = exp(-max(d, 0.0) / 3.2) * (0.09 + 0.65 * highlight);
    float alpha = max(inside, halo);
    COLOR = vec4(mix(vec3(0.08, 0.67, 1.0), body, inside), alpha);
}
