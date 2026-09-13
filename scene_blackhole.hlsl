// Advected turbulent accretion flow, seen along gravitationally bent rays.
float b2Flow(float3 p,float local)
{
    float rad=length(p.xz);
    p.xz=rot(p.xz,-local*.54/pow(max(rad,.9),1.5));
    float3 w=p*2.8;
    w+=float3(noise3(w+8.3),noise3(w+16.1),noise3(w+43.8))*1.5;
    float v=0,amp=.56;
    [unroll]for(int j=0;j<5;j++) {
        v+=amp*(1-abs(noise3(w)*2-1));
        w=w.zxy*2.13+float3(7.1,17.3,2.8);amp*=.48;
    }
    return v;
}
// A world-space ionization front consumes the accretion flow from the inside.
// Outside its narrow support band no procedural noise is necessary.
float b4Conversion(float3 pos,float t,float frontRadius,out float shock)
{
    float radius=length(pos),conversion=0;
    shock=0;
    [branch] if(t>=150.0) conversion=1.0;
    else if(t>136.0)
    {
        [branch] if(radius<frontRadius-.5) conversion=1.0;
        else if(radius<frontRadius+.5)
        {
            float grain=noise3(pos*3.1+float3(0,t*.035,0));
            float corrugation=(grain-.5)*.16+sin(pos.y*4.7+pos.z*2.4+t*.8)*.04;
            float signedFront=radius-frontRadius+corrugation;
            float width=.10+frontRadius*.012;
            conversion=1.0-smoothstep(-width,width,signedFront);
            float shellDistance=signedFront/(.04+frontRadius*.006);
            // Fractured ionization filaments leave the forming clouds visible.
            // An inverse-area falloff prevents a large shell washing out
            // the whole frame as its angular area grows around the observer.
            float fine=noise3(pos*10.8+grain*2.0);
            float filament=pow(saturate(1.0-abs(fine*2.0-1.0)),7.0);
            float structure=(.08+.92*filament)*(.20+.80*smoothstep(.30,.65,grain));
            shock=exp(-shellDistance*shellDistance)*structure/(1.0+frontRadius*frontRadius*.22);
            shock*=smoothstep(136.,138.,t)*(1.0-smoothstep(148.,150.,t));
        }
    }
    return conversion;
}

// BH-local origin is the future star. The nursery uses q = n2Star + pos.
// One ray, one accumulated radiance/transmittance, and one locally changing
// medium: gravity and the horizon recede while the outgoing front changes gas.
float3 b4Render(float3 eyeB,float3 ray,float t,out float opaqueDistanceB)
{
    opaqueDistanceB=65000.0;
    float3 result=0.0;
    // After all material has converted, use its straight-ray specialization.
    // The camera, field, lighting, jitter, and single radiance integral agree.
    [branch] if(t>=150.0)
    {
        result=n2RenderRay(eyeB+n2Star,ray,t);
    }
    else
    {
    // Negative phases are valid: the distant accretion flow is already moving.
    float local=t-108.0;
    float nurseryLocal=max(0,t-144.0),growth=smoothstep(0.,26.,nurseryLocal);
    float frontRadius=9.8*smoothstep(136.,150.,t);
    float gravity=1.04*(1.0-smoothstep(136.,145.,t));
    float horizon=.70*(1.0-smoothstep(136.,142.,t));
    float ignition=smoothstep(139.,144.,t);
    float settled=smoothstep(139.,145.,t);
    float boundsBlend=smoothstep(136.,145.,t);
    float3 nurseryCenter=float3(0,-.55,2.1)-n2Star;
    float3 boundsCenter=nurseryCenter*boundsBlend;
    float boundsRadius=lerp(19.0,6.9,boundsBlend);
    // The front must leave the molecular cloud naturally, without being cut by
    // its smaller bound. Bounds can shrink once this emissive support is gone.
    [branch] if(t>136.0&&t<150.0)
        boundsRadius=max(boundsRadius,frontRadius+.5+length(boundsCenter));
    float2 bounds=sphereHit(eyeB,ray,boundsCenter,boundsRadius);
    float3 transmit=1.0,emission=0.0,starVisibility=1.0,velocity=ray;
    float captured=0;

    [branch] if(bounds.y>0.0)
    {
        // In particular, transit can see the hole from outside radius 19.
        // Start on the analytic entry surface instead of exhausting the march.
        float begin=max(0.0,bounds.x),traveled=begin;
        float3 pos=eyeB+ray*begin;
        float3 nurseryEye=eyeB+n2Star;
        float2 nurseryBounds=sphereHit(nurseryEye,ray,float3(0,-.55,2.1),6.9);
        float nurseryBegin=max(0.0,nurseryBounds.x);
        float nurseryStep=nurseryBounds.y>0.0?(nurseryBounds.y-nurseryBegin)/128.0:.10;
        float nurseryStarDistance=dot(n2Star-nurseryEye,ray);
        int nurseryStepIndex=0;
        float jitter=j4RayJitter;
        [loop]for(int stepIndex=0;stepIndex<320;stepIndex++)
        {
            float rr=length(pos);
            if(horizon>.0001&&rr<horizon)
            {
                captured=1.0;opaqueDistanceB=traveled;break;
            }
            if(gravity<.0001&&traveled>=bounds.y)break;
            if(traveled>begin+.05&&dot(pos-boundsCenter,pos-boundsCenter)>boundsRadius*boundsRadius+.01)break;
            float ds=lerp(clamp(rr*.038,.014,.25),nurseryStep,settled);
            // Outside the cloud and away from the thin front, the straight
            // late-release ray can safely cross empty space in larger strides.
            float outsideCloud=length(pos-nurseryCenter)-6.9;
            [branch] if(gravity<.02&&outsideCloud>.02)
            {
                float outsideFront=max(.01,abs(rr-frontRadius)-.5);
                float emptyDistance=min(outsideCloud,outsideFront);
                // Once rays are straight, both distances are conservative
                // sphere bounds: cross the vacuum in a single safe stride.
                // Bent rays retain shorter steps. Neither density nor the
                // front's emissive band is skipped; the cloud grid still snaps
                // to its exact analytic entry point below.
                float emptyStep=gravity<.0001?emptyDistance*.95:min(.40,emptyDistance*.8);
                ds=max(ds,max(.015,emptyStep));
            }
            float3 previous=pos;
            float sampleDistance=traveled+ds*(.5+jitter);
            float3 mid;
            bool nurseryGrid=false;
            [branch] if(gravity<.0001)
            {
                velocity=ray;
                // Snap the cloud interval to exactly the same 128 sample
                // positions as n2RenderRay, including at the 150-second seam.
                nurseryGrid=nurseryBounds.y>0.0&&traveled>=nurseryBegin-.00001
                    &&traveled<nurseryBounds.y-.00001&&nurseryStepIndex<128;
                [branch] if(nurseryGrid)
                {
                    ds=nurseryStep;
                    sampleDistance=nurseryBegin+(float(nurseryStepIndex)+.5+jitter)*ds;
                    traveled=nurseryBegin+float(nurseryStepIndex+1)*ds;
                    nurseryStepIndex++;
                }
                else
                {
                    ds=min(ds,bounds.y-traveled);
                    if(nurseryBounds.y>0.0&&traveled<nurseryBegin)ds=min(ds,nurseryBegin-traveled);
                    sampleDistance=traveled+ds*(.5+jitter);
                    traveled+=ds;
                }
                pos=eyeB+ray*traveled;
                mid=eyeB+ray*sampleDistance;
            }
            else
            {
                velocity=normalize(velocity-pos*(gravity*ds/max(rr*rr*rr,.0001)));
                pos+=velocity*ds;
                traveled+=ds;
                mid=(previous+pos)*.5+velocity*(jitter*ds*settled);
            }
            float shock;
            float conversion=b4Conversion(mid,t,frontRadius,shock);
            float oldGas=1.0-conversion;
            float discR=length(mid.xz);
            [branch] if(oldGas>.0001&&abs(mid.y)<.55&&discR>1.32&&discR<4.55)
            {
                float crossing=saturate(-previous.y/(pos.y-previous.y+.00001));
                float3 gasPoint=lerp(previous,pos,crossing);
                gasPoint=lerp(mid,gasPoint,smoothstep(.05,.14,abs(pos.y-previous.y)));
                float r=length(gasPoint.xz);
                float theta=atan2(gasPoint.z,gasPoint.x);
                float shear=theta-local*.55/pow(max(r,1.),1.5);
                float turbulence=b2Flow(gasPoint,local);
                float spiral=.5+.5*sin(shear*7.+r*13.5+turbulence*4.8);
                float fibril=pow(saturate(turbulence*1.38-.25),3.);
                float ridges=.5+.5*sin(r*148.+turbulence*15.+shear*6.);
                float radial=smoothstep(1.32,1.58,r)*(1-smoothstep(3.35,4.55,r));
                float height=.028+r*.013;
                float warpHeight=.024*sin(theta*3+r*1.6-local*.21)*(r-1.3);
                float y0=previous.y-warpHeight,y1=pos.y-warpHeight;
                float delta=y1-y0;
                float prim0=sign(y0)*(1-exp(-abs(y0)/height));
                float prim1=sign(y1)*(1-exp(-abs(y1)/height));
                float vertical=abs(delta)>.0001?max(0,height*(prim1-prim0)/delta):exp(-abs(mid.y-warpHeight)/height);
                float density=radial*(.08+1.55*fibril)*(.22+.78*spiral)*(.40+.60*ridges);
                float optical=density*vertical*ds*11.*oldGas;
                float heat=pow(saturate(1-(r-1.3)/3.4),1.7);
                float3 gas=lerp(float3(.80,.028,.009),float3(2.8,.93,.18),heat);
                gas=lerp(gas,float3(3.2,2.3,1.2),smoothstep(.54,.91,heat)*(.35+.65*turbulence));
                float beaming=.52+1.45*pow(saturate(.5+.5*dot(normalize(float3(gasPoint.z,0,-gasPoint.x)),-ray)),2.);
                float hot=pow(saturate(turbulence*1.68-.5),7.)*(1-smoothstep(1.7,4.,r));
                emission+=transmit*(gas*beaming+hot*float3(3,1.1,.25))*optical*.88;
                transmit*=exp(-optical*.92);
            }
            float axial=abs(mid.y),cyl=length(mid.xz);
            [branch] if(oldGas>.0001&&axial>.85&&axial<7.&&cyl<.2+axial*.14)
            {
                float width=.055+axial*.045;
                float theta=atan2(mid.z,mid.x);
                float jet=exp(-cyl*cyl/(width*width))*exp(-axial*.44);
                jet*=smoothstep(.85,1.5,axial)*(.3+.7*pow(.5+.5*sin(axial*14.-local*4.+theta*2.),2.));
                emission+=transmit*jet*ds*oldGas*float3(.09,.3,.62)*.65;
            }
            [branch] if(conversion>.0001&&(nurseryGrid||dot(mid-nurseryCenter,mid-nurseryCenter)<6.9*6.9))
            {
                float3 nurserySample=nurseryGrid?nurseryEye+ray*sampleDistance:n2Star+mid;
                n2IntegrateSample(nurserySample,velocity,nurseryLocal,growth,ds,conversion,transmit,emission);
            }
            [branch] if(shock>.00001)
            {
                float3 ion=lerp(float3(1.7,.34,.07),float3(.16,.67,1.45),smoothstep(138.,145.,t));
                emission+=transmit*shock*ds*ion*1.8;
            }
            if(gravity<.0001?sampleDistance<nurseryStarDistance:dot(mid,velocity)<0.0)starVisibility=transmit;
            if(max(transmit.r,max(transmit.g,transmit.b))<.009)break;
        }
    }
    // One sky field throughout the approach and birth; no changing sky clock.
    float3 color=space(velocity,t*.22,.42)*transmit*(1.0-captured)+emission;
    [branch] if(ignition>0.0)
        color+=n2StellarRadiance(eyeB+n2Star,ray,nurseryLocal,starVisibility,transmit)*ignition*(1.0-captured);
    result=max(color,0);
    }
    return result;
}

float3 blackHoleScene(float2 p,float t)
{
    float3 eye,target;
    float bank,focal;
    j4BlackHoleCamera(t,eye,target,bank,focal);
    float3 ray=cameraRay(rot(p,bank),eye,target,focal);
    float opaqueDistanceB;
    float3 color=b4Render(eye,ray,t,opaqueDistanceB);
    j4OpaqueDistance=min(65000.0,opaqueDistanceB*8.0);
    return color;
}
