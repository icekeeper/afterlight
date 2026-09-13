// AFTERLIGHT IV: one camera route through connected procedural spaces.
// All camera handoffs share position, direction, lens and roll. Quintic curves
// preserve velocity and acceleration at the ends of choreography intervals.
#ifndef AFTERLIGHT_JOURNEY
#define AFTERLIGHT_JOURNEY

static float j4OpaqueDistance=65000.0;
static float j4RayJitter=0.0;
static const float j4BlackHoleScale=8.0;

float j4Ease(float a,float b,float t)
{
    float u=saturate((t-a)/(b-a));
    return u*u*u*(u*(u*6.0-15.0)+10.0);
}

float2 j4Path(float z)
{
    return float2(3.0*sin(z*0.027)+1.4*sin(z*0.073),
                  2.5*cos(z*0.035)+0.6*sin(z*0.095));
}

float3 j4BlackHoleOrigin() { return float3(j4Path(300.0),300.0); }
float3 j4TransitEntry() { return float3(j4Path(24.0),24.0); }

float j4FlightZ(float t)
{
    float age=max(0.0,t-66.0);
    return 24.0+3.4*age+0.026*age*age-18.0*smoothstep(27.0,42.0,age);
}

void j4BlackHoleCamera(float t,out float3 eye,out float3 target,out float bank,out float focal)
{
    float age=max(t-108.0,0.0);
    float phase=smoothstep(0.0,36.0,age);
    float yaw=0.24+0.95*phase;
    float altitude=lerp(2.6,0.45,smoothstep(1.0,28.0,age))+0.12*sin(age*0.22);
    float distance=lerp(9.1,7.4,smoothstep(3.0,30.0,age));
    eye=float3(sin(yaw)*distance,altitude,-cos(yaw)*distance);
    target=0.0;
    bank=-0.16+0.13*sin(age*0.067);
    focal=1.05;

    // The same central object becomes the nursery's star. Its cache is queried
    // with this translation, so both the camera and density remain registered.
    float birthAge=max(t-144.0,0.0);
    float orbit=-0.145+0.010*birthAge;
    float3 star=float3(0.05,0.64,1.35);
    float3 nurseryEye=float3(sin(orbit)*9.8,0.23+0.37*sin(birthAge*0.064),-10.9+birthAge*0.093)-star;
    float3 nurseryTarget=float3(0.10+0.25*sin(birthAge*0.046),0.0,1.8)-star;
    float emergence=j4Ease(132.0,150.0,t);
    eye=lerp(eye,nurseryEye,emergence);
    target=lerp(target,nurseryTarget,emergence);
    bank=lerp(bank,0.022*sin(birthAge*0.07),emergence);
    focal=lerp(focal,1.48,emergence);
}

void j4TransitCamera(float t,out float3 eye,out float3 target,out float bank,out float focal)
{
    float age=max(0.0,t-66.0);
    float z=j4FlightZ(t);
    float reveal=smoothstep(96.0,106.0,t);
    float2 sway=float2(sin(age*0.27),0.65*cos(age*0.21))*(1.0-reveal*0.75);
    eye=float3(j4Path(z)+sway,z);
    target=float3(j4Path(z+11.0)-sway*0.35,z+11.0);
    target=lerp(target,float3(j4Path(222.0),222.0),reveal*0.82);
    bank=(0.20*sin(age*0.23)+0.24*sin(age*0.107)-0.12)*(1.0-reveal*0.78);
    focal=1.18-0.18*smoothstep(76.0,91.0,t)+0.22*reveal;

    // This is precisely the machine core portal ray basis at 66 seconds.
    float3 entryEye=j4TransitEntry()+float3(0.0,0.0,(t-66.0)*5.4);
    float entry=j4Ease(66.0,74.0,t);
    eye=lerp(entryEye,eye,entry);
    target=lerp(entryEye+float3(0.0,0.0,8.0),target,entry);
    bank*=entry;
    focal=lerp(1.38,focal,entry);

    float3 holeEye,holeTarget;float holeBank,holeFocal;
    j4BlackHoleCamera(t,holeEye,holeTarget,holeBank,holeFocal);
    float arrival=j4Ease(96.0,118.0,t);
    eye=lerp(eye,j4BlackHoleOrigin()+holeEye*j4BlackHoleScale,arrival);
    target=lerp(target,j4BlackHoleOrigin()+holeTarget*j4BlackHoleScale,arrival);
    bank=lerp(bank,holeBank,arrival);
    focal=lerp(focal,holeFocal,arrival);
}

#endif
