// AFTERLIGHT / III: THE CHOIR OF DISTANCE
// Entirely procedural: a swept octagonal nave, recursive flying buttresses,
// inset machinery, animated phosphor circuits, and world-space light motes.
// The empty aperture remains deliberately readable between massive dark ribs.
// Formation/release design inspired by Smash's surface-target particle method:
// https://directtovideo.wordpress.com/2010/04/19/agenda-circling-forth/
// Camera choreography takes the action-camera lesson from Loonies' own notes:
// https://www.pouet.net/prod_nfo.php?which=75790

static float transitDepth=65000.0;

float2 tr2Path(float z)
{
    return j4Path(z);
}

float tr2Twist(float z, float t)
{
    return z*0.038+0.28*sin(z*0.046)+0.10*sin(t*0.12);
}

float tr3FlightZ(float t)
{
    return j4FlightZ(t);
}

float3 tr3IrisCenter()
{
    return float3(tr2Path(222.0),222.0);
}

void tr3Camera(float t,out float3 eye,out float3 target,out float bank,out float focal)
{
    j4TransitCamera(t,eye,target,bank,focal);
}

float tr3Release(float worldZ,float t)
{
    // The same moving front withdraws the SDF shell and releases its shards.
    float arrival=75.0+0.055*(worldZ-64.0);
    return smoothstep(arrival,arrival+8.0,t);
}

float tr3Reform(float t)
{
    return smoothstep(93.0,104.0,t);
}

float tr2Box(float3 q, float3 b)
{
    float3 d=abs(q)-b;
    return length(max(d,0.0))+min(max(d.x,max(d.y,d.z)),0.0);
}

float tr2Capsule(float3 p,float3 a,float3 b,float radius)
{
    float3 v=b-a,w=p-a;
    return length(w-v*saturate(dot(w,v)/dot(v,v)))-radius;
}

float3 tr2Local(float3 p,float t)
{
    p.xy=rot(p.xy-tr2Path(p.z),tr2Twist(p.z,t));
    return p;
}

float3 tr2Fold(float3 p)
{
    // Exact dihedral fold using only abs, a swap and a constant rotation.
    // Avoid atan2/sincos in every distance query of the raymarch.
    p.xy=abs(p.xy);
    if(p.y>p.x)p.xy=p.yx;
    if(p.y>p.x*0.41421356237)
        p.xy=float2(p.x+p.y,p.y-p.x)*0.70710678118;
    return p;
}

float2 tr2Map(float3 p,float t)
{
    float3 q=tr2Fold(tr2Local(p,t));
    float release=tr3Release(p.z,t);
    // Architecture withdraws behind the released blocks. The last stage
    // opens into space instead of retaining an unrelated intact tunnel.
    float spread=1.0+release*release*(2.9+6.0*tr3Reform(t));
    q.xy/=spread;
    // Empty central aperture: no structure reaches inside this safe bound.
    // Most of a forward ray can therefore skip all the fine distance work.
    float endPlanes=max(24.0-p.z,p.z-215.0);
    if(q.x<5.35)return float2(max(5.65-q.x,endPlanes),1.0);
    float bay=floor((q.z+4.0)/8.0);
    q.z-=bay*8.0;
    float z=abs(q.z);
    float a=abs(q.y);
    // Main shell is an octagonal cavity. Its relief is real geometry, with
    // panels recessed half a unit behind the ribs instead of flat decoration.
    // Finite outer wall leaves a real rim at each end, rather than an
    // infinite solid exterior that would become a giant closing plane.
    float2 result=float2(max(7.85-q.x,q.x-8.35),1.0);
    float d=tr2Box(float3(q.x-7.58,q.y,q.z),float3(0.22,2.65,3.60));
    if(d<result.x)result=float2(d,2.0);
    // Raised panel frames and chunky receding vault ribs.
    d=tr2Box(float3(q.x-7.14,a-2.68,q.z),float3(0.33,0.12,4.0));
    if(d<result.x)result=float2(d,1.0);
    d=tr2Box(float3(q.x-6.82,q.y,q.z),float3(1.06,2.91,0.21));
    if(d<result.x)result=float2(d,1.0);
    d=tr2Box(float3(q.x-6.02,q.y,z-0.33),float3(0.31,2.63,0.095));
    if(d<result.x)result=float2(d,2.0);
    // A narrow luminous inner reveal makes the arch silhouettes legible.
    d=tr2Box(float3(q.x-5.695,q.y,z-0.28),float3(0.033,2.47,0.066));
    if(d<result.x)result=float2(d,3.0);
    // Flying buttresses: a central rib branches into two diagonal spurs,
    // and secondary branches bridge those into the outer coffer corners.
    // Folding y and z repeats four branches per angular sector.
    float3 b=float3(q.x,a,z);
    d=tr2Capsule(b,float3(5.89,0.0,0.36),float3(7.25,2.48,3.72),0.14);
    if(d<result.x)result=float2(d,1.0);
    d=tr2Capsule(b,float3(6.33,0.85,1.49),float3(7.28,0.0,3.55),0.087);
    if(d<result.x)result=float2(d,2.0);
    d=tr2Capsule(b,float3(6.76,1.64,2.64),float3(7.33,2.54,1.28),0.064);
    if(d<result.x)result=float2(d,2.0);
    // Three nested micro-coffers set behind the macro structure.
    // The distance is bounded by the shell so the additional repetition
    // cannot turn the open nave into a noisy field of isolated objects.
    if(q.x>6.1)
    {
        float3 c=float3(q.x-7.23,frac((q.y+3.0)/1.0)*1.0-0.5,
                          frac((q.z+4.0)/1.2)*1.2-0.6);
        float frame=tr2Box(c,float3(0.15,0.45,0.52));
        float inset=tr2Box(c-float3(-0.14,0,0),float3(0.22,0.35,0.42));
        d=max(frame,-inset);
        if(d<result.x)result=float2(d,2.0);
        // Longitudinal light rails hide beneath the rib structure.
        d=tr2Box(float3(q.x-7.0,a-2.46,q.z),float3(0.036,0.035,4.0));
        if(d<result.x)result=float2(d,4.0);
    }
    result.x=max(result.x,endPlanes);
    return result;
}

float3 tr2Normal(float3 p,float t,float epsilon)
{
    float2 e=float2(epsilon,-epsilon);
    return normalize(e.xyy*tr2Map(p+e.xyy,t).x+
                     e.yyx*tr2Map(p+e.yyx,t).x+
                     e.yxy*tr2Map(p+e.yxy,t).x+
                     e.xxx*tr2Map(p+e.xxx,t).x);
}

float tr2Occlusion(float3 p,float3 n,float t)
{
    float occ=0.0;
    float weight=1.0;
    [unroll]for(int j=0;j<5;++j)
    {
        float d=0.055*pow(2.0,float(j));
        occ+=(d-tr2Map(p+n*d,t).x)*weight;
        weight*=0.72;
    }
    return saturate(1.0-occ*2.1);
}

float tr2Shadow(float3 p,float3 lightDirection,float lightDistance,float t)
{
    float s=0.04,visibility=1.0;
    [loop]for(int j=0;j<12;++j)
    {
        float h=tr2Map(p+lightDirection*s,t).x;
        visibility=min(visibility,10.0*h/s);
        if(h<0.002||s>lightDistance)break;
        s+=clamp(h*0.76,0.07,0.85);
    }
    return 0.025+0.975*saturate(visibility);
}

float3 tr2GateColor(float bay,float t)
{
    float gold=step(0.74,hash11(bay+31.0));
    float alternate=step(0.50,frac(bay*0.61803398875));
    float3 cold=lerp(float3(0.25,0.07,1.0),float3(1.0,0.035,0.36),alternate);
    return lerp(cold,float3(1.0,0.39,0.06),gold);
}

float3 tr2Material(float3 pos,float3 ray,float3 normal,float t,float mat,float travel)
{
    float3 local=tr2Local(pos,t);
    float3 q=tr2Fold(local);
    float shellRelease=tr3Release(pos.z,t);
    float shellScale=1.0+shellRelease*shellRelease*(2.9+6.0*tr3Reform(t));
    q.xy/=shellScale;
    float sector=floor((atan2(local.y,local.x)+PI/8.0)/(PI/4.0));
    float bay=floor((q.z+4.0)/8.0);
    q.z-=bay*8.0;
    // The released architecture loses power as its material peels away.
    // Keep the first reveal bright, then hand the image to the free matter.
    float gatePower=1.0-smoothstep(0.60,0.97,shellRelease);
    float3 gate=tr2GateColor(bay,t)*gatePower;
    float flow=0.45+0.55*pow(0.5+0.5*sin(pos.z*0.40-t*3.4),5.0);
    float pulse=0.85+0.15*beat;
    if(mat>2.5)
    {
        if(mat<3.5)
        {
            // Deliberate dark gaps and moving subdivisions make each gate
            // look built from light modules, not an unbroken neon outline.
            float module=step(0.09,frac(q.y*1.9+sector*0.21));
            return gate*(3.7+2.8*flow)*pulse*(0.12+0.88*module);
        }
        return float3(0.11,0.38,1.0)*(2.0+2.0*flow)*pulse*gatePower;
    }

    float panels=hash21(float2(floor(q.y*1.3),floor(q.z*1.5))+bay*13.0);
    float grain=noise3(pos*17.0)*0.5+noise3(pos*43.0)*0.5;
    float3 base=lerp(float3(0.009,0.014,0.026),float3(0.09,0.12,0.18),panels*0.24+grain*0.13);
    if(mat>1.5)base*=1.22;

    // Light emitted by this arch and the one in front. The finite-distance
    // falloff and opposing colors reveal curvature and specular shoulders.
    float2 gateCenter=tr2Path(bay*8.0);
    float2 nearestSide=normalize(pos.xy-gateCenter);
    float2 sourceOffset=rot(nearestSide,0.62+0.20*sin(bay*2.17))*5.35*shellScale;
    float3 source=float3(gateCenter+sourceOffset,bay*8.0-0.27);
    float3 delta=source-pos;
    float distance=length(delta);
    float3 ld=delta/max(distance,0.001);
    float ndl=saturate(dot(normal,ld));
    float3 halfDirection=normalize(ld-ray);
    float roughness=lerp(45.0,135.0,panels);
    float fresnel=0.34+0.66*pow(1.0-saturate(dot(normal,-ray)),5.0);
    float spec=pow(saturate(dot(normal,halfDirection)),roughness)*roughness*0.030*fresnel;
    float attenuation=14.0/(1.5+distance*distance);
    float shadow=tr2Shadow(pos+normal*0.025,ld,distance,t);
    float3 color=base*(0.045+gate*ndl*attenuation*2.4*shadow);
    color+=gate*spec*attenuation*1.8*shadow;

    float3 fill=normalize(float3(tr2Path(pos.z-4.0),pos.z-4.0)-pos);
    float diff=saturate(dot(normal,fill));
    float spec2=pow(saturate(dot(normal,normalize(fill-ray))),65.0);
    color+=float3(0.14,0.25,0.70)*(base*diff*0.35+spec2*0.38);
    float edge=pow(1.0-saturate(dot(normal,-ray)),3.0);
    color+=float3(0.006,0.007,0.022)*edge;
    color*=tr2Occlusion(pos,normal,t);

    // Procedural printed circuits inside the coffers. Intersecting trace
    // directions are selectively masked so blocks have unique little maps.
    float2 circuitUV=float2(q.y*3.3,q.z*3.0);
    float2 grid=abs(frac(circuitUV)-0.5);
    float hc=hash21(floor(circuitUV)+bay*7.0);
    float traces=1.0-smoothstep(0.015,0.045,min(grid.x,grid.y));
    traces*=step(0.61,hc)*step(7.03,q.x);
    float datapulse=pow(saturate(sin(q.z*4.0-t*3.0+floor(q.y*3.0))),10.0);
    color+=gate*traces*(0.45+1.4*datapulse);
    return color;
}

#ifndef TRANSIT_GEOMETRY_ONLY
float3 tr4Render(float3 eye,float3 ray,float t,out float depthT)
{
    // Clip traversal to the physical corridor. Portal rays may originate
    // before its entrance; backward rays cannot see repeating bays behind it.
    float travelStart=0.03,travelEnd=65000.0;
    bool crossesCorridor=true;
    if(abs(ray.z)>0.00001)
    {
        float entrance=(24.0-eye.z)/ray.z;
        float exit=(215.0-eye.z)/ray.z;
        travelStart=max(travelStart,min(entrance,exit));
        travelEnd=min(400.0,max(entrance,exit));
        crossesCorridor=travelEnd>travelStart;
    }
    else
    {
        crossesCorridor=eye.z>=24.0&&eye.z<=215.0;
        travelEnd=400.0;
    }
    float distance=travelStart+0.002;
    float material=0.0;
    float2 surface=0.0;
    bool hit=false;
    [loop]for(int stepIndex=0;stepIndex<112;++stepIndex)
    {
        if(!crossesCorridor||distance>travelEnd)break;
        surface=tr2Map(eye+ray*distance,t);
        float epsilon=0.0015+distance*0.00013;
        if(surface.x<epsilon){hit=true;material=surface.y;break;}
        // The swept/twisted coordinate field is not an exact SDF. A 0.73
        // safety factor keeps flight smooth across bending ribs.
        distance+=max(0.007,surface.x*0.73);
    }

    // The finite nave ends at z215; the nearest black-hole disc extent is
    // beyond z263.6. An opaque nave hit therefore occludes that background,
    // allowing its much longer integrator to run only through open rays.
    float3 color;
    if(hit)
    {
        float3 pos=eye+ray*distance;
        float3 normal=tr2Normal(pos,t,0.003+distance*0.00012);
        color=tr2Material(pos,ray,normal,t,material,distance);
        depthT=distance;
    }
    else
    {
        float blackHoleDistance;
        color=b4Render((eye-j4BlackHoleOrigin())/j4BlackHoleScale,ray,t,blackHoleDistance);
        depthT=min(65000.0,blackHoleDistance*j4BlackHoleScale);
    }

    // Only the section of the ray inside the finite nave accumulates haze.
    // The same background becomes unobscured as the camera leaves the rim.
    float3 fogColor=lerp(float3(0.027,0.005,0.051),float3(0.002,0.004,0.012),tr3Reform(t));
    float mediumLength=crossesCorridor?max(0.0,min(depthT,travelEnd)-travelStart):0.0;
    float fog=1.0-exp(-pow(mediumLength*0.011,1.7));
    color=lerp(color,fogColor,fog*0.78);
    float3 forward=normalize(float3(tr2Path(eye.z+12.0),eye.z+12.0)-eye);
    float vanishing=pow(saturate(dot(ray,forward)),95.0);
    color+=float3(0.060,0.004,0.073)*vanishing*fog*(1.0-tr3Reform(t));
    // Matter is now actual instanced 3D geometry in scene_particles.hlsl.
    return color;
}

float3 warpScene(float2 p,float t)
{
    float3 eye,target;
    float bank,focal;
    tr3Camera(t,eye,target,bank,focal);
    float3 ray=cameraRay(rot(p,bank),eye,target,focal);
    return tr4Render(eye,ray,t,transitDepth);
}
#endif
