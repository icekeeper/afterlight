// ALL THINGS BEGIN AGAIN / a three-dimensional stellar nursery.
// Sculpted volumes are evaluated in world space, with extinction along both
// view and light rays. The atlas is generated mathematically on the GPU.
// Cached lighting / separate flow detail: Smash's Media Error and Frameranger
// writeups, https://directtovideo.wordpress.com/2009/09/29/old-demos-2-media-error-and-track-one/
// and https://directtovideo.wordpress.com/2009/09/30/frameranger/ . This is an
// original point-light adaptation, not those demos' fixed-direction algorithm.

static const float3 n2Star=float3(0.05,0.64,1.35);
static const float3 n2CacheMin=float3(-7.5,-7.5,-5.5);
static const float3 n2CacheMax=float3(7.5,7.5,9.5);

float3 n2Displacement(float3 p)
{
    return float3(sin(p.y*1.15+p.z*0.65),sin(p.z*0.9+p.x*0.55),cos(p.x*0.8-p.y*0.6))*0.53;
}

// Curl of A(p) = sum(a_i sin(dot(k_i,p)+phase_i)). Each term below is
// cross(k_i,a_i)*cos(...), so the continuous analytic field is divergence-free.
// Constant scaling preserves that property; there is no per-voxel normalization.
// The sum of the four velocity-amplitude lengths is below 0.120 world units/s.
float3 n2CurlVelocity(float3 p)
{
    float3 k0=float3(0.70,1.10,-0.45),a0=float3(0.023,-0.009,0.017);
    float3 k1=float3(1.50,-0.65,0.75),a1=float3(-0.009,0.014,0.010);
    float3 k2=float3(-2.30,1.40,0.95),a2=float3(0.004,0.005,-0.007);
    float3 k3=float3(4.60,2.20,-2.70),a3=float3(0.0018,-0.0022,0.0015);
    return cross(k0,a0)*cos(dot(k0,p)+0.7)
         + cross(k1,a1)*cos(dot(k1,p)+2.1)
         + cross(k2,a2)*cos(dot(k2,p)+4.8)
         + cross(k3,a3)*cos(dot(k3,p)+1.3);
}

float n2Fbm(float3 q)
{
    float result=noise3(q)*0.52;
    q=q.yzx*2.07+float3(4.7,11.1,2.3);result+=noise3(q)*0.265;
    q=q.zxy*2.03+float3(7.1,2.3,9.6);result+=noise3(q)*0.135;
    q=q.yzx*2.11+float3(2.7,8.6,3.2);result+=noise3(q)*0.068;
    return result;
}

float n2Pillar(float3 p,float3 base,float height,float width,float bend,float phase)
{
    float3 q=p-base;
    float h=saturate((q.y+0.5)/height);
    float angle=h*3.1+phase;
    q.x-=bend*h*h+sin(angle)*0.22*h+sin(q.y*2.3+phase)*0.11;
    q.z-=sin(h*3.6+phase)*0.38*h;
    float radius=width*(1.10-h*0.60)+0.10*sin(h*12.0+phase);
    float cap=max(q.y-height*0.80,0.0);
    return max(length(float3(q.x,q.z*0.84,cap))-radius,-q.y-height*0.13);
}

float n2Skeleton(float3 p)
{
    // Uneven finger-like columns: they surround the star without making a sphere.
    float d=n2Pillar(p,float3(-3.45,-3.55,1.30),5.25,0.91,1.08,1.4);
    d=min(d,n2Pillar(p,float3(-1.65,-3.45,0.05),3.75,0.59,0.72,3.7));
    d=min(d,n2Pillar(p,float3(2.85,-3.40,1.80),4.60,0.97,-0.83,5.9));
    d=min(d,n2Pillar(p,float3(3.85,-2.40,4.30),4.80,0.73,-1.28,8.0));
    // A vaulted cloud bank behind the pillars; the front remains open to space.
    float3 arc=p-float3(-0.65,0.5,3.5);
    arc.xy=rot(arc.xy,-0.19);
    arc.x+=sin(arc.y*1.4+sin(arc.x*0.9))*0.34;
    arc.y+=sin(arc.x*0.94)*0.40;
    float arch=length(arc.xy*float2(0.79,1.0));
    float archAngle=atan2(arc.y,arc.x);
    float shell=length(float2(arch-3.30-0.30*sin(archAngle*3.0),arc.z*0.72))-0.49;
    shell=max(shell,-arc.y-0.55);
    shell=max(shell,0.78-length((p-float3(1.0,3.6,3.5))*float3(0.85,1.0,0.80)));
    d=min(d,shell);
    // Heavy lower molecular cloud supports the slender illuminated pillars.
    float floorCloud=length((p-float3(0,-4.0,3.5))*float3(0.21,0.80,0.22))-1.0;
    d=min(d,floorCloud*1.2);
    return d;
}

// Only the macro structure participates in the precomputed light integral.
// Animated micro-turbulence has approximately the same mean optical thickness.
float n2MacroDensity(float3 p)
{
    float3 displacement=n2Displacement(p);
    float baseDE=n2Skeleton(p+displacement*0.63);
    float density=0;
    [branch] if(baseDE<=1.8)
    {
        float coarse=noise3(p*0.69+float3(4.1,1.3,7.7));
        float turbulence=n2Fbm((p+displacement)*2.15);
        float d=baseDE+(turbulence-0.51)*1.9+(coarse-0.50)*1.1;
        float envelope=1.0-smoothstep(-0.27,0.33,d);
        float fissures=saturate((turbulence*0.48+0.49*0.52-0.20)*2.10);
        float cavity=length((p-n2Star)*float3(1.0,1.12,0.91));
        density=envelope*(0.035+fissures*fissures*1.15)
            *smoothstep(0.74,1.39,cavity+(turbulence-0.5)*0.55);
    }
    return density;
}

#ifndef NURSERY_CACHE_BUILD
Texture2D<float4> nurseryCache : register(t7);
SamplerState nurserySampler : register(s0);

// 64^3 voxel CENTERS in an 8x8 atlas of 64x64 tiles. XY filtering cannot
// reach an adjacent tile; Z is explicitly interpolated between two slices.
// R = 2.6 * integral(rho_macro ds), GBA = signed curl velocity in world units/s.
float4 n2CacheAt(float3 p)
{
    float3 g=clamp((p-n2CacheMin)/(n2CacheMax-n2CacheMin)*64.0-0.5,0.0,63.0);
    float z0=floor(g.z),z1=min(z0+1.0,63.0);
    float2 tile0=float2(fmod(z0,8.0),floor(z0/8.0));
    float2 tile1=float2(fmod(z1,8.0),floor(z1/8.0));
    float2 uv0=(tile0*64.0+g.xy+0.5)/512.0;
    float2 uv1=(tile1*64.0+g.xy+0.5)/512.0;
    return lerp(nurseryCache.SampleLevel(nurserySampler,uv0,0),
                nurseryCache.SampleLevel(nurserySampler,uv1,0),frac(g.z));
}

float4 n2Matter(float3 p,float3 velocity,float clock)
{
    float3 displacement=n2Displacement(p);
    float baseDE=n2Skeleton(p+displacement*0.63);
    // The three noise terms can lower the distance by at most 1.7248.
    // Above 2.0 the envelope is therefore exactly zero; skip empty-space noise.
    float4 result=0;
    [branch] if(baseDE<=2.0)
    {
        float coarse=noise3(p*0.69+float3(4.1,1.3,7.7));
        float coarseDE=baseDE+(coarse-0.50)*1.1;
        // Remaining turbulence/fine terms can lower d by at most 1.1748.
        [branch] if(coarseDE<=1.425)
        {
            float turbulence=n2Fbm((p+displacement)*2.15);
            float macroDE=coarseDE+(turbulence-0.51)*1.9;
            // Fine noise can lower d by at most 0.2058. Cull before the
            // extra atlas lookup and three high-frequency noise evaluations.
            [branch] if(macroDE<=0.456)
            {
                // Midpoint backtrace through the cached curl field. Macro
                // density stays anchored; fine dust follows the coherent flow.
                float3 midpoint=p-velocity*(clock*0.5);
                float3 advected=p-n2CacheAt(midpoint).gba*clock;
                float3 warped=advected+displacement;
                float fine=noise3(warped*10.1+turbulence*2.1)*0.58;
                fine+=noise3(warped.zxy*22.9+float3(3.7,13.1,4.1))*0.27;
                fine+=noise3(warped.yzx*49.7+float3(8.4,2.2,15.0))*0.13;
                float d=macroDE+(fine-0.49)*0.42;
                float envelope=1.0-smoothstep(-0.19,0.25,d);
                float fissures=saturate((turbulence*0.48+fine*0.52-0.20)*2.10);
                float density=envelope*(0.035+fissures*fissures*1.15);
                float cavity=length((p-n2Star)*float3(1.0,1.12,0.91));
                density*=smoothstep(0.74,1.39,cavity+(turbulence-0.5)*0.55);
                float edge=exp(-abs(d-0.025)*13.0);
                float vein=pow(saturate(1.0-abs(fine*2.0-1.0)),18.0);
                float mineral=coarse*0.57+0.225+0.15*sin(p.y*0.64-p.x*0.59+turbulence*3.4);
                result=float4(density,edge,vein,mineral);
            }
        }
    }
    return result;
}

// Optically thin, animated material is intentionally outside the static cache.
// Three curled stellar-wind streamers and a torn shock surface travel through
// world space, so they receive proper foreground occlusion and parallax.
float2 n2WindMatter(float3 p,float3 velocity,float clock,float shockRadius)
{
    float3 radial=p-n2Star;
    float radius=length(radial);
    float2 result=0;
    [branch] if(radius>0.38&&radius<5.4)
    {
        float thickness=0.07+0.025*radius;
        float3 plumeDir=normalize(radial+velocity*(2.8+radius*1.2));
        float3 angles=float3(dot(plumeDir,normalize(float3(-0.62,0.77,-0.31))),
            dot(plumeDir,normalize(float3(0.69,-0.25,-0.60))),
            dot(plumeDir,normalize(float3(0.27,0.82,0.50))));
        // Below these cosine bounds each angular lobe contributes under 1e-5.
        // Grain moves the shock at most 0.11; outside 3.4 sigma it is <1e-5.
        bool hasPlume=radius>0.45&&radius<4.7&&any(angles>float3(0.912,0.9326,0.9412));
        bool hasShock=clock>4.0&&abs(radius-shockRadius)<0.11+3.4*thickness;
        [branch] if(hasPlume||hasShock)
        {
            float3 warped=radial-velocity*clock*1.9;
            float grain=noise3(warped*4.7+float3(0,-clock*0.13,0));
            float fracture=noise3(warped.zxy*12.8+grain*2.8);
            float shock=0,plumes=0;
            [branch] if(hasShock)
            {
                float shellDistance=(radius-shockRadius+(grain-0.5)*0.22)/thickness;
                shock=exp(-shellDistance*shellDistance);
                shock*=smoothstep(0.34,0.68,fracture)*smoothstep(4.0,9.0,clock);
            }
            [branch] if(hasPlume)
            {
                float plumeA=pow(saturate(angles.x),125.0);
                float plumeB=pow(saturate(angles.y),165.0);
                float plumeC=pow(saturate(angles.z),190.0);
                float3 direction=radial/max(radius,0.001);
                float flow=noise3(warped*2.35-direction*clock*0.18);
                plumes=(plumeA+plumeB*0.85+plumeC*0.70)*smoothstep(0.29,0.67,flow);
                plumes*=smoothstep(0.45,0.95,radius)*(1.0-smoothstep(2.7,4.7,radius));
                plumes*=smoothstep(0.43,0.70,fracture);
            }
            result=float2(plumes*0.026+shock*0.010,shock+plumes*0.14);
        }
    }
    return result;
}

float n2Phase(float cosine)
{
    // Two Henyey-Greenstein lobes, expressed relative to unit isotropic
    // scattering (4*pi cancels). Forward dust + a small backscatter component.
    const float forwardG=0.42,backwardG=-0.20;
    float frontBase=max(0.001,1.0+forwardG*forwardG-2.0*forwardG*cosine);
    float backBase=max(0.001,1.0+backwardG*backwardG-2.0*backwardG*cosine);
    float front=(1.0-forwardG*forwardG)*rsqrt(frontBase)/frontBase;
    float back=(1.0-backwardG*backwardG)*rsqrt(backBase)/backBase;
    return 0.84*front+0.16*back;
}

// Shared by the nursery and the black-hole release. The conversion front scales
// LOCAL extinction/emission; it never interpolates two finished scene images.
void n2IntegrateSample(float3 q,float3 ray,float local,float growth,float ds,float conversion,
    inout float3 transmit,inout float3 radiance)
{
    float4 cached=n2CacheAt(q);
    float4 matter=n2Matter(q,cached.gba,local);
    float shockRadius=0.50+max(0,local-6.0)*0.135;
    float2 wind=n2WindMatter(q,cached.gba,local,shockRadius);
    float3 toStar=n2Star-q;
    float r2=dot(toStar,toStar),r=sqrt(r2);
    float3 lightDirection=toStar/max(0.01,r);
    float density=(matter.x+wind.x)*conversion;
    [branch] if(density>0.005)
    {
        float3 visibility=exp(-cached.r*float3(1.00,1.22,1.47));
        float3 alpha=1.0-exp(-density*ds*float3(2.65,3.10,3.65));
        float3 cold=lerp(float3(0.009,0.021,0.087),float3(0.078,0.014,0.10),smoothstep(0.35,0.66,matter.w));
        float3 ion=lerp(float3(0.047,0.38,0.70),float3(1.02,0.245,0.095),smoothstep(0.47,0.67,matter.w));
        float incoming=(7.2+growth*9.0)/(1.3+r2);
        float phase=n2Phase(dot(ray,lightDirection));
        float hotEdge=pow(saturate(matter.y),1.20);
        float3 lit=cold*0.18;
        lit+=ion*incoming*visibility*phase*(0.038+hotEdge*1.85);
        lit+=ion*matter.z*hotEdge*(0.09+0.22*growth)*(0.025+visibility);
        float windFraction=wind.x/max(matter.x+wind.x,0.001);
        lit+=float3(0.24,0.39,0.86)*windFraction*incoming*visibility*phase*0.45;
        radiance+=transmit*alpha*lit;
        transmit*=1.0-alpha;
    }
    float frontEmission=wind.y*ds*conversion*0.040*(0.3+0.7*growth)/(1+shockRadius*0.35);
    radiance+=transmit*frontEmission*float3(0.20,0.58,1.0);
}

// Analytic stellar point-spread functions share the same foreground extinction
// as the volume. Both renderer entry points use world-space camera rays.
float3 n2StellarRadiance(float3 eye,float3 ray,float local,float3 starVisibility,float3 transmit)
{
    float growth=smoothstep(0.0,26.0,local);
    float starDistance=dot(n2Star-eye,ray);
    float3 closest=eye+ray*max(0,starDistance)-n2Star;
    float starImpact=length(closest);
    float3 sourceStrength=(0.6+growth*1.7)*starVisibility;
    float core=0.018/(starImpact*starImpact+0.0013);
    float halo=exp(-starImpact*starImpact*2.0)*0.11;
    float3 color=(core*float3(1.0,0.80,0.58)+halo*float3(0.13,0.51,0.86))*sourceStrength;
    [unroll] for(int s=0;s<6;s++)
    {
        float seed=float(s)*13.71+4.3;
        float3 nurseryStar=float3((hash11(seed)-0.5)*6.4,(hash11(seed+2.3)-0.5)*4.0,2.6+hash11(seed+8.1)*2.4);
        float along=dot(nurseryStar-eye,ray);
        float perpendicular=length(eye+ray*along-nurseryStar);
        float glint=0.000065/(perpendicular*perpendicular+0.00017);
        color+=glint*lerp(float3(0.27,0.55,1.0),float3(1.0,0.35,0.13),hash11(seed+12.0))*(0.1+transmit*0.9);
    }
    float3 forward=normalize(n2Star-eye);
    float3 right=normalize(cross(float3(0,1,0),forward)),up=cross(forward,right);
    float2 delta=float2(dot(ray,right),dot(ray,up))*1.48/max(dot(ray,forward),0.001);
    float rays=exp(-abs(delta.y)*800.0)*exp(-abs(delta.x)*14.0)+exp(-abs(delta.x)*850.0)*exp(-abs(delta.y)*20.0)*0.35;
    color+=rays*float3(0.36,0.27,0.16)*sourceStrength;
    return max(color,0);
}

// Settled straight-ray specialization of the shared medium integral. Its caller
// supplies the continuous journey camera; no second image is rendered/blended.
float3 n2RenderRay(float3 eye,float3 ray,float t)
{
    float local=max(0,t-144.0),growth=smoothstep(0.0,26.0,local);
    float3 star=n2Star;
    float3 color=space(ray,t*.22,.42);
    float3 radiance=0;
    float3 transmit=1.0,starVisibility=1.0;
    float starDistance=dot(star-eye,ray);
    float2 boundary=sphereHit(eye,ray,float3(0,-0.55,2.1),6.9);
    if(boundary.y>0)
    {
        float begin=max(0,boundary.x),finish=boundary.y;
        float ds=(finish-begin)/128.0;
        float jitter=0.5+j4RayJitter;
        [loop] for(int stepIndex=0;stepIndex<128;stepIndex++)
        {
            float distance=begin+(float(stepIndex)+jitter)*ds;
            float3 q=eye+ray*distance;
            n2IntegrateSample(q,ray,local,growth,ds,1.0,transmit,radiance);
            if(distance<starDistance)starVisibility=transmit;
            if(max(transmit.r,max(transmit.g,transmit.b))<0.009)break;
        }
    }
    color=color*transmit+radiance;

    color+=n2StellarRadiance(eye,ray,local,starVisibility,transmit);
    return max(color,0);
}

float3 rebirthScene(float2 p,float t)
{
    float local=max(0,t-144.0);
    float orbit=-0.145+local*0.010;
    float3 eye=float3(sin(orbit)*9.8,0.23+0.37*sin(local*0.064),-10.9+local*0.093);
    float3 target=float3(0.10+0.25*sin(local*0.046),0.0,1.8);
    float3 ray=cameraRay(rot(p,0.022*sin(local*0.07)),eye,target,1.48);
    return n2RenderRay(eye,ray,t);
}
#endif
