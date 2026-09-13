#pragma once

#include <cstdint>
#include <vector>

namespace Afterlight {

inline constexpr double Duration = 180.0;
inline constexpr int SampleRate = 44100;

// An original 120 BPM score. Returns mastered, stereo-interleaved PCM16.
// The entire synthesizer is deterministic and requires no audio assets or DLLs.
std::vector<int16_t> GenerateSoundtrack();

} // namespace Afterlight
