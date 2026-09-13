// AFTERLIGHT / THE UNBUILDING: real GPU-instanced matter.
// DrawInstanced(36,24576,0,0), triangle list, no vertex/index buffers.
// First 12288 instances are solid architectural blocks; the rest are dust.
// Entirely analytic, stable instance identities, no imported meshes or assets.
// Inspired by surface-correspondence + weighted release in Agenda Circling Forth:
// https://directtovideo.wordpress.com/2010/04/19/agenda-circling-forth/
// Hardware-instance/effectors principle (our implementation is custom HLSL):
// https://manual.notch.one/2026.1/en/docs/learning/working-in-3d/cloners/
// Flow is a procedural curl field, not a claim to simulate Navier-Stokes.
#include "scene_common.hlsl"
#include "scene_journey.hlsl"
#define TRANSIT_GEOMETRY_ONLY
#include "scene_transit.hlsl"

Texture2D<float> geometryDepth : register(t0);

struct ShardVertex
{
    float4 position : SV_POSITION;
    float3 toEye : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float3 local : TEXCOORD2;
    float3 tint : TEXCOORD3;
    float4 material : TEXCOORD4; // grain seed, dust, release, reform
    float3 world : TEXCOORD5;
    float3 axisX : TEXCOORD6;
    float3 axisY : TEXCOORD7;
};

float3 tr3Curl(float3 p,float t)
{
    // Analytic curl of A=(sin(y+a)sin(z+b), sin(z+c)sin(x+d),
    //                    sin(x+e)sin(y+f)). Spatially coherent, divergence-free.
    float a=t*0.19,b=-t*0.13,c=t*0.23,d=t*0.11,e=-t*0.17,f=t*0.07;
    return float3(sin(p.x+e)*cos(p.y+f)-cos(p.z+c)*sin(p.x+d),
                  sin(p.y+a)*cos(p.z+b)-cos(p.x+e)*sin(p.y+f),
                  sin(p.z+c)*cos(p.x+d)-cos(p.y+a)*sin(p.z+b));
}

float3 tr3RotateShard(float3 p,float3 angles)
{
    p.yz=rot(p.yz,angles.x);
    p.xz=rot(p.xz,angles.y);
    p.xy=rot(p.xy,angles.z);
    return p;
}

ShardVertex VSMain(uint vertexID:SV_VertexID,uint instanceID:SV_InstanceID)
{
    ShardVertex output;
    float3 eye,target;
    float bank,focal;
    tr3Camera(time,eye,target,bank,focal);

    bool dust=instanceID>=12288;
    uint index=instanceID%12288;
    uint localBay=index/768;
    uint sector=(index/96)%8;
    uint panel=index%96;
    uint tangentCell=panel%12;
    uint lengthCell=panel/12;

    // Freeze the identity window before reassembly: a moving camera cannot
    // change a shard's identity once it has joined the distant formation.
    float identityZ=tr3FlightZ(min(time,94.0));
    // Stop recycling the window at the end of the finite architecture.
    float firstBay=min(floor((identityZ+4.0)/8.0)-2.0,11.0);
    float bay=firstBay+float(localBay);
    float seed=bay*768.0+float(sector*96+panel);
    float rnd=hash11(seed*1.371+19.3);
    float rnd2=hash11(seed*2.913+47.7);
    float rnd3=hash11(seed*0.719+8.8);
    float3 randomVector=float3(rnd,rnd2,rnd3)*2.0-1.0;

    float baseZ=bay*8.0+(float(lengthCell)+0.5)-4.0;
    float sideY=(float(tangentCell)+0.5)*0.5-3.0;
    float2 wall=rot(float2(7.46,sideY),float(sector)*PI/4.0);
    float sectorAngle=float(sector)*PI/4.0;
    float sectorOffset=atan2(sideY,7.46);
    float wallAngle=sectorAngle+sectorOffset;
    float wallRadius=length(wall);
    float launch=75.0+0.055*(baseZ-64.0);
    float release=tr3Release(baseZ,time);
    float reform=tr3Reform(time);
    float freeAge=max(0.0,time-launch);

    // Adjacent blocks begin on adjacent wall cells. Whole sheets peel away,
    // roll into helical streams, and only then acquire finer turbulent motion.
    // Eight dense sheets separated by empty sectors; the eye can read the
    // collective gesture before discovering individual blocks within it.
    float streamAngle=sectorAngle+sectorOffset*lerp(1.0,0.34,release)+
        release*(freeAge*0.18+baseZ*0.017+0.26*sin(baseZ*0.10+time*0.22));
    float openingRadius=max(5.7+1.05*sin(baseZ*0.14+sectorAngle*0.7+time*0.25),
        4.4+max(0.0,baseZ-eye.z)*0.10);
    float streamRadius=lerp(wallRadius,openingRadius+0.40*rnd,release);
    float streamZ=baseZ+release*(2.8*sin(wallAngle*3.0+baseZ*0.11+time*0.25)-1.4*sin(freeAge*0.3));
    float3 flow=tr3Curl(float3(wall*0.36,baseZ*0.19),time);
    float3 localCenter=float3(float2(cos(streamAngle),sin(streamAngle))*streamRadius,streamZ);
    localCenter+=flow*(0.34*release);
    if(dust)
    {
        // A second population follows the same sheets, with finer eddies.
        localCenter+=randomVector*(0.18+0.48*release);
        localCenter+=tr3Curl(float3(wall*1.05,baseZ*0.57),time*1.37)*release*0.22;
    }
    localCenter.xy=rot(localCenter.xy,-tr2Twist(localCenter.z,time));
    float3 cameraForward=normalize(target-eye);
    float2 sightCenter=(eye+cameraForward*((localCenter.z-eye.z)/max(cameraForward.z,0.25))).xy;
    float2 streamCenter=lerp(tr2Path(localCenter.z),sightCenter,release*0.82);
    float3 freeCenter=float3(localCenter.xy+streamCenter,localCenter.z);

    // Seven interwoven torus-knot strands. The pieces follow each strand's
    // tangent rather than retaining a uniform row of billboard-like boxes.
    float ringBand=(float(lengthCell)+0.5)/8.0;
    float ringDepth=(float(localBay)+0.5)/16.0;
    float irisAngle=wallAngle+float(localBay/7)*0.024+time*0.105;
    float strandPhase=irisAngle*3.0+float(localBay%7)*(TAU/7.0);
    float minorRadius=2.25+(ringBand-0.5)*0.95+float(localBay/7)*0.19;
    float majorRadius=lerp(15.0,8.9,smoothstep(97.0,108.0,time));
    float irisRadius=majorRadius+minorRadius*cos(strandPhase);
    float3 irisCenter=tr3IrisCenter();
    float3 irisPoint=irisCenter+float3(cos(irisAngle)*irisRadius,
        sin(irisAngle)*irisRadius,minorRadius*sin(strandPhase));
    if(dust)irisPoint+=randomVector*(0.15+ringDepth*0.6);

    // The braid becomes a set of accelerating infall streams. Neighboring
    // cells retain a common phase as they travel toward the same black hole
    // that is visible beyond the corridor; there is no scene-lifetime fade.
    float departure=107.0+float(localBay%7)*0.12+ringBand*0.20;
    float arrival=115.5+ringDepth*2.1+ringBand*0.20;
    float infall=j4Ease(departure,arrival,time);
    float3 blackHole=j4BlackHoleOrigin();
    float3 braidOffset=irisPoint-irisCenter;
    braidOffset.xy=rot(braidOffset.xy,7.5*infall*infall);
    braidOffset.xy*=lerp(1.0,0.12,infall);
    braidOffset.z*=1.0+1.8*sin(PI*infall);
    irisPoint=lerp(irisCenter,blackHole,pow(abs(infall),1.3))+braidOffset;
    float3 center=lerp(freeCenter,irisPoint,reform);

    float fragmentScale=0.48+1.05*rnd*rnd*rnd;
    float3 halfSize=float3(0.075+0.045*rnd2,0.19,0.37)*fragmentScale;
    // A few long blades provide a readable size hierarchy among small pieces.
    if(rnd>0.94)halfSize=float3(0.060,0.14,0.91)*(0.8+0.4*rnd2);
    halfSize*=1.0-release*0.14;
    halfSize=lerp(halfSize,float3(0.050+0.055*rnd2,0.115,0.35+0.30*rnd)*fragmentScale,reform);
    if(dust)
    {
        float size=(0.008+length(center-eye)*0.00035)*(0.6+0.8*rnd);
        halfSize=size.xxx*smoothstep(0.03,0.33,release);
    }
    // Pieces first emerge with the actual moving release front, then shrink
    // only at the local horizon. The capture radius is .70 black-hole units;
    // .72-.85 gives their finite extent a short, spatial absorption margin.
    float born=step(24.0,baseZ)*step(baseZ,215.0)*smoothstep(0.0,0.14,release);
    float horizonDistance=length(center-blackHole)/j4BlackHoleScale;
    float absorption=smoothstep(0.72,0.85,horizonDistance);
    halfSize.xy*=1.0-0.40*infall;
    halfSize.z*=1.0+1.2*infall;
    halfSize*=born*absorption;

    // Reassembly can carry a formerly trailing block across the eye plane.
    // Bend only that near-camera part of its path around a protected view-axis
    // cylinder. Include the full box bound so even the long blades clear it.
    // The smooth maximum and axial taper avoid a hard change in velocity.
    if(reform>0.0)
    {
        float3 relativeCenter=center-eye;
        float along=dot(relativeCenter,cameraForward);
        float3 lateral=relativeCenter-cameraForward*along;
        float lateralLength=length(lateral);
        float protection=1.0-smoothstep(6.0,14.0,abs(along));
        float minimumRadius=(3.5+length(halfSize))*protection;
        float deficit=minimumRadius-lateralLength;
        float rounding=max(0.0,0.8*protection-abs(deficit));
        float push=max(deficit,0.0)+rounding*rounding/max(3.2*protection,0.0001);
        float3 sourceLateral=freeCenter-eye;
        sourceLateral-=cameraForward*dot(sourceLateral,cameraForward);
        float3 direction=lateralLength>0.0001?lateral/lateralLength:
            sourceLateral/max(length(sourceLateral),0.0001);
        center+=direction*push;
    }

    float3 angles=float3(release*(0.24*sin(baseZ*0.16+sectorAngle)+(rnd-0.5)*0.22),
        release*(0.30*cos(baseZ*0.12+time*0.2)+(rnd2-0.5)*0.26),
        lerp(sectorAngle,streamAngle,release)-tr2Twist(baseZ,time));
    float dr=-3.0*minorRadius*sin(strandPhase);
    float3 irisTangent=normalize(float3(dr*cos(irisAngle)-irisRadius*sin(irisAngle),
        dr*sin(irisAngle)+irisRadius*cos(irisAngle),3.0*minorRadius*cos(strandPhase)));
    irisTangent.xy=rot(irisTangent.xy,7.5*infall*infall);
    float3 infallTangent=normalize(blackHole-irisPoint+
        cross(float3(0,0,1),irisPoint-blackHole)*(1.0-infall)*2.0);
    irisTangent=normalize(lerp(irisTangent,infallTangent,infall*0.85));
    float3 irisX=normalize(cross(irisTangent,float3(0,0,1)));
    float3 axisZ=normalize(lerp(tr3RotateShard(float3(0,0,1),angles),irisTangent,reform));
    float3 axisX=normalize(lerp(tr3RotateShard(float3(1,0,0),angles),irisX,reform));
    float3 axisY=normalize(cross(axisZ,axisX));
    axisX=cross(axisY,axisZ);

    uint face=vertexID/6;
    uint corner=vertexID%6;
    float u=(corner==1||corner==4||corner==5)?1.0:-1.0;
    float v=(corner>=2&&corner!=4)?1.0:-1.0;
    float side=(face%2==0)?1.0:-1.0;
    float3 local,normal;
    if(face<2){local=float3(side,u,v);normal=float3(side,0,0);}
    else if(face<4){local=float3(u,side,v);normal=float3(0,side,0);}
    else {local=float3(u,v,side);normal=float3(0,0,side);}
    float3 world=center+axisX*local.x*halfSize.x+axisY*local.y*halfSize.y+axisZ*local.z*halfSize.z;
    normal=axisX*normal.x+axisY*normal.y+axisZ*normal.z;

    float3 forward=normalize(target-eye);
    float3 right=normalize(cross(float3(0,1,0),forward));
    float3 up=cross(forward,right);
    float3 relative=world-eye;
    float viewZ=dot(relative,forward);
    float2 film=rot(float2(dot(relative,right),dot(relative,up)),-bank);
    float aspect=resolution.x/resolution.y;
    const float nearPlane=0.05,farPlane=200.0;
    output.position=float4(film.x*2.0*focal/aspect,film.y*2.0*focal,
        viewZ*(farPlane/(farPlane-nearPlane))-nearPlane*farPlane/(farPlane-nearPlane),viewZ);
    output.toEye=eye-world;
    output.normal=normal;
    output.local=local;
    float3 gate=tr2GateColor(bay,time);
    output.tint=lerp(gate,float3(0.10,0.35,0.85),step(0.82,rnd2)*0.55);
    output.material=float4(rnd,dust?1.0:0.0,release,reform);
    output.world=world;
    output.axisX=axisX;
    output.axisY=axisY;
    return output;
}

float4 PSMain(ShardVertex input):SV_TARGET
{
    float rayDistance=length(input.toEye);
    float sceneDistance=geometryDepth.Load(int3(int2(input.position.xy),0));
    clip(sceneDistance+0.01-rayDistance);
    // Analytic bevel shading catches thin, curved highlights at the edges.
    float3 localNormal=sign(input.local)*pow(abs(input.local),22.0);
    float3 normal=normalize(input.axisX*localNormal.x+input.axisY*localNormal.y+
        cross(input.axisX,input.axisY)*localNormal.z);
    float3 view=input.toEye/max(rayDistance,0.00001);
    float rnd=input.material.x;
    float reform=input.material.w;
    float3 tint=input.tint;

    float cameraZ=tr3FlightZ(time);
    float3 assemblyLight=lerp(tr3IrisCenter(),j4BlackHoleOrigin(),j4Ease(107.0,118.0,time));
    float3 keyPoint=lerp(float3(tr2Path(cameraZ+18.0)+float2(-4.5,5.5),cameraZ+18.0),
        assemblyLight+float3(-10,13,-13),reform);
    float3 fillPoint=lerp(float3(tr2Path(cameraZ+35.0)+float2(7,-2),cameraZ+35.0),
        assemblyLight+float3(12,-5,4),reform);
    float3 keyDelta=keyPoint-input.world,fillDelta=fillPoint-input.world;
    float keyDistance=length(keyDelta),fillDistance=length(fillDelta);
    float3 key=keyDelta/max(keyDistance,0.001);
    float3 fill=fillDelta/max(fillDistance,0.001);
    float keyAttenuation=72.0/(5.0+keyDistance*keyDistance);
    float fillAttenuation=38.0/(5.0+fillDistance*fillDistance);
    float diffuse=saturate(dot(normal,key));
    float diffuse2=saturate(dot(normal,fill));
    float keyHalf=saturate(dot(normal,normalize(view+key)));
    float fillHalf=saturate(dot(normal,normalize(view+fill)));
    float spec=pow(keyHalf,38.0+60.0*rnd);
    float spec2=pow(fillHalf,36.0);
    float fresnel=0.22+0.78*pow(1.0-saturate(dot(normal,view)),5.0);
    float3 metal=lerp(float3(0.035,0.050,0.075),float3(0.115,0.079,0.030),step(0.93,rnd));
    float plating=0.85+0.15*hash31(floor(input.local*14.0)+rnd*103.0);
    float3 keyColor=lerp(float3(0.53,0.71,1.0),float3(1.0,0.69,0.35),reform);
    float3 fillColor=float3(0.30,0.24,0.68);
    // A broad overhead source separates the graded faces even away from the
    // small key. Contact shadows remain the responsibility of depth SSAO.
    float hemi=saturate(dot(normal,normalize(float3(-0.45,0.72,-0.52)))*0.5+0.5);
    float3 softFill=float3(0.14,0.16,0.21)+float3(0.45,0.54,0.68)*hemi*hemi;
    float3 color=metal*plating*(softFill+keyColor*diffuse*keyAttenuation*3.2+
        fillColor*diffuse2*fillAttenuation*1.7);
    // The wide reflection lobe suggests a large emitter; the narrow lobe
    // retains the moving glints that make the bevels read as polished metal.
    color+=keyColor*(spec*fresnel*2.6+pow(keyHalf,8.0)*0.16)*keyAttenuation;
    color+=fillColor*(spec2*fresnel*1.5+pow(fillHalf,6.0)*0.09)*fillAttenuation;

    // Median distance to the box faces measures proximity to a face edge.
    float3 faceDistance=1.0-abs(input.local);
    float edgeDistance=max(min(faceDistance.x,faceDistance.y),min(max(faceDistance.x,faceDistance.y),faceDistance.z));
    float edge=1.0-smoothstep(0.018,0.075,edgeDistance);
    float active=step(0.945,rnd);
    float pulse=0.65+0.35*beat;
    color+=lerp(tint,float3(1.0,0.45,0.095),reform)*edge*active*(0.26+0.44*reform)*pulse;
    if(input.material.y>0.5)
    {
        // Dust is a separate small, solid population, with selected hot flecks.
        color=float3(0.008,0.012,0.018)*(0.30+diffuse*keyAttenuation);
        color+=lerp(float3(0.30,0.45,0.66),float3(1.0,0.65,0.25),reform)*step(0.965,rnd)*0.90;
        color+=keyColor*spec*keyAttenuation*0.45;
    }
    float fog=1.0-exp(-rayDistance*0.007);
    color=lerp(color,float3(0.002,0.003,0.008),fog*0.30);
    return float4(max(color,0.0),rayDistance);
}
