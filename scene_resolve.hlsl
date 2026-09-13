// Contact shading for the hybrid ray-marched / instanced scene.
// World positions and normals are reconstructed from the final visible distance.
// Coherent lighting was a central lesson of Smash's Frameranger making-of:
// https://directtovideo.wordpress.com/2009/09/30/frameranger/
#include "scene_common.hlsl"
#include "scene_journey.hlsl"
#define TRANSIT_GEOMETRY_ONLY
#include "scene_transit.hlsl"
Texture2D<float4> surfaceImage:register(t0);

float3 rsRay(float2 pixel,float3 forward,float3 right,float3 up,float bank,float focal)
{
    float2 film=(pixel-.5*resolution)/resolution.y; film.y=-film.y;
    film=rot(film,bank);
    return normalize(right*film.x+up*film.y+forward*focal);
}

float3 rsRelative(float2 pixel,float3 forward,float3 right,float3 up,float bank,float focal)
{
    float2 valid=clamp(floor(pixel),0.0,resolution-1.0);
    return rsRay(valid+.5,forward,right,up,bank,focal)*surfaceImage.Load(int3(int2(valid),0)).a;
}

float4 PSMain(float4 position:SV_POSITION,float2 uv:TEXCOORD0):SV_TARGET
{
    float4 surface=surfaceImage.Load(int3(int2(position.xy),0));
    if(surface.a>=124.5)return surface;
    float3 eye,target; float bank,focal;
    tr3Camera(time,eye,target,bank,focal);
    float3 forward=normalize(target-eye),right=normalize(cross(float3(0,1,0),forward)),up=cross(forward,right);
    float3 ray=rsRay(position.xy,forward,right,up,bank,focal);
    float3 center=ray*surface.a;
    // Choose the smaller one-sided derivative at silhouettes. This prevents
    // the foreground edge from borrowing a normal from distant background.
    float3 xp=rsRelative(position.xy+float2(1,0),forward,right,up,bank,focal)-center;
    float3 xm=center-rsRelative(position.xy-float2(1,0),forward,right,up,bank,focal);
    float3 yp=rsRelative(position.xy+float2(0,1),forward,right,up,bank,focal)-center;
    float3 ym=center-rsRelative(position.xy-float2(0,1),forward,right,up,bank,focal);
    float3 dx=dot(xp,xp)<dot(xm,xm)?xp:xm;
    float3 dy=dot(yp,yp)<dot(ym,ym)?yp:ym;
    float3 crossNormal=cross(dx,dy);
    float3 normal=crossNormal*rsqrt(max(dot(crossNormal,crossNormal),1e-16));
    normal*=dot(normal,-ray)<0.0?-1.0:1.0;
    float worldRadius=1.25;
    float pixels=clamp(resolution.y*focal*worldRadius/max(dot(center,forward),.1),2.,56.);
    float angle=hash21(floor(position.xy))*TAU;
    float occlusion=0.0;
    [unroll]for(int i=0;i<16;i++)
    {
        float phi=angle+float(i)*2.399963;
        float sampleRadius=sqrt((float(i)+.5)/16.0)*pixels;
        float2 samplePixel=position.xy+float2(cos(phi),sin(phi))*sampleRadius;
        float3 delta=rsRelative(samplePixel,forward,right,up,bank,focal)-center;
        float d2=dot(delta,delta);
        float hemisphere=saturate((dot(normal,delta)-0.025)*rsqrt(max(d2,0.0001)));
        occlusion+=hemisphere*exp(-d2/(worldRadius*worldRadius));
    }
    // Contact shading grows with released matter and recedes as that matter
    // reaches the horizon. Starting/stopping the pass cannot change an image
    // before a fragment exists or after the last fragment has been absorbed.
    float matter=tr3Release(j4FlightZ(time),time)*(1.0-j4Ease(114.0,120.0,time));
    float visibility=1.0-min(.80,occlusion*(3.9/16.0))*matter;
    // Preserve light sources while contact-shadowing reflected surface light.
    float emission=smoothstep(.60,2.0,max(surface.r,max(surface.g,surface.b)));
    surface.rgb*=lerp(visibility,1.0,emission);
    return surface;
}
