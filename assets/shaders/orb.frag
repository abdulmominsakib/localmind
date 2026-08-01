#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 uResolution;
uniform float uTime;
uniform float uMicLevel;
uniform float uPhase;
uniform vec4 uAccentColor;
uniform vec4 uSecondaryColor;
uniform float uIsDark;
uniform float uEnergy;
uniform float uProcessingWeight;
uniform float uSpeakingWeight;
uniform float uErrorWeight;
uniform float uResponseProgress;

const float PI = 3.14159265359;

vec3 hash3(vec3 p) {
    p = vec3(
        dot(p, vec3(127.1, 311.7, 74.7)),
        dot(p, vec3(269.5, 183.3, 246.1)),
        dot(p, vec3(113.5, 271.9, 124.6))
    );
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise3d(vec3 p) {
    vec3 cell = floor(p);
    vec3 local = fract(p);
    vec3 curve = local * local * (3.0 - 2.0 * local);

    return mix(
        mix(
            mix(
                dot(hash3(cell), local),
                dot(hash3(cell + vec3(1.0, 0.0, 0.0)), local - vec3(1.0, 0.0, 0.0)),
                curve.x
            ),
            mix(
                dot(hash3(cell + vec3(0.0, 1.0, 0.0)), local - vec3(0.0, 1.0, 0.0)),
                dot(hash3(cell + vec3(1.0, 1.0, 0.0)), local - vec3(1.0, 1.0, 0.0)),
                curve.x
            ),
            curve.y
        ),
        mix(
            mix(
                dot(hash3(cell + vec3(0.0, 0.0, 1.0)), local - vec3(0.0, 0.0, 1.0)),
                dot(hash3(cell + vec3(1.0, 0.0, 1.0)), local - vec3(1.0, 0.0, 1.0)),
                curve.x
            ),
            mix(
                dot(hash3(cell + vec3(0.0, 1.0, 1.0)), local - vec3(0.0, 1.0, 1.0)),
                dot(hash3(cell + vec3(1.0, 1.0, 1.0)), local - vec3(1.0, 1.0, 1.0)),
                curve.x
            ),
            curve.y
        ),
        curve.z
    );
}

float fbm3d(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    vec3 samplePoint = p;

    // Four octaves keep the orb fluid while remaining safe for mobile GPUs.
    for (int octave = 0; octave < 4; octave++) {
        value += amplitude * noise3d(samplePoint);
        samplePoint = samplePoint * 2.03 + vec3(0.13, -0.17, 0.11);
        amplitude *= 0.5;
    }
    return value;
}

float thinBand(float wave, float width, float softness) {
    return 1.0 - smoothstep(width, width + softness, abs(sin(wave)));
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    float shortSide = min(uResolution.x, uResolution.y);
    vec2 point = (fragCoord - uResolution * 0.5) / shortSide;
    float pixel = 1.25 / shortSide;

    float dark = step(0.5, uIsDark);
    float responseCadence =
        0.5 +
        0.30 * sin(uTime * 7.4 + uResponseProgress * PI * 18.0) +
        0.20 * sin(uTime * 12.7 - uResponseProgress * PI * 11.0);
    responseCadence = smoothstep(0.18, 0.86, responseCadence);

    float activity = clamp(
        max(uEnergy, uMicLevel * (1.0 - uSpeakingWeight)) +
        uSpeakingWeight * responseCadence * 0.22,
        0.0,
        1.0
    );

    // Keep the silhouette mathematically circular. Voice activity changes the
    // orb's overall radius, while motion stays inside the surface so speech
    // never makes the edge look flattened or lopsided.
    vec2 shapePoint = point;
    float slowTime = uTime * (
        0.115 +
        0.065 * uProcessingWeight +
        0.005 * uPhase
    );
    float breathing = sin(uTime * 1.35 + uResponseProgress * PI * 2.0);
    float radius =
        0.378 +
        activity * 0.010 +
        breathing * (0.0015 + activity * 0.0015) -
        uProcessingWeight * 0.004 -
        uErrorWeight * 0.028;
    float signedDistance = length(shapePoint) - radius;

    float bodyMask = smoothstep(pixel * 3.6, -pixel * 3.6, signedDistance);
    float haloMask = exp(-max(signedDistance, 0.0) * mix(25.0, 20.0, dark));
    haloMask *= 1.0 - smoothstep(
        radius + 0.018,
        radius + 0.145,
        length(shapePoint)
    );

    vec2 orbPoint = shapePoint / max(radius, 0.001);
    float orbDistance = length(orbPoint);
    float edge = smoothstep(0.42, 0.96, orbDistance);
    float edgeGlow = pow(clamp(orbDistance, 0.0, 1.0), 5.0);

    // Reconstruct the front half of a sphere from the circular silhouette.
    // Object-space lighting supplies depth without changing the round edge.
    float surfaceZ = sqrt(max(0.0, 1.0 - min(dot(orbPoint, orbPoint), 1.0)));
    vec3 surfaceNormal = normalize(vec3(orbPoint, surfaceZ + 0.001));
    vec3 lightDirection = normalize(vec3(-0.52, -0.46, 0.78));
    vec3 viewDirection = vec3(0.0, 0.0, 1.0);
    float diffuseLight = smoothstep(
        -0.42,
        0.88,
        dot(surfaceNormal, lightDirection)
    );
    float centerVolume = pow(surfaceZ, 0.62);
    vec3 halfVector = normalize(lightDirection + viewDirection);
    float softSheen = pow(
        max(dot(surfaceNormal, halfVector), 0.0),
        mix(5.0, 7.0, dark)
    );

    // Layered curved coordinates create the wrapped, hair-like fibers in the
    // reference. They move slowly and remain visible throughout every phase.
    float flowNoise = fbm3d(vec3(
        orbPoint * 1.45,
        slowTime * 1.35
    ));
    float primaryCurve =
        orbPoint.y +
        0.31 * orbPoint.x * orbPoint.x -
        0.13 * orbPoint.x +
        0.055 * sin(orbPoint.x * 3.7 - uTime * 0.19) +
        flowNoise * (0.045 + activity * 0.018);
    float secondaryCurve =
        orbPoint.y * 0.88 +
        orbPoint.x * 0.27 +
        0.19 * orbPoint.x * orbPoint.x +
        0.045 * sin(orbPoint.x * 4.4 + uTime * 0.14) -
        flowNoise * 0.035;

    float primaryFlow = primaryCurve * PI * 4.65 + uTime * 0.14;
    float secondaryFlow = secondaryCurve * PI * 3.55 - uTime * 0.11;
    float silkBands = thinBand(primaryFlow, 0.060, 0.185);
    float broadSilk = thinBand(primaryFlow + 0.18, 0.19, 0.31);
    float fineBands = thinBand(secondaryFlow + 1.15, 0.042, 0.135);

    float topCoverage = 1.0 - smoothstep(-0.56, 0.76, orbPoint.y);
    float leftCoverage = 1.0 - smoothstep(-0.82, 0.18, orbPoint.x);
    float ribbonCoverage = clamp(
        edge * (0.34 + topCoverage * 0.72 + leftCoverage * 0.28),
        0.0,
        1.0
    );
    float ribbonLight = (
        silkBands * (0.82 + activity * 0.28) +
        broadSilk * 0.20 +
        fineBands * 0.30
    ) * ribbonCoverage;
    // Fibres facing the light are clearer and those rolling around the shaded
    // side recede, which makes them feel embedded in a curved surface.
    ribbonLight *= 0.58 + diffuseLight * 0.31 + centerVolume * 0.11;

    vec3 accent = clamp(uAccentColor.rgb, 0.0, 1.0);
    vec3 secondary = clamp(uSecondaryColor.rgb, 0.0, 1.0);

    vec3 lightPearl = vec3(0.965, 0.960, 1.000);
    vec3 lightLilac = mix(vec3(0.735, 0.690, 0.985), accent, 0.055);
    vec3 lightPink = mix(vec3(0.985, 0.555, 0.950), secondary, 0.035);
    vec3 darkPearl = mix(vec3(0.690, 0.625, 1.000), accent, 0.28);
    vec3 darkLilac = mix(vec3(0.155, 0.105, 0.355), accent, 0.32);
    vec3 darkPink = mix(vec3(0.895, 0.290, 0.805), secondary, 0.25);

    vec3 pearl = mix(lightPearl, darkPearl, dark);
    vec3 lilac = mix(lightLilac, darkLilac, dark);
    vec3 pink = mix(lightPink, darkPink, dark);

    float innerCloud = fbm3d(vec3(
        orbPoint * 1.35 + vec2(-slowTime * 0.25, slowTime * 0.16),
        slowTime * 0.48
    ));
    float pinkBloom = exp(
        -dot(
            orbPoint - vec2(-0.18, -0.08),
            orbPoint - vec2(-0.18, -0.08)
        ) * 3.9
    );
    float pearlBloom = exp(
        -dot(
            orbPoint - vec2(0.24, 0.20),
            orbPoint - vec2(0.24, 0.20)
        ) * 3.2
    );

    vec3 color = lilac;
    color = mix(color, pink, pinkBloom * mix(0.52, 0.50, dark));
    color = mix(color, pearl, pearlBloom * mix(0.17, 0.12, dark));
    color += pearl * innerCloud * mix(0.055, 0.085, dark);

    vec3 silkColor = mix(vec3(1.0, 0.985, 1.0), vec3(0.88, 0.83, 1.0), dark);
    float formLight = mix(
        mix(0.79, 1.075, diffuseLight),
        mix(0.54, 1.13, diffuseLight),
        dark
    );
    formLight *= mix(0.91, 1.035, centerVolume);
    color *= formLight;
    color = mix(
        color,
        pearl,
        softSheen * mix(0.15, 0.18, dark)
    );
    color = mix(
        color,
        silkColor,
        clamp(ribbonLight * mix(0.68, 0.58, dark), 0.0, 0.82)
    );
    vec3 rimColor = mix(lilac, silkColor, 0.34 + diffuseLight * 0.48);
    color = mix(
        color,
        rimColor,
        edgeGlow * mix(0.28, 0.31, dark)
    );

    float bodyAlpha = bodyMask * mix(0.69, 0.88, dark);
    bodyAlpha *= mix(0.93 + pinkBloom * 0.045, 0.96, dark);

    float haloStrength =
        haloMask *
        (0.11 + activity * 0.06) *
        mix(0.72, 1.0, dark);
    vec3 haloColor = mix(
        mix(pearl, pink, 0.18),
        mix(darkPearl, secondary, 0.20),
        dark
    );

    if (uErrorWeight > 0.001) {
        vec3 errorColor = mix(vec3(1.0, 0.54, 0.58), vec3(1.0, 0.20, 0.28), dark);
        color = mix(color, errorColor, uErrorWeight * (0.30 + edgeGlow * 0.20));
    }

    vec3 premultiplied =
        clamp(color, 0.0, 1.15) * bodyAlpha +
        haloColor * haloStrength;
    float alpha = clamp(bodyAlpha + haloStrength, 0.0, 1.0);

    fragColor = vec4(premultiplied, alpha);
}
