#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 uResolution;
uniform float uTime;
uniform float uMicLevel;
uniform float uPhase; // 0=idle, 1=listening, 2=processing, 3=speaking, 4=error
uniform vec4 uAccentColor;
uniform vec4 uSecondaryColor;

// 3D Simplex-style noise helper
vec3 hash3(vec3 p) {
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(dot(hash3(i + vec3(0,0,0)), f - vec3(0,0,0)),
                       dot(hash3(i + vec3(1,0,0)), f - vec3(1,0,0)), u.x),
                   mix(dot(hash3(i + vec3(0,1,0)), f - vec3(0,1,0)),
                       dot(hash3(i + vec3(1,1,0)), f - vec3(1,1,0)), u.x), u.y),
               mix(mix(dot(hash3(i + vec3(0,0,1)), f - vec3(0,0,1)),
                       dot(hash3(i + vec3(1,0,1)), f - vec3(1,0,1)), u.x),
                   mix(dot(hash3(i + vec3(0,1,1)), f - vec3(0,1,1)),
                       dot(hash3(i + vec3(1,1,1)), f - vec3(1,1,1)), u.x), u.y), u.z);
}

float fbm3d(vec3 p) {
    float val = 0.0;
    float amp = 0.5;
    vec3 q = p;
    for (int i = 0; i < 4; i++) {
        val += amp * noise3d(q);
        q *= 2.03;
        amp *= 0.5;
    }
    return val;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 st = (fragCoord - uResolution * 0.5) / min(uResolution.x, uResolution.y);
    float dist = length(st);

    // Smooth outer boundary mask (no box artifact)
    float radialMask = smoothstep(0.48, 0.36, dist);

    float speed = (uPhase == 2.0) ? 2.2 : (uPhase == 3.0 ? 1.6 : 1.0);
    float time = uTime * speed;

    // Dynamic sphere radius based on mic level & phase
    float baseRadius = 0.30;
    if (uPhase == 1.0) { // Listening
        baseRadius += 0.08 * uMicLevel;
    } else if (uPhase == 2.0) { // Processing pulse
        baseRadius += 0.03 * sin(time * 6.0);
    } else if (uPhase == 3.0) { // Speaking
        baseRadius += 0.05 * sin(time * 4.0) * cos(time * 2.0);
    } else if (uPhase == 4.0) { // Error
        baseRadius = 0.25;
    }

    vec3 col = vec3(0.0);
    float alpha = 0.0;

    float rNorm = dist / baseRadius;

    if (rNorm <= 1.05) {
        // Calculate 3D sphere surface normal
        float pX = st.x / baseRadius;
        float pY = st.y / baseRadius;
        float r2 = clamp(pX * pX + pY * pY, 0.0, 1.0);
        float pZ = sqrt(1.0 - r2);

        vec3 N = vec3(pX, pY, pZ);

        // 3D rotation matrix for swirling surface coordinates
        float rotAngle = time * 0.7;
        float cosA = cos(rotAngle);
        float sinA = sin(rotAngle);
        vec3 rotN = vec3(
            N.x * cosA - N.z * sinA,
            N.y * cosA + N.x * sinA * 0.3,
            N.x * sinA + N.z * cosA
        );

        // 3D curved swirl ribbons wrapping along sphere surface
        float swirlTheta = atan(rotN.z, rotN.x);
        float noiseVal = fbm3d(rotN * 3.0 + vec3(0.0, 0.0, time * 0.4));
        
        float ribbonPattern = sin(rotN.y * 14.0 + swirlTheta * 4.0 + time * 2.0 + noiseVal * 4.0);
        float silkRibbons = smoothstep(-0.25, 0.75, ribbonPattern);

        // Soft internal nebula glow
        float innerGlow = pow(pZ, 0.85);

        // Fresnel rim reflection (translucent crystal edge)
        float fresnel = pow(1.0 - pZ, 2.2);

        // Soft top-left specular highlight
        vec3 lightDir = normalize(vec3(-0.35, -0.45, 0.82));
        float spec = pow(max(0.0, dot(N, lightDir)), 14.0);

        // Color blending for silky crystal orb
        vec3 coreBase = mix(uAccentColor.rgb, uSecondaryColor.rgb, clamp(rotN.y * 0.5 + 0.5, 0.0, 1.0));
        vec3 pinkHighlight = vec3(0.96, 0.65, 0.98); // Soft pink center glow
        vec3 whiteSilk = vec3(0.96, 0.95, 1.0);      // Pearlescent silk bands

        vec3 surfaceColor = mix(coreBase, pinkHighlight, innerGlow * 0.45);
        surfaceColor = mix(surfaceColor, whiteSilk, silkRibbons * 0.42);
        surfaceColor += whiteSilk * spec * 0.65; // Specular sheen
        surfaceColor = mix(surfaceColor, whiteSilk, fresnel * 0.50); // Rim glow

        // Antialiased sphere edge transition
        float edgeAlpha = smoothstep(1.05, 0.92, rNorm);

        col = surfaceColor * edgeAlpha;
        alpha = edgeAlpha * 0.92;
    }

    // Soft Atmospheric Halo Glow around the crystal sphere
    float haloDist = max(0.0, rNorm - 0.85);
    float outerGlow = exp(-haloDist * 4.5) * 0.55 * radialMask;
    vec3 haloColor = mix(uAccentColor.rgb, vec3(0.92, 0.88, 1.0), 0.3) * outerGlow;

    vec3 finalColor = col + haloColor;
    float finalAlpha = clamp(alpha + outerGlow, 0.0, 1.0) * radialMask;

    fragColor = vec4(finalColor * finalAlpha, finalAlpha);
}
