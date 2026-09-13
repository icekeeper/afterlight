# AFTERLIGHT — visual research and implementation

The research focused on creators' technical accounts of influential demos and intros. The goal was to turn useful methods into visible changes in AFTERLIGHT's existing space journey. All scene code, choreography, materials and generated content in this iteration are original; no demo assets or third-party rendering engine are bundled.

## Research → implementation

### Changing recursive architecture

Mercury describes **hg_sdf**, developed for **The Timeless** and **On**, as a system of distance bounds, space repetition and geometric combination operators. Its central lesson is that a small vocabulary of carefully composed operations can create intricate architecture. [Mercury's documentation](https://mercury.sexy/hg_sdf/)

Syntopia's **Folding Space II** explains how conditional plane reflections and scaling produce recursive solids, and how rotations within the folding process change their structure. This is a technical reference rather than a claim about Mercury's implementation. [Creator article](https://blog.hvidtfeldts.net/index.php/2010/06/01/)

**In AFTERLIGHT:** the orbital machine now has three recursive structural scales with changing internal rotations. Three designed poses unfold over musical phrases, with smaller levels following after a short delay. Nested bevelled frames, bronze ribs and luminous recessed channels follow the changing coordinates. Large intersecting galleries expose the central chamber. The silhouette and chambers transform while the orbital machinery keeps a recognizable frame of reference. See `scene_machine.hlsl`.

### Architecture becoming particles

In **Agenda Circling Forth**, Smash describes particles retaining correspondence with their source objects, blending between animated targets and freer motion. His particle-system article discusses GPU processing, coherent curl-driven movement, lighting and shadows. Together they explain why particles can form a moving object or volume rather than merely decorate a scene. [Agenda making-of](https://directtovideo.wordpress.com/2010/04/19/agenda-circling-forth/) · [Particle system](https://directtovideo.wordpress.com/2009/10/06/a-thoroughly-modern-particle-system/)

**In AFTERLIGHT:** a dedicated instanced GPU pass constructs up to 24,576 solid fragments and dust cuboids directly from vertex and instance IDs. Stable identities and absolute-time choreography connect architectural positions with released formations. The corridor's ray-marched distance buffer hides fragments behind its structure, and hardware depth resolves fragments against one another. A separate pass reconstructs visible surface positions and normals to add screen-space contact shading, inspired by Frameranger's emphasis on ambient occlusion. The implementation uses deterministic procedural flow and target blending; it is not an SPH or Navier–Stokes simulation. See `scene_transit.hlsl`, `scene_particles.hlsl`, `scene_resolve.hlsl` and `main.cpp`.

### Light and flow at different resolutions

Smash's **Media Error** account accumulates density along a light direction to cache smoke shadows. **Frameranger** separates coarse motion from finer visible density and adds procedural detail. These methods spend expensive work on coherent large-scale behavior while retaining fine visual structure. [Smoke renderer](https://directtovideo.wordpress.com/2009/09/29/fluid-dynamics-1-introduction-and-the-smokebox/) · [Frameranger making-of](https://directtovideo.wordpress.com/2009/09/30/frameranger/)

Ctrl-Alt-Test's **H–Immersion** combines volumetric scattering with a Henyey–Greenstein phase function, occlusion and colored absorption along light and view paths. [Creator making-of](https://www.ctrl-alt-test.fr/2018/a-dive-into-the-making-of-immersion/)

**In AFTERLIGHT:** startup generates a 64³ field containing full-path optical depth from the protostar and a curl flow field. An 8×8 atlas of slices provides trilinear sampling using Direct3D feature level 10. The view ray evaluates animated fine density separately, with colored extinction and angular scattering. Extending the directional shadow-cache idea to a central point light is our adaptation. The static cache represents the large cloud structure; small moving wisps do not regenerate its shadows. See `scene_volume_cache.hlsl` and `scene_rebirth.hlsl`.

## Other findings that informed selection

The authors of **One Of Those Days** document camera choreography and an 8×8 tile prepass that narrows ray starts and visibility masks. Its camera discussion informed the transit work; AFTERLIGHT does not implement their tile prepass. [Authors' release notes](https://www.pouet.net/prod_nfo.php?which=75790)

IQ's indexed **Behind Elevated** slides describe derivative-attenuated terrain octaves and camera-path controls. A close terrain passage was considered, but the implemented scope concentrates on the three transformations above. Full PDF retrieval was blocked, so no unseen slide details are claimed. [Creator slides](https://iquilezles.org/articles/function2009/function2009.pdf)

## Fourth iteration: a continuous journey

The next iteration applies those techniques to transitions as well as individual scenes. The five environments retain their procedural detail and musical timing, but their connections are now part of the rendered space:

- The planet and machine use the same world rays and depth ordering. The camera leaves the planetary composition and approaches the orbiting structure.
- A carved gallery contains a portal plane. Its rays map into the corridor, with the same camera position, forward direction, roll and lens at the crossing. Machine geometry and light in front of the portal occlude its view.
- The corridor has an actual entrance and exit. Its architectural fragments retain their identities as they form a braid and fall toward the black hole already visible beyond the exit.
- The black hole and nursery share a volume integral. An expanding three-dimensional front changes local gas extinction and emission, while the horizon contracts and the central star ignites. The nursery continues to use its procedurally generated shadow and flow cache.

`scene_journey.hlsl` shares the camera choreography between the ray-marched environments, rasterized fragments and contact shading. Quintic camera blends preserve position, velocity and acceleration at their endpoints. The show no longer interpolates completed scene images or presents chapter cards. Opening and closing exposure ramps remain.

## Distribution

The soundtrack and 180-second timeline are retained. Compiled shaders and generation code are embedded in a single native Windows 11 x64 executable. Cached fields are generated on the user's GPU; there are no downloaded textures, meshes, recordings or installation dependencies.
