#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    vec4 cPrimary;
    vec4 cSecondary;
    vec4 cTertiary;
};

// 2D Simplex noise
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x*34.0)+1.0)*x); }

float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187,
                        0.366025403784439,
                       -0.577350269189626,
                        0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v -   i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m;
    m = m*m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
    vec3 g;
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float t = uTime * 0.45;

    // Multi-octave curtain ribbons flowing down from top edge (uv.y = 0.0)
    float n1 = snoise(vec2(uv.x * 2.4 + t * 0.22, uv.y * 1.6 - t * 0.32));
    float n2 = snoise(vec2(uv.x * 4.2 - t * 0.28, uv.y * 2.6 + t * 0.18));
    float n3 = snoise(vec2(uv.x * 1.5 + t * 0.12, uv.y * 0.9 + n1 * 0.45));

    // Curtains extend downward to ~48% of screen height and fade smoothly into pure black
    float verticalMask = smoothstep(0.48, 0.02, uv.y);

    // Flowing ribbon folds
    float ribbon1 = smoothstep(0.12, 0.88, sin((uv.x + n1 * 0.28) * 6.2831 + t) * 0.5 + 0.5);
    float ribbon2 = smoothstep(0.18, 0.84, cos((uv.x + n2 * 0.32) * 9.4247 + t * 0.85) * 0.5 + 0.5);
    float ribbon3 = smoothstep(0.15, 0.90, n3 * 0.5 + 0.5);

    // Color gradient across primary, secondary, and tertiary
    vec3 col = mix(cPrimary.rgb, cSecondary.rgb, ribbon1);
    col = mix(col, cTertiary.rgb, ribbon2 * 0.65);

    // 0.28 master dark-mode alpha to guarantee 100% center lyric contrast
    float intensity = (ribbon1 * 0.55 + ribbon2 * 0.35 + ribbon3 * 0.40) * verticalMask * 0.28;

    fragColor = vec4(col * intensity, intensity * qt_Opacity);
}
