// AFTERLIGHT IV. Spatial handoffs, not image crossfades.
#include "scene_common.hlsl"
#include "scene_journey.hlsl"
#include "scene_planet.hlsl"
#include "scene_rebirth.hlsl"
#include "scene_blackhole.hlsl"
#include "scene_transit.hlsl"
#include "scene_machine.hlsl"
struct SceneOutput { float4 color:SV_TARGET0; float distance:SV_TARGET1; };
SceneOutput PSMain(float4 position:SV_POSITION,float2 uv:TEXCOORD0)
{
    float2 p=(position.xy-.5*resolution)/resolution.y;p.y=-p.y;
    float t=max(0.,time);float3 col=0;
    // Keep volume quadrature stable when the camera moves. Hashing the ray
    // direction would decorrelate fine density samples between adjacent frames.
    j4RayJitter=(hash21(position.xy+float2(83.1,29.7))-.5)*.65;
    [branch] if(t<66.0) col=orbitScene(p,t);
    else if(t<118.0) col=warpScene(p,t);
    else col=blackHoleScene(p,t);
    float distance=t<118.0?transitDepth:j4OpaqueDistance;
    SceneOutput o;
    o.color=float4(clamp(col,0.,60.),distance);
    o.distance=distance;
    return o;
}
