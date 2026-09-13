#pragma once
// Scene values stay in floating point through a five-level optical bloom pyramid.
static const char* BloomSource=R"(
Texture2D source:register(t0); SamplerState linearSampler:register(s0);
cbuffer Composite:register(b1) { float4 state; };
float3 tap(float2 uv) {
    float3 c=source.SampleLevel(linearSampler,uv,0).rgb;
    if(state.z>.5) {
        float b=max(c.r,max(c.g,c.b));
        float soft=clamp(b-.6,0,.8); soft=soft*soft/.8001*.25;
        c*=max(b-1.,soft)/max(b,.0001);
        c=min(c,16.);
    }
    return c;
}
float4 PSMain(float4 p:SV_POSITION,float2 uv:TEXCOORD0):SV_TARGET {
    float2 d=state.xy;
    float3 c=tap(uv)*.20;
    c+=(tap(uv+d*float2(-1,-1))+tap(uv+d*float2(1,-1))+tap(uv+d*float2(-1,1))+tap(uv+d*float2(1,1)))*.125;
    c+=(tap(uv+d*float2(-2,0))+tap(uv+d*float2(2,0))+tap(uv+d*float2(0,-2))+tap(uv+d*float2(0,2)))*.075;
    return float4(c,1);
}
)";
static const char* CompositeSource=R"(
Texture2D scene:register(t0); Texture2D overlay:register(t1);
Texture2D bloom0:register(t2); Texture2D bloom1:register(t3); Texture2D bloom2:register(t4);
Texture2D bloom3:register(t5); Texture2D bloom4:register(t6);
SamplerState linearSampler:register(s0);
cbuffer Composite:register(b1) { float4 state; };
float3 tonemap(float3 c) {
    c=max(0,c)*1.12;
    c=(c*(2.51*c+.03))/(c*(2.43*c+.59)+.14);
    return pow(saturate(c),1./2.2);
}
float4 PSMain(float4 p:SV_POSITION,float2 uv:TEXCOORD0):SV_TARGET {
    float2 radial=uv-.5;
    float2 ca=radial*dot(radial,radial)*.00065;
    float3 c=scene.Sample(linearSampler,uv).rgb;
    c.r=scene.Sample(linearSampler,uv+ca).r;
    c.b=scene.Sample(linearSampler,uv-ca).b;
    float3 bloom=bloom0.Sample(linearSampler,uv).rgb*.22+bloom1.Sample(linearSampler,uv).rgb*.25;
    bloom+=bloom2.Sample(linearSampler,uv).rgb*.27+bloom3.Sample(linearSampler,uv).rgb*.28+bloom4.Sample(linearSampler,uv).rgb*.30;
    c+=bloom*.32;
    // Low-energy anamorphic scatter, proportional to actual scene highlights.
    [unroll] for(int i=1;i<=3;i++) {
        float2 d=float2(float(i)*.024,0);
        c+=(bloom2.Sample(linearSampler,uv+d).rgb+bloom2.Sample(linearSampler,uv-d).rgb)*(.012/float(i));
    }
    c*=1-.24*smoothstep(.24,.78,length(radial*float2(1.15,1)));
    c=tonemap(c);
    float grain=frac(sin(dot(p.xy+frac(state.y)*170.13,float2(12.9898,78.233)))*43758.5453)-.5;
    c+=grain/340.;
    c*=smoothstep(0.,3.,state.y)*(1-smoothstep(174.,180.,state.y));
    c*=1-state.x*min(.9,.70*(1-smoothstep(0,.85,uv.x))+.4*smoothstep(.78,1.,uv.y));
    float4 o=overlay.Sample(linearSampler,uv);
    return float4(lerp(c,o.rgb,o.a),1);
}
)";
