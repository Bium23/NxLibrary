/// The moonlight's Metal shaders, compiled at launch by the system's runtime
/// compiler (SwiftPM builds no .metal files, and the app needs no Metal toolchain).
///
/// Space is in window heights, y down: x runs 0...aspect. Two passes into a
/// clear target, both additive: `moon_light` draws the beam, its pool and the
/// haze; `moon_dot` draws every mote as a quad. Each pixel's alpha is its
/// brightest channel, so the layer composites over the theme's gradient like a
/// screen blend.
enum MoonlightShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 size;    // width px, height px, time s, aspect
    float4 accent;  // rgb, overall strength
    float4 ink;     // rgb, unused
    float4 look;    // breath 0...1, unused...
};

struct Particle { float start, lane, depth, speed, size, phase, kind, tint; };

// MARK: Look (window heights and shares of the width)

constant float2 beamSource = float2(0.15, -0.20);   // x: share of the width
constant float2 beamLean = float2(0.06, 1.0);
constant float beamWidth = 0.09;                     // half width at the source
constant float beamSpread = 0.24;                     // half width gained per height travelled
constant float beamReach = 3.6;                       // fall-off below its brightest
constant float2 poolCentre = float2(0.205, 0.865);   // x: share of the width
constant float2 poolRadius = float2(0.36, 0.072);
constant float focusDepth = 1.4;
constant float aperture = 0.009;

// MARK: Noise

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
    return v;
}

float4 premultiplied(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return float4(c, max(c.r, max(c.g, c.b)));
}

// MARK: Light

struct FullOut { float4 position [[position]]; };

vertex FullOut moon_full_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

fragment float4 moon_light_fragment(FullOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float aspect = u.size.w, t = u.size.z, breath = u.look.x;
    float2 p = in.position.xy / u.size.y;
    float3 accent = u.accent.rgb;

    // The beam: a cone from above the top left, its edges smoking slowly.
    float2 src = float2(beamSource.x * aspect, beamSource.y);
    float2 dir = normalize(beamLean);
    float2 v = p - src;
    float along = dot(v, dir);
    float across = dot(v, float2(dir.y, -dir.x));
    float halfWidth = beamWidth + max(along, 0.0) * beamSpread;
    float beam = 0.0, core = 0.0;
    if (abs(across) < halfWidth * 2.2 && along > -0.05) {
        float smoke = fbm(float2(across * 5.5, along * 2.4 - t * 0.07) + float2(t * 0.025, 0.0));
        float edge = across / (halfWidth * (0.6 + 0.8 * smoke));
        float body = exp(-edge * edge * 1.7);
        float fall = smoothstep(-0.02, 0.2, along) * exp(-max(along - 0.24, 0.0) * beamReach);
        beam = body * fall * (0.4 + 1.0 * smoke);
        core = exp(-edge * edge * 5.0) * exp(-max(along - 0.1, 0.0) * 5.0) * smoothstep(0.0, 0.2, along);
    }

    // The pool where it meets the floor: a flat ellipse, its rim stirring.
    float2 d = (p - float2(poolCentre.x * aspect, poolCentre.y)) / poolRadius;
    float r = length(d);
    float pool = 0.0;
    if (r < 2.6) {
        r *= 1.0 + 0.12 * (fbm(p * 7.0 + float2(t * 0.05, -t * 0.03)) - 0.5);
        pool = smoothstep(1.05, 0.4, r) * 0.3 + exp(-r * r * 0.7) * 0.1;
    }

    // A wide wash round the beam and a haze along the floor.
    float2 w = (p - float2(beamSource.x * aspect, 0.0)) / float2(0.75, 1.05);
    float wash = exp(-dot(w, w) * 1.6) * 0.07;
    float2 h = (p - float2(0.5 * aspect, 1.05)) / float2(0.9 * aspect, 0.32);
    float haze = exp(-dot(h, h) * 1.4) * 0.06;

    float pulse = 0.62 + 0.38 * breath;
    float3 white = mix(accent, float3(1.0), 0.65);
    float3 c = accent * ((beam * 0.75 + pool) * pulse + wash + haze) + white * core * 0.3 * pulse;
    c *= u.accent.w;
    // Dither so the dark gradients never band.
    c += (hash21(in.position.xy + fract(t)) - 0.5) / 255.0;
    return premultiplied(c);
}

// MARK: Motes

struct DotOut {
    float4 position [[position]];
    float2 local;      // px from the centre
    float radius;      // px
    float alpha;
    float bokeh;       // 0 sharp ... 1 a wide soft disc
    float3 color;
};

/// Where a mote is (window heights, at depth 1) and how alive it is (0...1).
float3 motePlace(Particle q, float t, float aspect) {
    float wobble = sin(t * (0.35 + q.phase * 0.4) + q.phase * 6.2831);
    if (q.kind < 0.5) {
        // The band: from the pool, rising to the right, thickening as it goes.
        float s = fract(q.start + t * q.speed);
        float x = mix(0.14, 1.08, s) * aspect;
        float y = 0.82 - 0.36 * (1.0 - pow(1.0 - s, 2.2));
        y += 0.028 * sin(6.2831 * (s * 1.25 - t / 46.0));
        y += q.lane * (0.035 + 0.11 * s);
        x += (q.phase - 0.5) * 0.05 * aspect;
        y += 0.008 * wobble;
        float life = smoothstep(0.0, 0.08, s) * smoothstep(1.0, 0.9, s);
        return float3(x, y, life);
    } else if (q.kind < 1.5) {
        // Off the pool: up and a little right, fading out as they rise.
        float s = fract(q.start + t * q.speed);
        float x = poolCentre.x * aspect + q.lane * 0.13 + s * 0.06 + 0.01 * wobble;
        float y = poolCentre.y + 0.015 - s * (0.16 + 0.12 * q.phase) + abs(q.lane) * 0.01;
        float life = smoothstep(0.0, 0.15, s) * smoothstep(1.0, 0.45, s);
        return float3(x, y, life);
    } else {
        // Loose in the air, slow and dim.
        float s = fract(q.start + t * q.speed);
        float x = (s * 1.2 - 0.1) * aspect;
        float y = 0.18 + fract(q.phase * 7.13 + q.lane * 0.11) * 0.72 + 0.012 * wobble;
        float life = smoothstep(0.0, 0.1, s) * smoothstep(1.0, 0.9, s) * 0.55;
        return float3(x, y, life);
    }
}

vertex DotOut moon_dot_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              constant Particle *field [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]]) {
    Particle q = field[iid];
    float W = u.size.x, H = u.size.y, t = u.size.z, aspect = u.size.w;
    float3 place = motePlace(q, t, aspect);

    // A touch of perspective: far motes draw in toward the middle.
    float2 centre = float2(0.5 * aspect, 0.56);
    float2 p = centre + (place.xy - centre) * pow(q.depth / focusDepth, -0.22);

    float sharp = q.size / q.depth * H;
    float blur = q.depth < focusDepth
        ? aperture * (focusDepth - q.depth) / q.depth * H
        : aperture * 0.18 * (q.depth - focusDepth) / q.depth * H;
    float radius = max(sqrt(sharp * sharp + blur * blur), 0.9);
    // The same light spread wider is fainter, but bokeh stays visible.
    float spread = clamp(pow(max(sharp, 0.9) / radius, 1.3), 0.16, 1.0);
    float far = clamp(1.7 / q.depth, 0.32, 1.0);
    float twinkle = 0.62 + 0.38 * sin(t * (0.7 + q.phase * 1.6) + q.phase * 40.0);
    float bright = 0.5 + 0.5 * fract(q.phase * 13.7);

    float2 corner = float2(float(vid & 1), float(vid >> 1)) * 2.0 - 1.0;
    float extent = radius + 1.5;
    float2 px = p * H + corner * extent;

    DotOut o;
    o.position = float4(px.x / W * 2.0 - 1.0, 1.0 - px.y / H * 2.0, 0.0, 1.0);
    o.local = corner * extent;
    o.radius = radius;
    // Motes finer than a pixel draw at a pixel, dimmer.
    o.alpha = place.z * spread * far * twinkle * bright * u.accent.w * clamp(sharp / 0.9, 0.3, 1.0);
    o.bokeh = smoothstep(2.5, 12.0, blur);
    o.color = q.tint > 0.5 ? mix(u.ink.rgb, u.accent.rgb, 0.25) : mix(u.accent.rgb, float3(1.0), 0.3);
    return o;
}

fragment float4 moon_dot_fragment(DotOut in [[stage_in]]) {
    float d = length(in.local);
    float soft = max(1.0, in.radius * mix(0.5, 0.2, in.bokeh));
    float shape = smoothstep(in.radius, in.radius - soft, d);
    // A bokeh disc is flat with a faintly brighter rim.
    shape *= 1.0 + 0.3 * in.bokeh * smoothstep(in.radius * 0.55, in.radius * 0.95, d);
    // A sharp mote has a bright heart.
    shape += (1.0 - in.bokeh) * exp(-d * d / max(in.radius * in.radius * 0.25, 0.3)) * 0.6;
    return premultiplied(in.color * in.alpha * shape);
}
"""#
}
