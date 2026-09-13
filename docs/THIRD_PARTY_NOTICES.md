# Third-party notices

CC0 applies to AFTERLIGHT's original project content. It does not replace the licenses of third-party development tools or runtime components.

The Windows executable is built using Zig 0.13.0 and statically links the C++ and Windows GNU runtime components selected by that toolchain. Upstream notices supplied with this toolchain are preserved here:

- [libc++](licenses/libcxx.txt): Apache License 2.0 with LLVM exceptions and historical notices.
- [libc++abi](licenses/libcxxabi.txt): Apache License 2.0 with LLVM exceptions and historical notices.
- [LLVM unwinding runtime](licenses/libunwind.txt): Apache License 2.0 with LLVM exceptions and historical notices.
- [mingw-w64](licenses/mingw-w64.txt): upstream Windows runtime notice.
- [Zig](licenses/zig.txt): compiler and Zig runtime notice.

The downloaded Zig and FFmpeg development tool distributions are not checked into this repository or included in its Windows release package. FFmpeg and Node.js are optional tools for producing and checking preview videos; neither is a runtime dependency of AFTERLIGHT. Windows graphics, audio and system DLLs are supplied by Windows, not redistributed here.

The research links in [RESEARCH.md](RESEARCH.md) acknowledge technical inspiration. No assets or rendering engine from those demos are bundled.
