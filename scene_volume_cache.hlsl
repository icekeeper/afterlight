// Procedural startup prepass. This 512x512 atlas is a 64^3 world-space field.
// R: optical depth tau = 2.6 * integral(rho_macro ds), central star to voxel.
// GBA: signed analytic curl velocity in world units/second, stored directly.
// The cache contains no photographs, external textures, or simulated state.
// Unlike Media Error's top-down rolling integral, this traces the entire path
// from a central point light. Fine advected dust remains a runtime calculation.
#define NURSERY_CACHE_BUILD
#include "scene_common.hlsl"
#include "scene_rebirth.hlsl"

float4 PSMain(float4 position : SV_POSITION,float2 uv : TEXCOORD0) : SV_TARGET
{
    float2 pixel=floor(position.xy);
    float2 tile=floor(pixel/64.0);
    float slice=tile.x+tile.y*8.0;
    float2 voxelXY=pixel-tile*64.0;
    float3 coordinate=(float3(voxelXY,slice)+0.5)/64.0;
    float3 world=lerp(n2CacheMin,n2CacheMax,coordinate);
    float3 fromStar=world-n2Star;
    float pathLength=length(fromStar);
    float opticalDepth=0.0;
    const int integrationSteps=64;
    float segment=pathLength/float(integrationSteps);
    [loop] for(int i=0;i<integrationSteps;i++)
    {
        float fraction=(float(i)+0.5)/float(integrationSteps);
        opticalDepth+=n2MacroDensity(n2Star+fromStar*fraction)*segment;
    }
    return float4(opticalDepth*2.6,n2CurlVelocity(world));
}
