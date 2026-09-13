// AFTERLIGHT / FIVE MOVEMENTS — original procedural imagery.
// No imported images, meshes or external resources; GPU caches are procedural.
// Coordinate convention: film-plane units are relative to viewport height.
cbuffer Frame : register(b0)
{
    float2 resolution;
    float time;
    float beat;
};

static const float PI = 3.14159265359;
static const float TAU = 6.28318530718;

float hash11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float hash21(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float hash31(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return frac((p.x + p.y) * p.z);
}

float noise2(float2 p)
{
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(hash21(i), hash21(i + float2(1,0)), f.x),
                lerp(hash21(i + float2(0,1)), hash21(i + 1.0), f.x), f.y);
}

float noise3(float3 p)
{
    float3 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(lerp(hash31(i),hash31(i+float3(1,0,0)),f.x),
             lerp(hash31(i+float3(0,1,0)),hash31(i+float3(1,1,0)),f.x),f.y),
        lerp(lerp(hash31(i+float3(0,0,1)),hash31(i+float3(1,0,1)),f.x),
             lerp(hash31(i+float3(0,1,1)),hash31(i+1),f.x),f.y),f.z);
}

float2 rot(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c*p.x-s*p.y, s*p.x+c*p.y);
}

float fbm(float2 p)
{
    float v = 0, a = 0.5;
    [unroll] for (int i=0; i<5; ++i)
    {
        v += a * noise2(p);
        p = float2(p.x*1.62-p.y*1.21,p.x*1.21+p.y*1.62) + 7.3;
        a *= 0.5;
    }
    return v;
}

float fbm3(float3 p)
{
    float v = 0, a = 0.5;
    [unroll] for (int i=0; i<4; ++i)
    {
        v += a * noise3(p);
        p = p.yzx * 2.03 + float3(3.1,7.2,1.4);
        a *= 0.5;
    }
    return v;
}

float3 cameraRay(float2 p, float3 eye, float3 target, float focal)
{
    float3 fw = normalize(target-eye);
    float3 rt = normalize(cross(float3(0,1,0),fw));
    float3 up = cross(fw,rt);
    return normalize(rt*p.x + up*p.y + fw*focal);
}

float2 sphereHit(float3 ro, float3 rd, float3 center, float radius)
{
    float3 oc = ro-center;
    float b = dot(oc,rd), h = b*b-dot(oc,oc)+radius*radius;
    if (h<0) return float2(-1,-1);
    h=sqrt(h);
    return float2(-b-h,-b+h);
}

float starLayer(float2 p, float scale, float density)
{
    p *= scale;
    float2 cell = floor(p), f=frac(p)-0.5;
    float h=hash21(cell);
    float2 center=float2(hash21(cell+14.7),hash21(cell-9.1))-0.5;
    float2 d=f-center*0.78;
    float radius=0.010 + 0.022*hash21(cell+7.4);
    float star=exp(-dot(d,d)/(radius*radius));
    // Cross diffraction only on uncommon bright stars.
    star+=step(0.995,h)*0.07*(exp(-abs(d.x)*350-abs(d.y)*13)+exp(-abs(d.y)*350-abs(d.x)*13));
    return star * step(density,h) * (0.25+1.75*hash21(cell+4.0));
}

float3 space(float3 rd, float clock, float nebulaAmount)
{
    float2 p=rd.xy / (abs(rd.z)+0.72);
    p=rot(p,0.34);
    float2 wp=p*3.5 + float2(0.013*clock,0.006*clock);
    float2 warp=float2(fbm(wp+17.0),fbm(wp-19.0));
    float n=fbm(wp*2.3 + warp*2.8);
    float dust=fbm(wp*5.7 + warp*5.0);
    float lane=exp(-pow((p.y + 0.22*sin(p.x*2.2)+0.05)*2.5,2));
    float cloud=pow(saturate(n*1.65-0.29),2.8)*lane;
    float3 col=float3(0.0015,0.0020,0.0070);
    col+=nebulaAmount*cloud*lerp(float3(0.075,0.017,0.115),float3(0.005,0.145,0.195),saturate(dust*1.5));
    col+=nebulaAmount*pow(saturate(n*1.35-0.50),3.0)*float3(0.17,0.067,0.023)*lane;
    col*=1.0-0.74*pow(saturate(dust*1.5-0.23),3.0)*lane;
    float s1=starLayer(p,110.0,0.84), s2=starLayer(p+17.4,53.0,0.92);
    col+=s1*float3(0.62,0.76,1.0)+s2*float3(1.0,0.74,0.45);
    col+=starLayer(p-8.1,220.0,0.965)*float3(0.28,0.37,0.58);
    return col;
}

float3 sunFlare(float2 p, float2 source, float strength)
{
    float2 d=p-source;
    float r=length(d);
    float halo=0.007/(r*r+0.007);
    float core=0.000025/(r*r+0.000015);
    float streak=exp(-abs(d.y)*350.0)/(1.0+d.x*d.x*3.0);
    float3 c=(halo*float3(0.45,0.14,0.035)+core*float3(1.0,0.86,0.53)+streak*float3(0.12,0.055,0.016))*strength;
    float2 axis=normalize(source+0.0001);
    [unroll] for (int i=0;i<3;++i)
    {
        float2 ghost=p+source*(0.30+float(i)*0.40);
        float ring=exp(-pow((length(ghost)-(0.045+0.015*float(i)))*90.0,2.0));
        c+=ring*float3(0.012,0.027,0.019)*strength;
    }
    return c;
}
