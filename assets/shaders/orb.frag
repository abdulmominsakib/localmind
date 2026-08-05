#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// Uniform layout (must match the order .setFloat() is called in Dart):
// 0-1: uSize (vec2)
// 2:   uTime
// 3-5: uBaseColor (vec3, outer/base color of the orb)
// 6-8: uGlowColor (vec3, inner glow color)
uniform vec2 uSize;
uniform float uTime;
uniform vec3 uBaseColor;
uniform vec3 uGlowColor;

out vec4 fragColor;

// ---- Simplex noise (Ashima Arts, MIT licensed pattern) ----
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                      -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod289(i);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
                  + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 5; i++) {
    v += amp * snoise(p);
    p *= 2.0;
    amp *= 0.5;
  }
  return v;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 center = uSize * 0.5;
  float radiusPx = min(uSize.x, uSize.y) * 0.36;
  vec2 uv = (fragCoord - center) / radiusPx;
  float dist = length(uv);

  // soft circular falloff -> matches the blurred edge in the reference image
  float sphereMask = 1.0 - smoothstep(0.75, 1.05, dist);

  // gentle breathing pulse for the inner glow size
  float breathe = 0.5 + 0.5 * sin(uTime * 0.6);

  // slowly rotate coordinates to drive the swirling highlight bands
  float angle = uTime * 0.15;
  float ca = cos(angle);
  float sa = sin(angle);
  vec2 ruv = vec2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca);

  // thin swirl streaks (stretched fbm), drifting over time
  float streaks = fbm(vec2(ruv.x * 2.0, ruv.y * 6.0) + vec2(uTime * 0.05, 0.0));
  streaks = smoothstep(0.1, 0.9, streaks);

  // inner core glow, offset slightly like the reference, pulsing + drifting
  vec2 glowCenter = vec2(-0.15, 0.25) + 0.05 * vec2(cos(uTime * 0.3), sin(uTime * 0.4));
  float glowDist = length(uv - glowCenter);
  float innerGlow = exp(-glowDist * glowDist * (2.5 - 0.4 * breathe));

  // base radial gradient: outer base color -> inner glow color
  vec3 color = mix(uBaseColor, uGlowColor, innerGlow);

  // subtle rotating light streaks near the rim
  float rim = smoothstep(0.55, 1.0, dist) * (1.0 - smoothstep(0.95, 1.05, dist));
  color += streaks * rim * 0.35;

  // soft white wash toward the edges, matching the blurred-glass look
  color = mix(color, vec3(1.0), smoothstep(0.5, 1.05, dist) * 0.6);

  float alpha = sphereMask;
  fragColor = vec4(color * alpha, alpha);
}
