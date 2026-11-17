import NXLibraryCore

/// The moonlight's Metal shaders, compiled at launch by the system's runtime
/// compiler (SwiftPM builds no .metal files, and the app needs no Metal toolchain).
///
/// Space is in window heights, y down: x runs 0...aspect. Two passes into a
/// clear target, both additive: `moon_light` draws the beam, its pool and the
/// haze; `moon_dot` draws every mote as a quad. Each pixel's alpha is its
/// brightest channel, so the layer composites over the theme's gradient like a
/// screen blend.
enum MoonlightShaders {
    private static let spectrum = MoonlightChromatics.colors.map {
        "float3(\($0.x), \($0.y), \($0.z))"
    }.joined(separator: ", ")

    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 size;    // width px, height px, time s, aspect
    float4 accent;  // rgb, overall strength
    float4 ink;     // rgb, unused
    float4 look;    // breath, presence, Flow blend, Arcane surface blend
    float4 tintTop;     // the Mods card's ground: top rgb, amount 0...1
    float4 tintMid;     // rgb at 0.45 of the height
    float4 tintBottom;  // rgb at the bottom
};

struct Particle { float start, lane, depth, speed, size, phase, kind, tint; };

constant float3 arcaneColors[3] = { \#(spectrum) };
constant float arcanePeriod = \#(MoonlightChromatics.period);
constant float arcaneIntensity = \#(MoonlightChromatics.intensity);

float3 arcaneSpectrum(float2 uv, float time, float offset) {
    float phase = time / arcanePeriod * 6.2831853;
    float2 p = (uv - float2(0.18,0.77)) / float2(0.42,0.5);
    float2 c = (uv - float2(0.84,0.43)) / float2(0.42,0.5);
    float pw = exp(-dot(p,p)), cw = exp(-dot(c,c));
    float3 drift = float3(2.5*sin(phase),1.8*sin(phase+1.0),2.6*sin(phase+2.0))/255.0;
    return (arcaneColors[0]*pw + arcaneColors[1]*cw + arcaneColors[2]*0.25)/(pw+cw+0.25)+drift;
}

// Analytic moving surfaces, evaluated in the existing light pass. No texture,
// geometry upload, extra timer, or sampling loop per pixel.
float arcaneGlow(float2 uv, float2 centre, float2 radius) {
    float2 d=(uv-centre)/radius;
    return exp(-dot(d,d)*2.5);
}

// Travelling, overlapping wind waves bend the whole thread, not just its glow.
float filamentY(float x, float2 a, float2 b, float bend, float phase, float seed) {
    float s=clamp((x-a.x)/(b.x-a.x),0.0,1.0);
    float envelope=sin(s*3.1415927);
    float wind=0.026*sin(s*5.2-phase*1.35+seed)
        + 0.009*sin(s*11.7-phase*1.91+seed*0.63);
    return mix(a.y,b.y,s) + envelope*(bend+wind);
}

// A subpixel luminous core integrated across a pixel. Soft, dim scattering
// gives it air without widening it into a neon ribbon.
float filamentProfile(float distancePixels) {
    return 0.34*exp(-0.5*distancePixels*distancePixels/0.25)
        + 0.018*exp(-0.5*distancePixels*distancePixels/4.84);
}

float3 filament(float2 uv, float2 a, float2 b, float bend, float phase,
                float time, float seed, float3 color, float height) {
    float s=(uv.x-a.x)/(b.x-a.x);
    float gate=smoothstep(0.0,0.12,s)*(1.0-smoothstep(0.78,1.0,s));
    float y=filamentY(uv.x,a,b,bend,phase,seed);
    float distance=uv.y-y;
    float footprint=max(length(float2(dfdx(distance),dfdy(distance))),1.0/height);
    float separation=(0.0015+0.006*sin(clamp(s,0.0,1.0)*3.1415927))
        *(0.75+0.25*sin(s*4.8-phase*0.8+seed));
    float strands=filamentProfile(distance/footprint)
        + 0.32*filamentProfile((distance-separation)/footprint)
        + 0.18*filamentProfile((distance+separation*1.4)/footprint);
    float glint=0.78+0.22*cos(6.2831853*(s*0.65-time/(100.0+seed*3.0)-seed*0.137));
    return color*gate*strands*glint;
}

float triangle(float2 p,float2 a,float2 b,float2 c) {
    float2 v=b-a,w=c-a,q=p-a;
    float det=v.x*w.y-v.y*w.x;
    float u=(q.x*w.y-q.y*w.x)/det, t=(v.x*q.y-v.y*q.x)/det;
    return smoothstep(0.0,0.018,u)*smoothstep(0.0,0.018,t)*(1.0-smoothstep(0.982,1.0,u+t));
}

float3 arcaneSurface(float2 uv,float time,float flow,float height) {
    float phase=time/ mix(120.0,140.0,flow)*6.2831853;
    float2 left=mix(float2(0.18,0.77),float2(0.12,0.79),flow)
        + float2(0.006*sin(phase),0.009*cos(phase));
    float2 right=mix(float2(0.84,0.43),float2(0.93,0.56),flow)
        + float2(0.007*sin(phase+2.0),0.012*cos(phase+2.0));
    float cp=time/arcanePeriod*6.2831853;
    float3 drift=float3(2.5*sin(cp),1.8*sin(cp+1.0),2.6*sin(cp+2.0))/255.0;
    float3 pink=arcaneColors[0]+drift, cyan=arcaneColors[1]+drift;
    float3 base=mix(mix(float3(0.094,0.09,0.18),float3(0.035,0.055,0.125),uv.y),
                    mix(float3(0.165,0.16,0.30),float3(0.078,0.118,0.208),uv.y),flow);
    float3 result=base+pink*arcaneGlow(uv,left,float2(0.40,0.48))*mix(0.16,0.22,flow)
        + cyan*arcaneGlow(uv,right,float2(0.37,0.47))*mix(0.15,0.21,flow)
        + arcaneColors[2]*arcaneGlow(uv,float2(0.22,0.2),float2(0.6,0.8))*mix(0.06,0.14,flow);
    float3 angular = float3(0.0);
    float3 facets = float3(0.0);
    if (flow < 1.0) {
    float2 junction=float2(0.56+0.007*sin(phase+1.0),0.60+0.015*sin(phase+0.3));
    float2 bottom=float2(0.58+0.009*cos(phase),0.86+0.008*sin(phase+2.0));
    float2 upper=float2(0.96+0.008*sin(phase),0.26+0.01*cos(phase+1.0));
    facets=arcaneColors[2]*triangle(uv,left,junction,bottom)*0.055
        + cyan*triangle(uv,right,junction,upper)*0.075
        + float3(0.28,0.44,0.71)*triangle(uv,right,junction,float2(0.70,0.80))*0.045;
    angular=filament(uv,left,junction,0.007,phase,time,0.0,pink,height)
        + filament(uv,right,junction,0.007,phase,time,4.0,cyan,height)
        + filament(uv,right,upper,0.004,phase,time,6.0,cyan,height)
        + filament(uv,left,float2(0.32,0.49),0.003,phase,time,2.0,pink*0.3,height);
    }
    float3 flowing = float3(0.0);
    if (flow > 0.0) {
    float2 a=float2(-0.06,0.49+0.012*sin(phase)), b=float2(0.72,1.02+0.012*cos(phase));
    float2 c=float2(1.04,0.31+0.013*cos(phase)), d=float2(0.38,0.79+0.009*sin(phase+2.0));
    float bendA=0.045+0.022*sin(phase+0.7),bendB=0.08+0.024*sin(phase+0.5);
    float yA=filamentY(uv.x,a,b,bendA,phase,1.0), yB=filamentY(uv.x,c,d,bendB,phase,4.0);
    float glassA=smoothstep(yA,yA+0.035,uv.y)*(1.0-smoothstep(yA+0.12,yA+0.28,uv.y));
    float glassB=smoothstep(yB,yB+0.025,uv.y)*(1.0-smoothstep(yB+0.07,yB+0.19,uv.y));
    flowing=filament(uv,a,b,bendA,phase,time,1.0,pink,height)
        + filament(uv,c,d,bendB,phase,time,4.0,cyan,height)
        + filament(uv,float2(-0.02,0.87),float2(0.58,0.94),-0.07+0.016*sin(phase+1.0),phase,time,7.0,pink*0.35,height)
        + pink*glassA*0.06 + cyan*glassB*0.05;
    }
    result+=mix(facets+angular,flowing,flow);
    float vignette=1.0-0.2*smoothstep(0.4,1.0,length((uv-float2(0.5,0.48))*float2(1.0,0.8)));
    return result*vignette;
}

// MARK: Look (window heights and shares of the width)

constant float2 beamSource = float2(0.14, -0.20);   // x: share of the width
constant float beamBend = 0.26;                       // how far it curves right, per height² travelled
constant float beamWidth = 0.09;                     // half width at the source
constant float beamSpread = 0.26;                     // half width gained per height travelled
constant float beamReach = 3.4;                       // fall-off below its brightest
constant float2 poolCentre = float2(0.205, 0.865);   // x: share of the width
constant float2 poolRadius = float2(0.36, 0.072);
constant float focusDepth = 2.0;
constant float aperture = 0.010;
// A lens's soft edge: motes toward the right blur a touch more, from `lensFrom`
// (share of the width) to the edge, up to `lensBlur` window heights.
constant float lensFrom = 0.55;
constant float lensBlur = 0.0016;
// The road the motes travel: an S from near the camera at the bottom left,
// away into the distance on the right. Depth at its two ends, and its half
// width in window heights at depth 1 (so it narrows as it recedes).
constant float roadNear = 0.5;
constant float roadFar = 2.9;
constant float roadHalf = 0.12;
// How much the road narrows with depth (1 true perspective, 0 none).
constant float roadNarrowing = 0.6;
constant float roadGlow = 0.055;

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

// MARK: Road

/// The road at `s` (0 near ... 1 far): x across the window, in window heights.
float roadX(float s, float aspect) { return mix(-0.04, 1.08, s) * aspect; }

/// The road's height at `s`: up from the bottom left, past the middle, and a
/// little down again on the right (the S), with a slow wave running along it.
float roadY(float s, float t) {
    float y = 0.84 - 0.34 * smoothstep(0.0, 0.55, s)
        - 0.06 * sin(3.14159 * clamp((s - 0.45) / 0.55, 0.0, 1.0));
    return y + 0.015 * sin(6.2831 * (s * 1.5 - t / 50.0));
}

float roadDepth(float s) { return mix(roadNear, roadFar, pow(clamp(s, 0.0, 1.0), 0.85)); }

/// The road's half width on screen at `s`, in window heights.
float roadWidth(float s) { return roadHalf / pow(roadDepth(s), roadNarrowing); }

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
    float2 uv = float2(p.x / aspect, p.y);
    // Uniform branch: a settled Arcane surface does not evaluate the classic beam.
    // Intermediate blends still draw both paths for the shared colour glide.
    if (u.look.w >= 1.0 && u.tintTop.w <= 0.0) {
        float3 surface=arcaneSurface(uv,t,u.look.z,u.size.y);
        surface+=(hash21(in.position.xy)-0.5)/255.0;
        return float4(surface,1.0)*u.look.y;
    }
    float3 accent = u.accent.rgb;
    if (u.look.w > 0.0) { accent = mix(accent, arcaneSpectrum(uv, t, 0.0), u.look.w); }

    // The beam: a cone from above the top left that bends right as it falls,
    // its edges smoking slowly.
    float2 src = float2(beamSource.x * aspect, beamSource.y);
    float along = p.y - src.y;
    float across = p.x - (src.x + beamBend * max(along, 0.0) * max(along, 0.0));
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

    // A faint glow along the motes' road, wide near and thin far.
    float road = 0.0;
    float rs = (p.x / aspect + 0.04) / 1.12;
    if (rs > 0.0 && rs < 1.0) {
        float width = roadWidth(rs) * 1.2;
        float dy = (p.y - roadY(rs, t)) / width;
        road = exp(-dy * dy) * roadGlow * smoothstep(0.0, 0.2, rs) * smoothstep(1.0, 0.8, rs);
    }

    float pulse = 0.62 + 0.38 * breath;
    float3 white = mix(accent, float3(1.0), 0.65);
    float3 c = accent * ((beam * 0.75 + pool) * pulse + wash + haze + road) + white * core * 0.3 * pulse;
    c *= u.accent.w;
    // Dither so the dark gradients never band.
    c += (hash21(in.position.xy + fract(t)) - 0.5) / 255.0;
    float4 light = premultiplied(c);
    if (u.look.w > 0.0) {
        float3 surface=arcaneSurface(uv,t,u.look.z,u.size.y);
        surface+=(hash21(in.position.xy)-0.5)/255.0;
        light=mix(light,float4(surface,1.0),u.look.w);
    }
    // The Mods card's ground under the light, as opaque as `amount`: drawn here, on the render thread, so it
    // glides in step with the accent and costs a few operations per pixel of a pass that runs anyway.
    float amount = u.tintTop.w;
    if (amount <= 0.0) { return light * u.look.y; }
    float y = in.position.y / u.size.y;
    float3 ground = y < 0.45 ? mix(u.tintTop.rgb, u.tintMid.rgb, y / 0.45)
                             : mix(u.tintMid.rgb, u.tintBottom.rgb, (y - 0.45) / 0.55);
    return float4(min(ground * amount + light.rgb, 1.0), amount + light.a * (1.0 - amount)) * u.look.y;
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

struct Place { float2 at; float depth; float life; };

/// Where a mote is on screen (window heights), how far, and how alive (0...1).
Place motePlace(Particle q, float t, float aspect) {
    float wobble = sin(t * (0.35 + q.phase * 0.4) + q.phase * 6.2831);
    Place o;
    if (q.kind < 0.5) {
        // On the road, drifting away along it and curling about as they go.
        float s = fract(q.start + t * q.speed);
        float2 c = float2(roadX(s, aspect), roadY(s, t));
        float2 ahead = float2(roadX(s + 0.01, aspect), roadY(s + 0.01, t));
        float2 n = normalize(float2(c.y - ahead.y, ahead.x - c.x));
        // `depth` jitters the mote off the road's own depth, a little nearer or further.
        float depth = roadDepth(s) * mix(0.82, 1.25, (q.depth - 0.45) / 2.75);
        float lift = (fract(q.phase * 5.31) - 0.5) * 0.9;
        float2 curl = float2(sin(t * (0.21 + q.phase * 0.3) + q.phase * 17.0),
                             cos(t * (0.17 + q.phase * 0.25) + q.phase * 11.0));
        o.at = c + (n * q.lane + float2(0.0, lift)) * roadWidth(s) + curl * 0.03 / depth;
        o.depth = depth;
        // Near the camera the road thins out to a few big discs; far, it crowds.
        float shown = step(fract(q.phase * 23.7), mix(0.3, 1.0, smoothstep(0.0, 0.45, s)));
        o.life = shown * smoothstep(0.0, 0.05, s) * smoothstep(1.0, 0.9, s);
        return o;
    }
    // Off the road, a touch of perspective: far motes draw in toward the middle.
    float2 centre = float2(0.5 * aspect, 0.56);
    float squeeze = pow(q.depth / focusDepth, -0.22);
    o.depth = q.depth;
    if (q.kind < 1.5) {
        // Off the pool: up and a little right, fading out as they rise.
        float s = fract(q.start + t * q.speed);
        float x = poolCentre.x * aspect + q.lane * 0.13 + s * 0.06 + 0.01 * wobble;
        float y = poolCentre.y + 0.015 - s * (0.16 + 0.12 * q.phase) + abs(q.lane) * 0.01;
        o.at = centre + (float2(x, y) - centre) * squeeze;
        o.life = smoothstep(0.0, 0.15, s) * smoothstep(1.0, 0.45, s);
        return o;
    } else {
        // Loose in the air, slow and dim.
        float s = fract(q.start + t * q.speed);
        float x = (s * 1.2 - 0.1) * aspect;
        float y = 0.18 + fract(q.phase * 7.13 + q.lane * 0.11) * 0.72 + 0.012 * wobble;
        o.at = centre + (float2(x, y) - centre) * squeeze;
        o.life = smoothstep(0.0, 0.1, s) * smoothstep(1.0, 0.9, s) * 0.55;
        return o;
    }
}

vertex DotOut moon_dot_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              constant Particle *field [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]]) {
    Particle q = field[iid];
    float W = u.size.x, H = u.size.y, t = u.size.z, aspect = u.size.w;
    Place place = motePlace(q, t, aspect);
    float2 p = place.at;
    float depth = place.depth;

    float sharp = q.size / depth * H;
    float blur = depth < focusDepth
        ? aperture * (focusDepth - depth) / depth * H
        : aperture * 0.18 * (depth - focusDepth) / depth * H;
    float lens = lensBlur * smoothstep(lensFrom, 1.0, p.x / aspect) * H;
    blur = sqrt(blur * blur + lens * lens);
    float radius = max(sqrt(sharp * sharp + blur * blur), 0.9);
    // The same light spread wider is fainter, but bokeh stays visible.
    float spread = clamp(pow(max(sharp, 0.9) / radius, 1.3), 0.11, 1.0);
    float far = clamp(2.2 / depth, 0.4, 1.0);
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
    o.alpha = place.life * spread * far * twinkle * bright * u.accent.w * u.look.y * clamp(sharp / 0.9, 0.3, 1.0);
    o.bokeh = smoothstep(2.5, 12.0, blur);
    o.color = q.tint > 0.5 ? mix(u.ink.rgb, u.accent.rgb, 0.25) : mix(u.accent.rgb, float3(1.0), 0.3);
    if (u.look.w > 0.0) {
        float3 spectral = arcaneSpectrum(float2(p.x / aspect, p.y), t, q.phase * 0.11);
        o.color = mix(o.color, mix(spectral, float3(1.0), q.tint > 0.5 ? 0.55 : 0.18), u.look.w);
    }
    o.alpha *= mix(1.0, arcaneIntensity * 1.45 * mix(0.85, 0.22, o.bokeh), u.look.w);
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
