// THE QUIET BEFORE / a close passage through the rings of a weather world.
// All radiance is linear HDR. The host owns bloom and the display transform.

float2 p2Vortex(float2 uv, float2 center, float radius, float winding)
{
    float2 q=uv-center;
    q.x=atan2(sin(q.x),cos(q.x));
    q.x*=0.78;
    float turn=winding*exp(-dot(q,q)/(radius*radius));
    float2 wound=rot(q,turn);
    return uv+float2((wound.x-q.x)/0.78,wound.y-q.y);
}

float3 p2Weather(float3 normal,float clock)
{
    normal.xz=rot(normal.xz,clock*0.011);
    float2 uv=float2(atan2(normal.z,normal.x),asin(clamp(normal.y,-0.9999,0.9999)));
    float2 original=uv;
    uv.x+=0.045*sin(uv.y*21.0+clock*0.022);
    uv=p2Vortex(uv,float2(-1.15,0.28),0.38,5.8);
    uv=p2Vortex(uv,float2(-2.12,-0.38),0.25,-5.2);
    uv=p2Vortex(uv,float2(-0.57,-0.56),0.21,4.5);
    uv=p2Vortex(uv,float2(-2.62,0.74),0.19,-4.3);
    float2 drift=float2(fbm(uv*float2(4,10)+13.4),fbm(uv*float2(6,7)-8.7));
    float flow=fbm(uv*float2(9.0,25.0)+drift*3.2);
    float stripe=0.5+0.5*sin(uv.y*40.0+flow*6.0+sin(uv.x*4.0)*0.6);
    float fine=fbm(uv*float2(24.0,65.0)+drift*5.5);
    float wisps=fbm(uv*float2(69.0,135.0)+float2(flow*7.0,fine*4.0));
    float3 deep=float3(0.022,0.067,0.100);
    float3 teal=float3(0.045,0.31,0.34);
    float3 cloud=float3(0.52,0.60,0.57);
    float3 albedo=lerp(deep,teal,smoothstep(0.22,0.71,stripe*0.6+flow*0.55));
    albedo=lerp(albedo,cloud,smoothstep(0.46,0.77,fine+stripe*0.2));
    float curled=pow(saturate(1.0-abs(wisps*2.0-1.0)),7.0);
    albedo*=0.69+0.59*wisps;
    albedo+=curled*float3(0.035,0.079,0.079);
    float d=length((original-float2(-1.15,0.28))*float2(0.78,1.0));
    float redStorm=(1.0-smoothstep(0.11,0.31,d))*smoothstep(0.33,0.73,flow+stripe*0.22);
    albedo=lerp(albedo,float3(0.62,0.23,0.115)*(0.6+fine),redStorm*0.87);
    albedo=lerp(albedo,float3(0.43,0.38,0.24),smoothstep(0.85,1.05,stripe+fine*0.22)*0.45);
    return albedo;
}

float p2Crater(float3 samplePosition)
{
    float3 cell=floor(samplePosition),local=frac(samplePosition);
    float result=0;
    [unroll] for(int z=-1;z<=1;z++)
    [unroll] for(int y=-1;y<=1;y++)
    [unroll] for(int x=-1;x<=1;x++)
    {
        float3 offset=float3(x,y,z);
        float3 id=cell+offset;
        float h=hash31(id);
        float3 center=offset+float3(hash31(id+4.3),hash31(id+13.7),hash31(id-3.1));
        float r=0.16+0.19*h;
        float d=length(local-center);
        result+=exp(-pow((d-r)*29.0,2.0))*0.22-exp(-d*d/(r*r*0.6))*0.24;
    }
    return result;
}

float3 p2Atmosphere(float3 col,float3 eye,float3 ray,float3 center,float radius,float endDistance,float3 light)
{
    float2 boundary=sphereHit(eye,ray,center,radius+0.105);
    if(boundary.y<=0)return col;
    float start=max(0,boundary.x),finish=min(boundary.y,endDistance);
    if(finish<=start)return col;
    float stepSize=(finish-start)/12.0;
    float transmittance=1.0;
    float3 scattering=0;
    float mu=dot(ray,light);
    float rayleigh=0.65+0.35*mu*mu;
    float mie=0.06/pow(max(0.15,1.0+0.72*0.72-1.44*mu),1.5);
    [unroll] for(int i=0;i<12;i++)
    {
        float3 q=eye+ray*(start+(float(i)+0.5)*stepSize)-center;
        float r=length(q),altitude=max(0,r-radius);
        float density=exp(-altitude/0.020)*stepSize*3.6;
        float sunHeight=dot(q,light);
        float sunImpact=length(q-light*min(sunHeight,0.0));
        float sunVisible=smoothstep(radius-0.012,radius+0.035,sunImpact);
        float3 tint=float3(0.070,0.26,0.54)*rayleigh+float3(0.76,0.35,0.12)*mie;
        scattering+=transmittance*(1.0-exp(-density))*tint*(0.025+sunVisible*0.92);
        transmittance*=exp(-density*0.85);
    }
    return col*transmittance+scattering;
}

// World-space renderer shared by the planet approach and orbital machinery.
// A single ray now sees both objects, so every ring and moon retains parallax
// while the camera travels towards the much smaller structure in orbit.
float3 p4Render(float3 eye,float3 ray,float t,out float opaqueDistance)
{
    float3 center=float3(1.94,-0.32,0.8);
    float3 light=normalize(float3(-0.95,0.30,-0.11));
    float3 col=space(ray,t*0.25,0.52);
    float radius=2.16;
    float2 planetHit=sphereHit(eye,ray,center,radius);
    float nearest=planetHit.x>0?planetHit.x:1000.0;
    float3 ringNormal=normalize(float3(0.17,0.93,-0.325));
    float3 ringU=normalize(cross(float3(0,0,1),ringNormal));
    float3 ringV=cross(ringNormal,ringU);

    if(planetHit.x>0)
    {
        float3 surface=eye+ray*planetHit.x;
        float3 normal=normalize(surface-center);
        float3 albedo=p2Weather(normal,t);
        float nl=dot(normal,light);
        float diffuse=max(0,nl);
        float planeDistance=-dot(surface-center,ringNormal)/dot(light,ringNormal);
        float shadowRadius=length(surface+planeDistance*light-center);
        float shadowBand=smoothstep(2.58,2.68,shadowRadius)*(1-smoothstep(4.55,4.72,shadowRadius));
        shadowBand*=1.0-0.72*exp(-pow((shadowRadius-3.58)*19.0,2.0));
        shadowBand*=0.62+0.28*noise2(float2(shadowRadius*94.0,3.1));
        diffuse*=1.0-shadowBand*step(0,planeDistance)*0.83;
        float sunset=exp(-nl*nl*36.0);
        col=albedo*(float3(0.003,0.008,0.019)+diffuse*float3(1.67,1.30,0.94));
        col+=albedo*sunset*float3(0.033,0.012,0.005);
        float horizon=pow(1.0-saturate(dot(normal,-ray)),4.0);
        col+=horizon*smoothstep(-0.16,0.19,nl)*float3(0.026,0.12,0.20);
    }

    col=p2Atmosphere(col,eye,ray,center,radius,nearest,light);
    // True ring-plane intersections: radial strata, azimuthal fractures and icy grains.
    float denom=dot(ray,ringNormal);
    float ringDistance=dot(center-eye,ringNormal)/(abs(denom)>0.0001?denom:0.0001);
    if(ringDistance>0 && ringDistance<nearest)
    {
        float3 q=eye+ray*ringDistance-center;
        float2 rp=float2(dot(q,ringU),dot(q,ringV));
        float r=length(rp),angle=atan2(rp.y,rp.x);
        float ringMask=smoothstep(2.56,2.63,r)*(1-smoothstep(4.53,4.76,r));
        if(ringMask>0)
        {
            float stripe=noise2(float2(r*112.0,0.72));
            float thin=0.5+0.5*sin(r*510.0+noise2(float2(r*37.0,0))*4.0);
            float strata=0.36+0.64*noise2(float2(r*21.0,4.7));
            float cuts=1.0-0.95*exp(-pow((r-3.58)*28.0,2.0));
            cuts*=1.0-0.70*exp(-pow((r-2.94)*49.0,2.0));
            cuts*=1.0-0.70*exp(-pow((r-4.19)*44.0,2.0));
            float spokes=0.55+0.45*noise2(float2(angle*42.0+r*1.4,r*7.0));
            float grain=noise2(rp*160.0);
            float debris=pow(saturate(grain*1.65-0.39),3.0);
            float optical=ringMask*(0.25+stripe*0.62+thin*0.12)*strata*cuts*spokes;
            float alpha=1.0-exp(-optical/(0.24+abs(denom))*1.15);
            float shadowAlong=-dot(q,light);
            float shadowImpact=length(q+light*shadowAlong);
            float shadow=shadowAlong>0?smoothstep(radius-0.10,radius+0.15,shadowImpact):1.0;
            float3 ringColor=lerp(float3(0.15,0.20,0.23),float3(0.62,0.47,0.28),stripe);
            ringColor*=0.075+shadow*(0.52+debris*0.8);
            ringColor+=shadow*pow(debris,4.0)*float3(1.0,1.18,1.4)*0.7;
            ringColor+=float3(0.35,0.18,0.06)*pow(saturate(dot(ray,light)),9.0)*shadow;
            col=lerp(col,ringColor,alpha);
        }
    }
    // A handful of nearby fragments give the ring passage genuine depth parallax.
    [loop] for(int rock=0;rock<24;rock++)
    {
        float seed=float(rock)*13.73+8.2;
        float angle=hash11(seed)*TAU+t*0.0027;
        float ringR=2.9+hash11(seed+4.0)*1.84;
        float3 rockCenter=center+(cos(angle)*ringU+sin(angle)*ringV)*ringR;
        rockCenter+=ringNormal*(hash11(seed-7.0)-0.5)*0.19;
        float rockR=0.027+pow(hash11(seed+15.0),4.0)*0.15;
        float2 rh=sphereHit(eye,ray,rockCenter,rockR);
        if(rh.x>0 && rh.x<nearest)
        {
            float3 n=normalize(eye+ray*rh.x-rockCenter);
            float3 rn=n;rn.xy=rot(rn.xy,seed+t*0.04);rn.yz=rot(rn.yz,seed*0.5);
            float rough=noise3(rn*8.0+seed);
            float3 facet=normalize(n+float3(noise3(rn*13+2),noise3(rn*13+7),noise3(rn*13+12))*0.37-0.18);
            float diffuse=saturate(dot(facet,light));
            col=lerp(float3(0.047,0.055,0.068),float3(0.29,0.24,0.17),rough)*(0.07+diffuse*1.7);
            col+=pow(saturate(dot(reflect(-light,facet),-ray)),20.0)*float3(0.12,0.19,0.25);
            nearest=rh.x;
        }
    }

    float3 moonCenter=float3(-2.75,2.02,2.8);
    float2 mh=sphereHit(eye,ray,moonCenter,0.48);
    if(mh.x>0 && mh.x<nearest)
    {
        float3 normal=normalize(eye+ray*mh.x-moonCenter);
        float3 q=normal;q.xz=rot(q.xz,t*0.004);
        float crater=p2Crater(q*10.0);
        float terrain=fbm3(q*15.0);
        float3 n=normalize(normal+float3(noise3(q*31+1),noise3(q*31+7),noise3(q*31+13))*0.16-0.08);
        col=lerp(float3(0.105,0.13,0.16),float3(0.38,0.35,0.29),terrain)*(0.035+saturate(dot(n,light))*1.3);
        col*=0.75+crater*1.9+terrain*0.35;
        nearest=mh.x;
    }
    // The distant flare is registered in the sky, rather than following a
    // screen coordinate while the ship turns towards the orbital engine.
    if(nearest>999.0)
    {
        float3 sunDirection=normalize(float3(-0.45,0.18,1.0));
        float alignment=saturate(dot(ray,sunDirection));
        float angleSquared=max(0.0,2.0-2.0*alignment);
        col+=float3(1.4,0.73,0.31)*(exp(-angleSquared*12000.0)*7.0+
             0.0018/(angleSquared+0.0017)+exp(-angleSquared*23.0)*0.016);
    }
    opaqueDistance=nearest;
    return max(col,0);
}
