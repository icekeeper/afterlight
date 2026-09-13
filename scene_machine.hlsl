// ARCHITECTS OF THE VOID. All geometry, illumination and surface detail is
// evaluated from mathematical distance fields; there are no meshes or images.

float m2Box(float3 p,float3 b)
{
    float3 q=abs(p)-b;
    return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0);
}

float m2RoundBox(float3 p,float3 b,float radius)
{
    return m2Box(p,b)-radius;
}

float m2Ring(float3 p,float radius,float2 thickness)
{
    float2 q=abs(float2(length(p.xy)-radius,p.z))-thickness;
    return length(max(q,0.0))+min(max(q.x,q.y),0.0);
}

float3 m2Sector(float3 p,float count,out float index)
{
    float angle=atan2(p.y,p.x);
    float unit=TAU/count;
    index=floor(angle/unit+0.5);
    p.xy=rot(p.xy,-index*unit);
    return p;
}

float3 m2Frame(float3 p,float t)
{
    p.yz=rot(p.yz,0.20+0.10*sin(t*0.047));
    p.xz=rot(p.xz,-0.23);
    p.xy=rot(p.xy,t*0.026+0.22);
    return p;
}

float3 m2CoreFrame(float3 p,float t)
{
    p.xz=rot(p.xz,t*0.087+0.41);
    p.xy=rot(p.xy,t*0.039+0.47);
    p.yz=rot(p.yz,0.28*sin(t*0.067));
    return p;
}

float3 m4FromCore(float3 p,float t)
{
    // Exact inverse: the flight camera and portal rays share the core's frame.
    p.yz=rot(p.yz,-0.28*sin(t*0.067));
    p.xy=rot(p.xy,-t*0.039-0.47);
    p.xz=rot(p.xz,-t*0.087-0.41);
    return p;
}

float3 m4AxisTurn(float3 p,float3 axis,float angle)
{
    float s=sin(angle),c=cos(angle);
    return p*c+cross(axis,p)*s+axis*dot(axis,p)*(1.0-c);
}

float m4Aperture(float t)
{
    return 0.29+0.035*smoothstep(7.0,15.0,t)+0.13*smoothstep(21.0,29.0,t);
}

// Conceptual references (the implementation and choreography below are original):
// Syntopia, "Folding Space II: Kaleidoscopic Fractals": rotating the domain
// before/after plane folds changes a recursive solid's actual architecture.
// https://blog.hvidtfeldts.net/index.php/category/kaleidoscopic-ifs/
// Mercury's hg_sdf: compose a few primitives; make intersections into designed
// geometric features, and preserve distance bounds through transformations.
// https://mercury.sexy/hg_sdf/

float2 m3CorePose(float t)
{
    // Three held compositions linked by eased, musically placed transformations.
    // The folds move only during these phrases, giving the eye time to read them.
    float first=smoothstep(7.0,15.0,t);
    float second=smoothstep(21.0,29.0,t);
    return float2(first,second);
}

float m3ArchitecturalFrame(float3 p,float extent,float width)
{
    // Twelve bevelled beams. Repeating these at selected fold levels preserves
    // large readable structural ribs above the finest recursive detail.
    float3 q=abs(p);
    float a=m2RoundBox(q-float3(0,extent,extent),float3(extent,width,width),width*0.22);
    float b=m2RoundBox(q-float3(extent,0,extent),float3(width,extent,width),width*0.22);
    float c=m2RoundBox(q-float3(extent,extent,0),float3(width,width,extent),width*0.22);
    return min(a,min(b,c));
}

float3 m3FoldStep(float3 q,float beforeAngle,float afterAngle)
{
    q.xz=rot(q.xz,beforeAngle);
    q=abs(q);
    // Each swap is a reflection at a diagonal plane. Together these fold the
    // domain into an octant wedge without adding a position-dependent warp.
    if(q.x<q.y)q.xy=q.yx;
    if(q.x<q.z)q.xz=q.zx;
    if(q.y<q.z)q.yz=q.zy;
    q.xy=rot(q.xy,afterAngle);
    q=q*3.0-float3(2.0,2.0,2.0);
    q.z=abs(q.z+1.0)-1.0;
    return q;
}

float2 m3CoreAngles(float t)
{
    float2 pose=m3CorePose(t);
    float first=lerp(0.045,0.38,pose.x);
    float second=lerp(-0.025,0.155,pose.x);
    return float2(lerp(first,-0.165,pose.y),lerp(second,0.34,pose.y));
}

float m2Core(float3 p,float t)
{
    float2 pose=m3CorePose(t);
    float objectScale=1.18+0.055*pose.y;
    // Planar facets trim the remote branches without giving the entire object
    // the outline of a solid sphere. Most of the profile belongs to the ribs.
    float bound=max(m2Box(p,float3(1.56,1.56,1.56)),
                    (abs(p.x)+abs(p.y)+abs(p.z)-2.80)*0.57735);
    if(bound>0.20)return bound;
    float3 q=p/objectScale;
    float scale=1.0;
    float structure=100.0;
    [unroll] for(int i=0;i<3;++i)
    {
        float level=float(i);
        // A small phase delay between structural levels makes the form unfold
        // from its large ribs into subsidiary chambers, instead of boiling.
        float2 levelAngles=m3CoreAngles(t-level*0.38);
        q=m3FoldStep(q,levelAngles.x/(1.0+level*0.22),levelAngles.y/(1.0+level*0.14));
        scale*=3.0;
        float width=0.086-0.011*level;
        float frame=m3ArchitecturalFrame(q,0.94,width);
        // A second inset frame forms a recessed channel between two real
        // rows of beams. The gap catches changing internal illumination.
        float inset=m3ArchitecturalFrame(q,0.73,width*0.57);
        structure=min(structure,min(frame,inset)*objectScale/scale);
    }
    // Three large crossing galleries keep the deep passages
    // visible through every pose. Their opening is part of the final unfolding.
    float aperture=0.29+0.035*pose.x+0.13*pose.y;
    float galleryX=m2RoundBox(p,float3(2.35,aperture,aperture),0.065);
    float galleryY=m2RoundBox(p,float3(aperture,2.35,aperture),0.065);
    float galleryZ=m2RoundBox(p,float3(aperture,aperture,2.35),0.065);
    float galleries=min(galleryX,min(galleryY,galleryZ));
    float chamber=length(p)-(0.51+0.10*pose.y);
    return max(max(structure,bound),-min(galleries,chamber));
}

float2 m3CoreSurface(float3 p,float t)
{
    float2 pose=m3CorePose(t);
    float3 q=p/(1.18+0.055*pose.y);
    float seam=0.0, brass=0.0;
    // Only the two largest scales get polished/emissive accents. Tiny geometry
    // stays rough and dark, avoiding a field of glitter during the close pass.
    [unroll] for(int i=0;i<2;++i)
    {
        float level=float(i);
        float2 angles=m3CoreAngles(t-level*0.38);
        q=m3FoldStep(q,angles.x/(1.0+level*0.22),angles.y/(1.0+level*0.14));
        float3 a=abs(q);
        float3 edge=abs(a-0.73);
        float nearestEdge=min(max(edge.x,edge.y),min(max(edge.x,edge.z),max(edge.y,edge.z)));
        float width=0.086-0.011*level;
        float trace=1.0-smoothstep(width*0.56,width*0.80,nearestEdge);
        float bounded=1.0-smoothstep(0.79,0.86,max(a.x,max(a.y,a.z)));
        seam=max(seam,trace*bounded*(0.70+0.15*level));
        float outer=m3ArchitecturalFrame(q,0.94,width);
        brass=max(brass,(1.0-smoothstep(0.012,0.046,abs(outer)))*0.72);
    }
    return float2(seam,brass);
}

float2 m2Union(float2 a,float d,float material)
{
    return d<a.x?float2(d,material):a;
}

float2 m2Map(float3 p,float t)
{
    float3 q=m2Frame(p,t);
    float radius=length(q.xy);
    float2 hit=float2(100.0,1.0);

    // Continuous load-bearing rails, machined with a gap between the ribs.
    float3 rails=q;
    rails.z=abs(rails.z)-0.255;
    float rail=m2Ring(rails,3.415,float2(0.031,0.040))-0.015;
    hit=m2Union(hit,rail,1.0);
    hit=m2Union(hit,m2Ring(rails,3.01,float2(0.027,0.040))-0.010,2.0);
    hit=m2Union(hit,m2Ring(q,2.97,float2(0.045,0.29))-0.010,2.0);

    float index;
    float3 seg=m2Sector(q,48.0,index);
    float3 slab=seg-float3(3.22,0.0,0.0);
    float housing=m2RoundBox(slab,float3(0.22,0.185,0.205),0.018);
    // Recesses are actual holes, not a drawn texture on a solid torus.
    float recess=m2RoundBox(slab-float3(0.075,0.0,0.0),float3(0.18,0.098,0.31),0.014);
    housing=max(housing,-recess);
    hit=m2Union(hit,housing,1.0);
    float3 conductor=seg-float3(3.32,0.0,0.0);
    conductor.z=abs(conductor.z)-0.12;
    hit=m2Union(hit,m2RoundBox(conductor,float3(0.020,0.105,0.017),0.006),3.0);
    float3 bridge=seg-float3(3.06,0.0,0.0);
    hit=m2Union(hit,m2RoundBox(bridge,float3(0.17,0.027,0.14),0.008),2.0);

    // Twelve skyscraper-sized pylons. Their staggered buttresses cast real
    // self shadows across the stator and establish a strong repeated scale.
    float pylonId;
    float3 tower=m2Sector(q,12.0,pylonId);
    float3 shaft=tower-float3(3.52,0.0,0.0);
    float d=m2RoundBox(shaft,float3(0.48,0.115,0.30),0.018);
    hit=m2Union(hit,d,1.0);
    float3 stepped=tower-float3(3.58,0.0,0.0);
    stepped.y=abs(stepped.y)-0.166;
    hit=m2Union(hit,m2RoundBox(stepped,float3(0.33,0.047,0.23),0.012),2.0);
    stepped=tower-float3(3.73,0.0,0.0);
    stepped.z=abs(stepped.z)-0.285;
    hit=m2Union(hit,m2RoundBox(stepped,float3(0.19,0.072,0.060),0.008),2.0);
    float3 crown=tower-float3(4.02,0.0,0.0);
    hit=m2Union(hit,m2RoundBox(crown,float3(0.082,0.072,0.19),0.016),1.0);
    crown=tower-float3(4.11,0.0,0.0);
    hit=m2Union(hit,m2RoundBox(crown,float3(0.018,0.045,0.13),0.007),4.0);
    float3 vent=tower-float3(3.69,0.0,0.0);
    vent.z=abs(vent.z)-0.323;
    hit=m2Union(hit,m2RoundBox(vent,float3(0.20,0.027,0.008),0.004),4.0);

    // Four cathedral spires break the circular silhouette. Open flying
    // buttresses and repeated cross-bracing separate into many layers on flyby.
    float spireId;
    float3 spireBase=m2Sector(q,4.0,spireId);
    float3 spine=spireBase-float3(4.26,0.0,0.0);
    float spire=m2RoundBox(spine,float3(0.88,0.082,0.165),0.015);
    spire=max(spire,abs(spine.y)-0.12+(spine.x+0.88)*0.048);
    hit=m2Union(hit,spire,1.0);
    float3 buttress=spireBase;
    buttress.y=abs(buttress.y)-(0.36-0.17*saturate((buttress.x-3.5)/1.3));
    buttress-=float3(4.08,0.0,0.0);
    hit=m2Union(hit,m2RoundBox(buttress,float3(0.60,0.036,0.31),0.008),2.0);
    float3 crossBrace=spine;
    crossBrace.x=frac(crossBrace.x/0.18+0.5)*0.18-0.09;
    crossBrace.z=abs(crossBrace.z)-0.18;
    float braces=m2Box(crossBrace,float3(0.023,0.22,0.024));
    braces=max(braces,m2Box(spine,float3(0.63,0.27,0.24)));
    hit=m2Union(hit,braces,1.0);
    float3 spireCap=spireBase-float3(5.17,0.0,0.0);
    hit=m2Union(hit,m2RoundBox(spireCap,float3(0.025,0.023,0.10),0.008),3.0);
    float3 spireConduit=spine;
    spireConduit.z=abs(spireConduit.z)-0.18;
    hit=m2Union(hit,m2RoundBox(spireConduit,float3(0.81,0.012,0.008),0.004),4.0);

    // Independent oblique gyroscopic rotor, ribbed in 64 angular segments.
    float3 rotor=p;
    rotor.xz=rot(rotor.xz,0.52+0.12*sin(t*0.049));
    rotor.yz=rot(rotor.yz,-0.52);
    rotor.xy=rot(rotor.xy,-t*0.067);
    float3 doubleRail=rotor;
    doubleRail.z=abs(doubleRail.z)-0.11;
    hit=m2Union(hit,m2Ring(doubleRail,2.46,float2(0.055,0.022))-0.008,2.0);
    float rotorIndex;
    float3 rib=m2Sector(rotor,64.0,rotorIndex)-float3(2.46,0.0,0.0);
    hit=m2Union(hit,m2RoundBox(rib,float3(0.092,0.025,0.14),0.008),1.0);
    float3 rotorLight=rotor;
    rotorLight.z=abs(rotorLight.z)-0.12;
    float lightRing=m2Ring(rotorLight,2.385,float2(0.009,0.012))-0.003;
    hit=m2Union(hit,lightRing,3.0);

    // Articulated iris petals open over sixteen bars. Each has a dark body,
    // bronze edge, luminous capillary and a second, separated armature.
    float openAmount=smoothstep(17.0,29.0,t);
    float3 iris=q;
    iris.xy=rot(iris.xy,-t*0.046);
    float irisId;
    float3 petal=m2Sector(iris,8.0,irisId);
    petal-=float3(2.00+openAmount*0.35,0.0,0.20+openAmount*0.21);
    petal.xz=rot(petal.xz,0.14+openAmount*0.83+0.045*sin(t*0.31));
    float blade=m2RoundBox(petal,float3(0.52,0.14,0.072),0.015);
    blade=max(blade,abs(petal.y)-0.14-petal.x*0.12);
    float bladeCut=m2Box(petal-float3(-0.18,0,0),float3(0.21,0.08,0.14));
    blade=max(blade,-bladeCut);
    hit=m2Union(hit,blade,2.0);
    float3 petalEdge=petal;
    petalEdge.y=abs(petalEdge.y)-0.139;
    hit=m2Union(hit,m2RoundBox(petalEdge,float3(0.49,0.018,0.068),0.006),1.0);
    float3 capillary=petal-float3(0.11,0.0,-0.079);
    hit=m2Union(hit,m2RoundBox(capillary,float3(0.36,0.018,0.006),0.004),3.0);
    float3 finger=petal-float3(0.09,0.0,0.19);
    hit=m2Union(hit,m2RoundBox(finger,float3(0.40,0.029,0.016),0.008),2.0);

    float3 core=m2CoreFrame(p,t);
    hit=m2Union(hit,m2Core(core,t),5.0);
    // The core's axial gallery continues through any crossing armatures. The
    // camera can enter this physical opening without intersecting a moving rail.
    float aperture=m4Aperture(t);
    float access=m2RoundBox(core,float3(aperture,aperture,6.0),0.065);
    hit.x=max(hit.x,-access);
    // A luminous, bevelled doorway surrounds the actual z=0 portal plane.
    // Its centre is empty: the next space is visible through geometry.
    float doorOuter=m2RoundBox(core,float3(aperture+0.10,aperture+0.10,0.028),0.010);
    float doorInner=m2RoundBox(core,float3(aperture+0.025,aperture+0.025,0.20),0.010);
    hit=m2Union(hit,max(doorOuter,-doorInner),6.0);
    return hit;
}

float3 m2Normal(float3 p,float t,float eps)
{
    float2 e=float2(1.0,-1.0)*eps;
    return normalize(e.xyy*m2Map(p+e.xyy,t).x+
                     e.yyx*m2Map(p+e.yyx,t).x+
                     e.yxy*m2Map(p+e.yxy,t).x+
                     e.xxx*m2Map(p+e.xxx,t).x);
}

float m2AO(float3 p,float3 n,float t)
{
    float occlusion=0.0;
    float weight=1.0;
    [unroll] for(int i=0;i<4;++i)
    {
        float h=0.035+float(i)*0.083;
        float d=m2Map(p+n*h,t).x;
        occlusion+=(h-d)*weight;
        weight*=0.55;
    }
    return saturate(1.0-3.1*occlusion);
}

float m2Shadow(float3 p,float3 direction,float t)
{
    float shade=1.0;
    float distance=0.025;
    [loop] for(int i=0;i<16;++i)
    {
        float h=m2Map(p+direction*distance,t).x;
        shade=min(shade,12.0*h/distance);
        distance+=clamp(h,0.03,0.40);
        if(h<0.001 || distance>4.5)break;
    }
    return 0.035+0.965*saturate(shade);
}

float3 m2Environment(float3 direction)
{
    float top=smoothstep(-0.4,0.8,direction.y);
    float3 env=lerp(float3(0.009,0.017,0.034),float3(0.19,0.28,0.34),top);
    env+=float3(1.1,0.63,0.24)*pow(saturate(dot(direction,normalize(float3(-0.8,0.7,-0.6)))),34.0);
    env+=float3(0.07,0.48,0.76)*pow(saturate(dot(direction,normalize(float3(0.8,0.1,0.5)))),18.0);
    float strip=exp(-pow((direction.y+0.17)*23.0,2.0));
    env+=strip*float3(0.14,0.21,0.24);
    return env;
}

float m2Panel(float3 p,float3 n)
{
    float3 an=abs(n);
    float2 uv=an.z>an.x && an.z>an.y?p.xy:(an.x>an.y?p.zy:p.xz);
    float2 cell=uv*float2(11.0,21.0);
    float2 grid=abs(frac(cell)-0.5);
    float seam=smoothstep(0.465,0.494,max(grid.x,grid.y));
    float number=hash21(floor(cell));
    float greeble=step(0.66,number)*step(0.24,grid.x)*step(grid.y,0.35);
    float fine=0.5+0.5*sin(uv.x*220.0+uv.y*4.0);
    return (1.0-0.31*seam-0.21*greeble)*(0.965+fine*0.035)*(0.90+number*0.15);
}

float3 m2Light(float3 n,float3 v,float3 direction,float3 radiance,float3 base,float metal,float rough)
{
    float3 h=normalize(v+direction);
    float nl=saturate(dot(n,direction));
    float nv=max(0.03,saturate(dot(n,v)));
    float nh=saturate(dot(n,h));
    float vh=saturate(dot(v,h));
    float a=max(0.018,rough*rough);
    float a2=a*a;
    float denominator=nh*nh*(a2-1.0)+1.0;
    float distribution=a2/(PI*denominator*denominator+0.0001);
    float k=(rough+1.0)*(rough+1.0)*0.125;
    float geometry=nl/(nl*(1-k)+k)*nv/(nv*(1-k)+k);
    float3 f0=lerp(float3(0.045,0.045,0.045),base,metal);
    float3 fresnel=f0+(1.0-f0)*pow(1.0-vh,5.0);
    float3 specular=distribution*geometry*fresnel/max(0.004,4.0*nl*nv);
    return ((1.0-metal)*base/PI+specular)*radiance*nl;
}

static const float3 m4WorldCenter=float3(-4.6,-0.1,1.8);
static const float m4WorldScale=0.20;

void m4OrbitCamera(float2 p,float t,out float3 worldEye,out float3 worldRay)
{
    float local=t-30.0;
    float orbitAge=max(0.0,local);
    float progress=saturate(orbitAge/36.0);
    float approach=smoothstep(0.0,1.0,progress);
    float angle=-0.71+orbitAge*0.027;
    float flyIn=smoothstep(0.48,1.0,progress);
    float distance=14.8-approach*1.50-flyIn*8.8;
    float3 eye=float3(sin(angle)*distance,2.45-approach*0.75,-cos(angle)*distance);
    float3 target=float3(-0.16+approach*0.25,0.06,0.0);
    float bank=0.06*sin(orbitAge*0.057)-0.025;

    // The engine is already present beside the planet in the opening shot.
    // We translate through this shared space while turning to inspect it.
    float departure=j4Ease(11.0,32.0,t);
    float phase=smoothstep(0.0,30.0,t);
    float3 planetEye=float3(-0.6+phase*0.8,0.10+phase*1.4,-7.5-phase*2.2);
    float3 planetTarget=float3(0.0,0.12,0.8);
    eye=lerp((planetEye-m4WorldCenter)/m4WorldScale,eye,departure);
    target=lerp((planetTarget-m4WorldCenter)/m4WorldScale,target,departure);
    float focal=lerp(1.64,1.38,departure);
    bank*=departure;

    // Follow an arc around the engine into its rotating axial gallery. Spherical
    // interpolation keeps the turn outside the core instead of cutting across it.
    float docking=j4Ease(50.0,62.0,t);
    float3 coreEye=float3(0.0,0.0,(t-66.0)*0.432);
    float3 corridorEye=m4FromCore(coreEye,local);
    float3 firstDirection=normalize(eye);
    float3 lastDirection=m4FromCore(float3(0.0,0.0,-1.0),local);
    float arc=acos(clamp(dot(firstDirection,lastDirection),-0.9999,0.9999));
    float3 direction=(firstDirection*sin((1.0-docking)*arc)+lastDirection*sin(docking*arc))/sin(arc);
    eye=normalize(direction)*lerp(length(eye),length(corridorEye),docking);
    target=lerp(target,float3(0.0,0.0,0.0),docking);
    float3 forward=normalize(target-eye);
    // Parallel-transport the original up guide around the same spherical arc
    // as the eye. Blending two raw up vectors can point almost along the view
    // halfway through docking, causing an otherwise smooth camera to snap-roll.
    float3 arcAxis=cross(firstDirection,lastDirection);
    arcAxis/=max(length(arcAxis),0.00001);
    float3 transported=m4AxisTurn(float3(0,1,0),arcAxis,arc*docking);
    float3 endpointUp=m4AxisTurn(float3(0,1,0),arcAxis,arc);
    endpointUp=normalize(endpointUp-lastDirection*dot(endpointUp,lastDirection));
    float3 coreUp=m4FromCore(float3(0,1,0),local);
    float endpointRoll=atan2(dot(-lastDirection,cross(endpointUp,coreUp)),dot(endpointUp,coreUp));
    // Select a continuous branch of the signed endpoint angle as the moving
    // orbital arc passes the opposite side of the engine. This reference only
    // unwraps atan2; the measured geometric angle still determines the roll.
    float rollGuide=-1.4-(t-50.0)*0.45;
    endpointRoll+=TAU*floor((rollGuide-endpointRoll)/TAU+0.5);
    float3 upGuide=m4AxisTurn(transported,forward,endpointRoll*docking);
    float3 right=normalize(cross(upGuide,forward));
    float3 up=cross(forward,right);
    float2 film=rot(p,bank*(1.0-docking));
    float3 ray=normalize(forward*focal+right*film.x+up*film.y);
    // At and after 62 seconds this is algebraically the exact entry-camera
    // mapping, independent of an almost-zero eye-to-target distance at t=66.
    if(t>=62.0)
    {
        eye=corridorEye;
        ray=m4FromCore(normalize(float3(p,1.38)),local);
    }
    worldEye=m4WorldCenter+eye*m4WorldScale;
    worldRay=ray;
}

float3 m4Render(float3 eye,float3 ray,float t,float3 background,float backgroundDistance,out float opaqueDistance)
{
    float local=t-30.0;
    float3 col=background;
    float3 coreEye=m2CoreFrame(eye,local);
    float3 coreRay=m2CoreFrame(ray,local);
    float portalDistance=65000.0;
    bool portalVisible=false;
    if(coreEye.z<=0.0 && coreRay.z>0.00001)
    {
        float planeDistance=max(0.0,-coreEye.z/coreRay.z);
        float3 portalPoint=coreEye+planeDistance*coreRay;
        float aperture=m4Aperture(local)+0.025;
        float opening=m2RoundBox(float3(portalPoint.xy,0.0),float3(aperture,aperture,0.2),0.010);
        if(opening<0.0 && planeDistance<backgroundDistance)
        {
            portalDistance=planeDistance;
            portalVisible=true;
        }
    }
    float2 bounds=sphereHit(eye,ray,float3(0,0,0),5.35);
    float visibleEnd=min(backgroundDistance,min(bounds.y,portalDistance));
    float travel=max(0.0,bounds.x);
    float material=0.0;
    float3 position=eye;
    float mist=0.0;
    if(visibleEnd>travel)
    {
        [loop] for(int stepIndex=0;stepIndex<128;++stepIndex)
        {
            if(travel>=visibleEnd)break;
            position=eye+ray*travel;
            float2 field=m2Map(position,local);
            float eps=max(0.00085,travel*0.000095);
            if(field.x<eps){material=field.y;break;}
            float advance=min(max(0.0006,field.x*0.79),visibleEnd-travel);
            float radius=length(position);
            mist+=exp(-radius*radius*0.90)*min(advance,0.3)*0.036;
            travel+=advance;
        }
    }
    opaqueDistance=material>0.0?travel:backgroundDistance;
    // Trace the space beyond the door only after foreground visibility is known.
    // Starting at its plane excludes corridor matter on the observer's side.
    if(portalVisible && material==0.0)
    {
        float3 portalPoint=coreEye+portalDistance*coreRay;
        portalPoint.z=0.0;
        float beyondDistance;
        col=tr4Render(j4TransitEntry()+portalPoint*12.5,coreRay,t,beyondDistance);
        opaqueDistance=portalDistance+beyondDistance/12.5;
    }
    float rhythm=exp(-frac(local*2.0)*6.5);
    float barPulse=0.5+0.5*sin(local*PI*0.25-PI*0.5);
    if(material>0.0)
    {
        float3 n=m2Normal(position,local,max(0.0008,travel*0.000085));
        float3 view=-ray;
        float ao=m2AO(position,n,local);
        float3 key=normalize(float3(-0.72,0.82,-0.63));
        float shadow=m2Shadow(position+n*0.004,key,local);
        float3 base=float3(0.10,0.15,0.19);
        float metal=0.80, rough=0.31;
        if(material==2.0){base=float3(0.36,0.20,0.075);rough=0.26;metal=0.86;}
        float2 coreSurface=0.0;
        if(material==5.0)
        {
            coreSurface=m3CoreSurface(m2CoreFrame(position,local),local);
            base=lerp(float3(0.095,0.14,0.175),float3(0.28,0.20,0.105),coreSurface.y);
            rough=lerp(0.53,0.35,coreSurface.y);
            metal=0.74;
        }
        float3 detailPoint=material==5.0?m2CoreFrame(position,local):m2Frame(position,local);
        float3 detailNormal=material==5.0?m2CoreFrame(n,local):m2Frame(n,local);
        float panel=m2Panel(detailPoint,detailNormal);
        base*=panel;
        rough+=0.08*(1.0-panel);
        float3 color=m2Light(n,view,key,float3(3.7,2.85,1.9)*shadow,base,metal,rough);
        color+=m2Light(n,view,normalize(float3(0.9,0.24,0.45)),float3(0.18,0.95,1.95),base,metal,rough);
        color+=m2Light(n,view,normalize(float3(-0.28,-0.85,-0.35)),float3(0.07,0.13,0.26),base,metal,rough);
        float nv=saturate(dot(n,view));
        float3 f0=lerp(float3(0.045,0.045,0.045),base,metal);
        float3 fresnel=f0+(1.0-f0)*pow(1.0-nv,5.0);
        color+=m2Environment(reflect(ray,n))*fresnel*ao*(0.49-rough*0.35);
        color+=base*float3(0.07,0.12,0.16)*ao;

        float3 toCore=normalize(-position);
        float internal=max(0.0,dot(n,toCore))/(0.18+dot(position,position));
        color+=base*internal*float3(0.24,1.0,1.4)*(0.80+rhythm*0.15)*ao;
        color*=0.32+0.68*ao;
        if(material==3.0)
        {
            float signal=0.45+0.55*pow(0.5+0.5*sin(atan2(position.y,position.x)*6.0-local*2.1),4.0);
            color=float3(0.11,1.52,2.35)*signal*(1.0+0.25*rhythm);
        }
        if(material==4.0)color=float3(3.4,1.22,0.21)*(0.65+rhythm*0.35);
        if(material==6.0)color=float3(0.12,2.5,4.0)*(0.90+rhythm*0.15);
        // Emission follows the recursively folded inset channels, and therefore
        // moves with their real geometry throughout the three transformations.
        if(material==5.0)
        {
            color+=coreSurface.x*float3(0.025,0.62,1.05)*(0.52+0.22*barPulse+0.12*rhythm);
        }
        col=color;
    }
    // Integrate only the visible part of the central haze, so nearer blades
    // remain crisp silhouettes against its blue volume.
    col+=mist*float3(0.17,1.50,2.50)*(0.85+rhythm*0.15);
    // Closed-form ray/beam distances keep the very fine ion filaments stable
    // during the final approach; distance-march samples would visibly band.
    float3 beamEye=m2Frame(eye,local), beamRay=m2Frame(ray,local);
    beamEye.xy=rot(beamEye.xy,-local*0.046);
    beamRay.xy=rot(beamRay.xy,-local*0.046);
    float3 relativeEye=beamEye-float3(0.0,0.0,0.20);
    float ionRays=0.0;
    [unroll] for(int beamIndex=0;beamIndex<8;++beamIndex)
    {
        float beamAngle=float(beamIndex)*TAU/8.0;
        float3 axis=float3(cos(beamAngle),sin(beamAngle),0.0);
        float alignment=dot(beamRay,axis);
        float alongRay=dot(beamRay,relativeEye);
        float alongBeam=dot(axis,relativeEye);
        float beamLocation=clamp((alongBeam-alignment*alongRay)/max(0.005,1.0-alignment*alignment),0.45,2.25);
        float3 closestOnBeam=axis*beamLocation+float3(0.0,0.0,0.20);
        float rayLocation=dot(closestOnBeam-beamEye,beamRay);
        float3 separation=beamEye+rayLocation*beamRay-closestOnBeam;
        float beamEnd=min(portalDistance,material>0.0?travel:backgroundDistance);
        float visibleBeam=rayLocation>0.0 && rayLocation<beamEnd?1.0:0.0;
        ionRays+=visibleBeam*exp(-dot(separation,separation)*1050.0)*0.09/sqrt(0.02+1.0-alignment*alignment);
    }
    col+=ionRays*float3(0.03,0.56,0.94)*(0.40+0.60*rhythm);
    return max(col,0.0);
}

float3 orbitScene(float2 p,float t)
{
    float3 worldEye,worldRay;
    m4OrbitCamera(p,t,worldEye,worldRay);
    float planetDistance;
    float3 background=p4Render(worldEye,worldRay,t,planetDistance);
    float machineDistance;
    float3 color=m4Render((worldEye-m4WorldCenter)/m4WorldScale,worldRay,t,
                         background,planetDistance/m4WorldScale,machineDistance);
    j4OpaqueDistance=machineDistance*m4WorldScale;
    transitDepth=j4OpaqueDistance;
    return color;
}
