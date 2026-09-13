# AFTERLIGHT IV — validation

Validated on 13 September 2026.

## Release

- Native Windows x64 GUI executable, version 1.4.0; 1.689.088 bytes.
- SHA-256: `0CDC52D2326C0240DA9BABC04E653AE094A5C29F3BFB5A8872CBB4611BD1A8C4`.
- All 17 imported DLLs are Windows components. C++ runtime, shaders, icon and soundtrack synthesis are embedded.
- The final executable rendered successfully from a directory containing only that executable. No texture, mesh, music or runtime files were present beside it.
- The Windows software renderer also rendered the final expanding-front/nursery passage successfully.

## Continuity and motion

The driver no longer crossfades scene images. Planet and machine share world rays; a geometric portal connects the machine gallery to the corridor; the corridor ends in the black hole's space; an expanding volume front transforms accretion gas into the nursery.

Paired native renders at each boundary use times 0.0001 seconds before and after it. The intentional kick-light attack is held constant for these comparisons. Mean absolute differences are measured per RGB channel on the final eight-bit output:

| Boundary | Mean difference / 255 |
| --- | ---: |
| Gallery crossing, 66 s | 0.454 |
| Fragment pass begins, 72 s | 0.346 |
| Corridor renderer completes, 118 s | 0.245 |
| Fragment pass ends, 120 s | 0.248 |
| Settled nursery specialization, 150 s | 0.242 |

All pass the 1/255 limit. The check detects view and radiance cuts; it does not replace motion review. Sampled adjacent frames were also inspected around the docking turn, gallery crossing, fragment close passes, absorption, and expanding front. A camera-roll surge found during that review was corrected using parallel transport and an explicitly controlled roll angle.

The complete preview contains 10,800 frames: an uninterrupted 180 seconds at 60 fps, with the original stereo score. It was captured at 1080p internal render quality and encoded at 960×540 using H.264 and 44.1 kHz AAC. The full encoded video was decoded to check for errors. Exposure checks cover the 10,260 frames between the intentional opening and closing ramps; no blank or nearly white frame was found in that interval.

## Native checks

The built-in self-test passes scene rendering across the route, deterministic seeking, 540p/1080p resolution changes, letterboxed resize, soundtrack length, clipping checks, and waveOut pause/resume/seek timing. Returning to the fragment scene after visiting the nursery produces an identical frame.

The unchanged score contains 15,876,000 interleaved samples at 44.1 kHz stereo: 180 seconds, peak 0.94397, RMS 0.149041, zero clipped samples. `soundtrack.cpp` retains SHA-256 `01B60E4646CA65E6C6D56296AE30A17C5066EB360CEAB74CCB7B162A64B61DE4`.

## Performance

Warm measurements on the AMD Radeon RX 7900 XTX at 1920×1080, including frame readback, average 2.84–17.58 ms across the sampled locations. The gallery averages 7.13 ms, fragment infall 5.45 ms, and settled nursery 12.80–13.99 ms. The expanding front at 145.5–149 s is the most expensive passage, averaging approximately 17.5–17.6 ms. These measurements exclude startup preparation and vary with hardware and driver state. The in-demo 720p and 540p settings remain available.

Detailed native and animation reports are preserved in [validation](validation). Running diagnostics from the source workspace writes fresh reports into the ignored `build` directory.
