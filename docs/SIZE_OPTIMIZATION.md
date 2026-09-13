# Executable size optimization

The 1.4.1 source build reduces the Windows x64 executable from **1,689,088 to
164,352 bytes (160.5 KiB)**: **90.3% smaller**, approximately **10.3 times smaller**.
The complete continuous 180-second show, all rendering settings, controls,
capture/benchmark tools and original musical layers remain present.

## Implementation

The native code uses `-Oz`, link-time optimization and symbol stripping, with
`-O2` at the link stage to keep the support libraries optimized for speed.
Checked byte writes and printf formatting replace C++ stream/locale machinery
in exports and diagnostics. Background synthesis uses the Windows CRT thread
API with the same atomic readiness signal and a joined thread at shutdown.
Exceptions and error handling remain enabled.

The official, unmodified [UPX 5.2.1](https://github.com/upx/upx/releases/tag/v5.2.1)
compresses the native code and original compiled shader bytecode together using
LZMA. Its embedded loader restores them in memory at startup; no installation,
extracted executable or external decoder is needed. The shader programs have
not been simplified or recompiled with different HLSL settings. Marching steps,
geometry density, lighting, bloom and rendering resolutions are unchanged.

Relocations and all Windows resources are retained. The executable keeps its
ASLR/high-entropy VA and DEP flags, icon, manifest and version information. The
four icon resolutions use lossless PNG entries inside the ICO: all RGBA pixels
match the original, while the asset shrinks from 32,038 to 7,683 bytes.

The normal build audits DLL imports on the ordinary executable before packing,
then runs UPX's integrity check on the packed result. The ordinary executable is
available at `build/AFTERLIGHT-unpacked.exe`; `build.ps1 -Unpacked` also places that
form in `dist`. The pinned UPX download is verified with SHA-256, just like Zig.

## Measured tradeoffs

| Experiment | Executable size | Decision |
| --- | ---: | --- |
| Original 1.4.0 | 1,689,088 bytes | Baseline |
| Native cleanup + separate lossless shader compression | 295,424 bytes | Working intermediate |
| UPX around separately compressed shaders | 169,472 bytes | Superseded |
| Shared code/shader compression, all code optimized for size | 153,600 bytes | Slower frame/readback benchmark; not retained |
| Exhaustive UPX compression search | 153,600 bytes | No additional saving |
| Fast floating-point math | 153,600 bytes | No saving; not retained |
| 32-bit executable variant | 165,376 bytes | Larger; not retained |
| All code optimized for speed | 169,472 bytes | Faster, but larger than the mixed build |
| Size-optimized demo + speed-optimized support libraries | **164,352 bytes** | **Retained** |

Separate Windows LZMS compression reduced 1,058,220 shader bytes to 76,154 bytes,
but letting UPX compress everything together made the complete executable
smaller. That intermediate decoder and its Cabinet.dll dependency were removed.

The smallest 150 KiB build added roughly 2 ms to the frame-render/readback
benchmark. The mixed build restores baseline performance: the mean of 17 sampled
frame-time measurements was 8.34 ms for the original and 8.31 ms for the mixed
build on the Radeon RX 7900 XTX at 1080p. The most expensive sampled passage was
about 17.4 ms in both. Measurements include GPU readback and vary with hardware
and driver state. The extra 10.5 KiB is retained to preserve performance.

Size optimization changes 12,575 of the 15,876,000 synthesized 16-bit PCM samples
by **one integer step at most**. The difference signal is approximately **-121.3
dBFS RMS**, **104.8 dB below the music**. This is accepted as perceptually
negligible; sample rate, duration, stereo channels, arrangement, instruments,
effects and dynamics are retained. There are no new clipped samples.

## Validation

`tools/verify-equivalence.ps1` compares the original and optimized executables:

- 16 captures at 1080p internal quality spanning all five scenes and their
  transitions; menu; 540p and 720p settings; two Windows software-renderer
  captures. All 21 visual files match exactly.
- Full 180-second stereo WAV comparison, permitting a maximum one-step error in
  16-bit PCM and recording the measured signal-to-error ratio.
- End-to-end capture/export timings for both executables, including startup.

The native self-test covers background synthesis, clipping, audio transport,
continuity, deterministic seeking, resolution changes and letterboxing. A
separate directory containing only the executable is used for a standalone
render. The unpacked program's 15 imported DLLs are Windows components; C++
support remains statically linked. Windows 11 supplies the
[Universal CRT](https://learn.microsoft.com/en-us/cpp/windows/universal-crt-deployment).

These are sampled visual comparisons, not a comparison of every frame of the
show. The earlier release's full animation validation remains in
[VALIDATION.md](VALIDATION.md). Reports for this optimization are in
[validation](validation).

```powershell
.\build.ps1 -DownloadToolchain
.\tools\verify-equivalence.ps1 -Baseline C:\path\to\v1.4.0\AFTERLIGHT.exe
.\dist\AFTERLIGHT.exe --self-test
.\verify-imports.ps1 -Executable .\build\AFTERLIGHT-unpacked.exe
```
