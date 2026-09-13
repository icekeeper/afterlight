#include "soundtrack.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>

namespace Afterlight {
namespace {

// AFTERLIGHT / music for a journey beyond the last star.
// 120 BPM, F-sharp minor; the final chord opens into F-sharp major.
// 00:00 DAWN        : breathing orchestral synthesis and distant glass.
// 00:30 ORBIT       : a clockwork pulse assembles around the listener.
// 01:06 TRANSIT     : sixteenth-note motion, driving drums, the main theme.
// 01:48 SINGULARITY : rhythm collapses into sub pulses and falling fragments.
// 02:24 REBIRTH     : the theme returns with a luminous upper countermelody.
// 02:54 AFTERLIGHT  : the last struck note dissolves into the reverb network.

constexpr float Pi = 3.14159265358979323846f;
constexpr float Tau = 2.0f * Pi;
constexpr double PhaseScale = 4294967296.0;
constexpr std::size_t Frames = static_cast<std::size_t>(Duration * SampleRate);
constexpr int TableBits = 12;
constexpr unsigned TableSize = 1u << TableBits;
constexpr unsigned PhaseBits = 32u - TableBits;
constexpr unsigned PhaseMask = (1u << PhaseBits) - 1u;

float Smooth(float x) {
    x = std::max(0.0f, std::min(1.0f, x));
    return x * x * (3.0f - 2.0f * x);
}

float NoteFrequency(int midi) {
    return 440.0f * std::pow(2.0f, (static_cast<float>(midi) - 69.0f) / 12.0f);
}

uint32_t Step(float frequency) {
    return static_cast<uint32_t>(static_cast<double>(frequency) * PhaseScale / SampleRate);
}

struct Random {
    uint32_t state;
    explicit Random(uint32_t seed = 0x73C4F9B1u) : state(seed ? seed : 1u) {}
    uint32_t Next() {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        return state;
    }
    float Bipolar() { return static_cast<float>(Next() >> 8) * (2.0f / 16777216.0f) - 1.0f; }
};

struct Tables {
    std::array<float, TableSize + 1> sine{};
    std::array<float, TableSize + 1> warm{};
    std::array<float, TableSize + 1> string{};
    Tables() {
        for (unsigned i = 0; i <= TableSize; ++i) {
            const float p = Tau * static_cast<float>(i) / TableSize;
            sine[i] = std::sin(p);
            warm[i] = (std::sin(p) + 0.25f * std::sin(2 * p)
                + 0.12f * std::sin(3 * p) + 0.055f * std::sin(4 * p)
                + 0.025f * std::sin(5 * p)) * 0.72f;
            // A band-limited bowed/saw colour. Highest lead partial remains
            // below Nyquist; no discontinuous waveform is ever sampled.
            float saw = 0.0f;
            for (int h = 1; h <= 12; ++h)
                saw += std::sin(p * h) * (1.0f / h) * (1.0f - h / 14.0f);
            string[i] = saw * 0.64f;
        }
    }
    float Read(const std::array<float, TableSize + 1>& table, uint32_t phase) const {
        const unsigned index = phase >> PhaseBits;
        const float fraction = static_cast<float>(phase & PhaseMask) / (1u << PhaseBits);
        return table[index] + (table[index + 1] - table[index]) * fraction;
    }
    float Sin(uint32_t phase) const { return Read(sine, phase); }
    float Warm(uint32_t phase) const { return Read(warm, phase); }
    float String(uint32_t phase) const { return Read(string, phase); }
};

struct Chord {
    int root;
    std::array<int, 5> notes;
};

const std::array<Chord, 4> Harmony = {{
    {42, {{54, 57, 61, 64, 68}}}, // F#m9
    {38, {{50, 54, 57, 61, 64}}}, // Dmaj9
    {45, {{57, 61, 64, 68, 71}}}, // Amaj9
    {40, {{52, 56, 59, 64, 66}}}  // Eadd9
}};
const std::array<Chord, 4> GravityHarmony = {{
    {42, {{54, 57, 61, 66, 68}}},
    {40, {{52, 54, 59, 62, 66}}},
    {38, {{50, 54, 57, 61, 64}}},
    {37, {{49, 54, 56, 61, 68}}}
}};
const Chord LastChord = {42, {{54, 58, 61, 66, 68}}};

class Composer {
public:
    Tables table;
    std::vector<float> left = std::vector<float>(Frames, 0.0f);
    std::vector<float> right = std::vector<float>(Frames, 0.0f);
    std::vector<float> send = std::vector<float>(Frames, 0.0f);
    Random random;

    static std::size_t At(double seconds) {
        return static_cast<std::size_t>(std::max(0.0, seconds) * SampleRate);
    }
    static std::size_t End(std::size_t begin, double length) {
        return std::min(Frames, begin + At(length));
    }
    void Mix(std::size_t i, float sample, float panL, float panR, float reverb) {
        left[i] += sample * panL;
        right[i] += sample * panR;
        send[i] += sample * reverb;
    }
    static std::array<float, 2> Pan(float pan) {
        return {{std::sqrt(0.5f - 0.5f * pan), std::sqrt(0.5f + 0.5f * pan)}};
    }

    void Pad(double start, double hold, int note, float level, float pan, bool bright = false) {
        const auto begin = At(start);
        const double release = 2.8;
        const auto finish = End(begin, hold + release);
        const auto stereo = Pan(pan);
        const float frequency = NoteFrequency(note);
        uint32_t a = random.Next(), b = random.Next(), c = random.Next(), lfo = random.Next();
        const uint32_t da = Step(frequency * 0.9987f), db = Step(frequency * 1.0014f);
        const uint32_t dc = Step(frequency * 0.5003f), dlfo = Step(0.11f + (note % 7) * 0.013f);
        const float attack = static_cast<float>(std::min(1.7, hold * 0.52));
        float lowL = 0, lowR = 0;
        for (std::size_t i = begin; i < finish; ++i) {
            const float t = static_cast<float>(i - begin) / SampleRate;
            const float envelope = Smooth(t / attack)
                * (t < hold ? 1.0f : 1.0f - Smooth((t - static_cast<float>(hold)) / release));
            const float breath = 0.87f + 0.13f * table.Sin(lfo);
            const float core = 0.19f * table.Sin(c);
            const float voiceL = (bright ? table.String(a) : table.Warm(a)) + core;
            const float voiceR = (bright ? table.String(b) : table.Warm(b)) + core;
            const float filter = bright ? 0.19f : 0.105f;
            lowL += filter * (voiceL - lowL);
            lowR += filter * (voiceR - lowR);
            const float amp = envelope * breath * level;
            left[i] += (lowL * 0.77f + lowR * 0.23f) * amp * stereo[0];
            right[i] += (lowR * 0.77f + lowL * 0.23f) * amp * stereo[1];
            send[i] += (lowL + lowR) * amp * 0.36f;
            a += da; b += db; c += dc; lfo += dlfo;
        }
    }

    void Glass(double start, int note, float level, float pan, double decay = 1.7) {
        const auto begin = At(start), finish = End(begin, decay * 3.5);
        const auto stereo = Pan(pan);
        const float frequency = NoteFrequency(note);
        uint32_t a = 0, b = 0, c = 0;
        const uint32_t da = Step(frequency), db = Step(frequency * 2.001f), dc = Step(frequency * 4.003f);
        float envelope = 1, overtone = 1;
        const float de = std::exp(-1.0f / (static_cast<float>(decay) * SampleRate));
        const float dh = std::exp(-1.0f / (0.22f * SampleRate));
        for (std::size_t i = begin; i < finish; ++i) {
            const float attack = std::min(1.0f, static_cast<float>(i - begin) / (0.006f * SampleRate));
            const float modulation = table.Sin(b) * 0.07f * overtone;
            const uint32_t offset = static_cast<uint32_t>(static_cast<int32_t>(modulation * 2147483648.0f));
            const float tone = table.Sin(a + offset) + 0.22f * table.Sin(c) * overtone;
            const float tail = std::min(1.0f, static_cast<float>(finish - i) / (0.03f * SampleRate));
            Mix(i, tone * envelope * attack * tail * level, stereo[0], stereo[1], 0.68f);
            a += da; b += db; c += dc; envelope *= de; overtone *= dh;
        }
    }

    void Arp(double start, int note, float level, float pan, bool bright) {
        const auto begin = At(start), finish = End(begin, bright ? 0.92 : 1.25);
        const auto stereo = Pan(pan);
        const float frequency = NoteFrequency(note);
        uint32_t a = 0, b = 0;
        const uint32_t da = Step(frequency), db = Step(frequency * 2.0f);
        float envelope = 1, modulationEnvelope = 1;
        const float decay = std::exp(-1.0f / ((bright ? 0.19f : 0.28f) * SampleRate));
        const float modDecay = std::exp(-1.0f / (0.055f * SampleRate));
        for (std::size_t i = begin; i < finish; ++i) {
            const float attack = std::min(1.0f, static_cast<float>(i - begin) / (0.003f * SampleRate));
            const int32_t modulation = static_cast<int32_t>(table.Sin(b) * modulationEnvelope * 420000000.0f);
            const float tone = table.Sin(a + static_cast<uint32_t>(modulation))
                + 0.1f * table.Sin(a * 3u) * modulationEnvelope;
            const float tail = std::min(1.0f, static_cast<float>(finish - i) / (0.025f * SampleRate));
            Mix(i, tone * envelope * attack * tail * level, stereo[0], stereo[1], bright ? 0.3f : 0.45f);
            a += da; b += db; envelope *= decay; modulationEnvelope *= modDecay;
        }
    }

    void Bass(double start, double duration, int note, float level, bool dark = false) {
        const auto begin = At(start), finish = End(begin, duration + 0.08);
        const float frequency = NoteFrequency(note);
        uint32_t a = 0, b = 0;
        const uint32_t da = Step(frequency), db = Step(frequency * 1.002f);
        float low1 = 0, low2 = 0, filterEnv = 1;
        const float decay = std::exp(-1.0f / (0.12f * SampleRate));
        for (std::size_t i = begin; i < finish; ++i) {
            const float t = static_cast<float>(i - begin) / SampleRate;
            const float amp = std::min(1.0f, t / 0.009f)
                * (t < duration ? 1.0f : std::max(0.0f, 1.0f - (t - static_cast<float>(duration)) / 0.08f));
            const float tone = table.String(a) * 0.62f + table.String(b) * 0.2f;
            const float cutoff = (dark ? 0.012f : 0.025f) + filterEnv * (dark ? 0.018f : 0.075f);
            low1 += cutoff * (tone - low1);
            low2 += cutoff * (low1 - low2);
            const float sub = table.Sin(a) * 0.56f;
            Mix(i, (low2 + sub) * amp * level, 0.7071f, 0.7071f, 0.014f);
            a += da; b += db; filterEnv *= decay;
        }
    }

    void Lead(double start, double duration, int note, float level, float pan, bool luminous = false) {
        const auto begin = At(start), finish = End(begin, duration + 0.35);
        const auto stereo = Pan(pan);
        const float frequency = NoteFrequency(note);
        uint32_t a = random.Next(), b = random.Next(), vibrato = 0;
        const uint32_t base = Step(frequency), dv = Step(5.15f);
        float low1 = 0, low2 = 0;
        for (std::size_t i = begin; i < finish; ++i) {
            const float t = static_cast<float>(i - begin) / SampleRate;
            const float envelope = Smooth(t / 0.028f)
                * (t < duration ? 1.0f : std::max(0.0f, 1.0f - (t - static_cast<float>(duration)) / 0.35f));
            const float vib = 1.0f + table.Sin(vibrato) * 0.0027f * Smooth(t / 0.22f);
            const float core = table.String(a) * 0.65f + table.String(b) * 0.35f;
            const float cutoff = luminous ? 0.31f : 0.21f;
            low1 += cutoff * (core - low1); low2 += cutoff * (low1 - low2);
            const float air = luminous ? table.Sin(a * 2u) * 0.12f : 0.0f;
            Mix(i, (low2 + air) * envelope * level, stereo[0], stereo[1], 0.29f);
            a += static_cast<uint32_t>(base * vib * 0.9989f);
            b += static_cast<uint32_t>(base * vib * 1.0012f);
            vibrato += dv;
        }
    }

    void Kick(double start, float level, bool deep = false) {
        const auto begin = At(start), finish = End(begin, deep ? 1.35 : 0.67);
        uint32_t phase = 0;
        float pitch = 1, envelope = 1, click = 1, lastNoise = 0;
        const float pitchDecay = std::exp(-1.0f / (0.028f * SampleRate));
        const float bodyDecay = std::exp(-1.0f / ((deep ? 0.40f : 0.155f) * SampleRate));
        const float clickDecay = std::exp(-1.0f / (0.006f * SampleRate));
        for (std::size_t i = begin; i < finish; ++i) {
            const float attack = std::min(1.0f, static_cast<float>(i - begin) / (0.0015f * SampleRate));
            const float noise = random.Bipolar();
            const float punch = (noise - lastNoise) * click * (deep ? 0.055f : 0.16f);
            const float body = table.Sin(phase) * envelope;
            const float tail = std::min(1.0f, static_cast<float>(finish - i) / (0.03f * SampleRate));
            Mix(i, (body + punch) * level * attack * tail, 0.7071f, 0.7071f, deep ? 0.12f : 0.008f);
            phase += Step((deep ? 36.0f : 48.0f) + 115.0f * pitch);
            pitch *= pitchDecay; envelope *= bodyDecay; click *= clickDecay; lastNoise = noise;
        }
    }

    void Snare(double start, float level, float pan = 0.0f) {
        const auto begin = At(start), finish = End(begin, 0.38);
        const auto stereo = Pan(pan);
        uint32_t body = 0, overtone = 0;
        float noiseLP = 0, topLP = 0, envelope = 1, bodyEnvelope = 1;
        const float decay = std::exp(-1.0f / (0.095f * SampleRate));
        const float bodyDecay = std::exp(-1.0f / (0.034f * SampleRate));
        for (std::size_t i = begin; i < finish; ++i) {
            const float t = static_cast<float>(i - begin) / SampleRate;
            const float noise = random.Bipolar();
            noiseLP += 0.07f * (noise - noiseLP);
            topLP += 0.49f * (noise - noiseLP - topLP);
            const float clap = (t < 0.01f || (t > 0.016f && t < 0.025f)
                || (t > 0.031f && t < 0.04f)) ? 1.25f : 0.65f;
            const float tone = topLP * envelope * clap
                + (0.30f * table.Sin(body) + 0.14f * table.Sin(overtone)) * bodyEnvelope;
            const float attack = std::min(1.0f, t / 0.0015f);
            const float tail = std::min(1.0f, static_cast<float>(finish - i) / (0.025f * SampleRate));
            Mix(i, tone * attack * tail * level, stereo[0], stereo[1], 0.23f);
            body += Step(181.0f); overtone += Step(329.0f);
            envelope *= decay; bodyEnvelope *= bodyDecay;
        }
    }

    void Hat(double start, float level, float pan, bool open = false) {
        const auto begin = At(start), finish = End(begin, open ? 0.43 : 0.14);
        const auto stereo = Pan(pan);
        float low = 0, envelope = 1;
        const float decay = std::exp(-1.0f / ((open ? 0.10f : 0.023f) * SampleRate));
        for (std::size_t i = begin; i < finish; ++i) {
            const float noise = random.Bipolar();
            low += 0.38f * (noise - low);
            const float attack = std::min(1.0f, static_cast<float>(i - begin) / 35.0f);
            const float tail = std::min(1.0f, static_cast<float>(finish - i) / (0.01f * SampleRate));
            Mix(i, (noise - low) * envelope * level * attack * tail, stereo[0], stereo[1], open ? 0.24f : 0.12f);
            envelope *= decay;
        }
    }

    void Crash(double start, float level) {
        const auto begin = At(start), finish = End(begin, 3.2);
        float lowL = 0, lowR = 0, envelope = 1;
        uint32_t metal = 0;
        const float decay = std::exp(-1.0f / (0.88f * SampleRate));
        for (std::size_t i = begin; i < finish; ++i) {
            const float nL = random.Bipolar(), nR = random.Bipolar();
            lowL += 0.115f * (nL - lowL); lowR += 0.115f * (nR - lowR);
            const float attack = std::min(1.0f, static_cast<float>(i - begin) / (0.012f * SampleRate));
            const float ring = table.Sin(metal) * table.Sin(metal * 3u) * 0.09f;
            const float tail = std::min(1.0f, static_cast<float>(finish - i) / (0.05f * SampleRate));
            const float l = (nL - lowL + ring) * envelope * level * attack * tail;
            const float r = (nR - lowR + ring) * envelope * level * attack * tail;
            left[i] += l; right[i] += r; send[i] += (l + r) * 0.3f;
            envelope *= decay; metal += Step(1537.0f);
        }
    }

    void Sweep(double start, double duration, float level, bool falling = false) {
        const auto begin = At(start), finish = End(begin, duration);
        float lowL = 0, lowR = 0, bottomL = 0, bottomR = 0;
        uint32_t phase = 0;
        for (std::size_t i = begin; i < finish; ++i) {
            const float progress = static_cast<float>(i - begin) / static_cast<float>(finish - begin);
            const float ramp = falling ? 1.0f - progress : progress;
            const float shape = falling ? ramp * ramp : ramp * ramp * Smooth(progress * 8.0f);
            const float cutoff = 0.012f + ramp * ramp * 0.33f;
            const float nL = random.Bipolar(), nR = random.Bipolar();
            lowL += cutoff * (nL - lowL); lowR += cutoff * (nR - lowR);
            bottomL += cutoff * 0.16f * (lowL - bottomL);
            bottomR += cutoff * 0.16f * (lowR - bottomR);
            const float tone = table.Sin(phase) * 0.055f * ramp;
            const float finalFade = Smooth((1.0f - progress) * 250.0f);
            const float l = (lowL - bottomL + tone) * shape * level * finalFade;
            const float r = (lowR - bottomR + tone) * shape * level * finalFade;
            left[i] += l; right[i] += r; send[i] += (l + r) * 0.42f;
            phase += Step(70.0f + 700.0f * ramp * ramp * ramp);
        }
    }

    void Atmosphere() {
        Random spaceNoise(0x0FAD3189u);
        uint32_t a = 0, b = 0, motion = 0;
        float lowL = 0, lowR = 0, low2L = 0, low2R = 0;
        for (std::size_t i = 0; i < Frames; ++i) {
            const float t = static_cast<float>(i) / SampleRate;
            const float opening = 1.0f - Smooth((t - 18.0f) / 14.0f);
            const float gravity = Smooth((t - 105.0f) / 5.0f) * (1.0f - Smooth((t - 138.0f) / 6.0f));
            const float ending = Smooth((t - 171.0f) / 4.0f);
            const float amplitude = (0.015f + opening * 0.041f + gravity * 0.031f + ending * 0.013f)
                * Smooth(t / 6.0f);
            const float nL = spaceNoise.Bipolar(), nR = spaceNoise.Bipolar();
            lowL += 0.015f * (nL - lowL); lowR += 0.017f * (nR - lowR);
            low2L += 0.0022f * (lowL - low2L); low2R += 0.002f * (lowR - low2R);
            const float breathing = 0.72f + 0.28f * table.Sin(motion);
            const float drone = (table.Sin(a) + 0.32f * table.Sin(b)) * 0.34f;
            const float l = ((lowL - low2L) * 1.9f + drone) * amplitude * breathing;
            const float r = ((lowR - low2R) * 1.9f + drone) * amplitude * breathing;
            left[i] += l; right[i] += r; send[i] += (l + r) * 0.45f;
            a += Step(46.2493f); b += Step(69.355f); motion += Step(0.067f);
        }
    }

    void Chords(double start, double end, double interval, float level, bool bright, bool gravity = false) {
        int sequence = 0;
        for (double t = start; t < end - 0.01; t += interval, ++sequence) {
            const Chord& chord = gravity ? GravityHarmony[sequence % 4] : Harmony[sequence % 4];
            const double hold = std::min(interval, end - t);
            for (int voice = 0; voice < 5; ++voice) {
                const float pan = (voice - 2) * 0.32f;
                Pad(t, hold, chord.notes[voice], level * (voice == 0 ? 0.93f : 1.0f), pan, bright);
            }
        }
    }

    struct MelodyNote { float beat; float length; int note; };
    void Theme(double start, double end, float level, bool luminous) {
        static constexpr MelodyNote theme[] = {
            {0.0f, 2.5f, 78}, {3.0f, 0.85f, 85}, {4.0f, 2.4f, 81}, {7.0f, 0.7f, 80},
            {8.0f, 2.8f, 78}, {11.0f, 0.8f, 76}, {12.0f, 2.4f, 73}, {15.0f, 0.8f, 76},
            {16.0f, 2.5f, 78}, {19.0f, 0.8f, 81}, {20.0f, 2.5f, 83}, {23.0f, 0.8f, 80},
            {24.0f, 2.3f, 76}, {27.0f, 2.0f, 73}, {30.0f, 1.6f, 76}
        };
        for (double phrase = start; phrase < end; phrase += 16.0) {
            int index = 0;
            for (const auto& n : theme) {
                const double time = phrase + n.beat * 0.5;
                if (time >= end - 0.05) break;
                Lead(time, std::min(static_cast<double>(n.length) * 0.5, end - time),
                    n.note, level, luminous ? -0.12f : -0.06f, luminous);
                if (luminous && (index % 3 == 0)) {
                    Glass(time + 0.015, n.note + 12, level * 0.21f, 0.44f, 0.85);
                    Lead(time + 0.018, n.length * 0.45, n.note - 12, level * 0.30f, 0.26f, true);
                }
                ++index;
            }
        }
    }

    void Rhythm(double start, double end, int act) {
        const int count = static_cast<int>((end - start) * 8.0 + 0.5);
        static constexpr int arpPattern[16] = {0, 2, 4, 1, 3, 2, 0, 4, 2, 3, 1, 4, 3, 0, 2, 4};
        for (int step = 0; step < count; ++step) {
            const double t = start + step * 0.125;
            const int local = step % 16;
            const int bar = step / 16;
            const Chord& chord = Harmony[(step / 32) % 4];
            const bool orbital = act == 1;
            const bool rebirth = act == 4;
            const float rise = orbital ? 0.55f + 0.45f * Smooth((t - start) / 18.0f) : 1.0f;

            if (step % 4 == 0 && (!orbital || t - start >= 8.0 || step % 8 == 0))
                Kick(t, (rebirth ? 0.425f : 0.39f) * rise);
            if (local == 4 || local == 12) {
                if (!orbital || t - start >= 8.0)
                    Snare(t, (rebirth ? 0.40f : 0.355f) * rise, -0.045f);
            }
            if (step % 2 == 0) {
                const bool open = local == 6 || local == 14;
                Hat(t + ((local % 4 == 2) ? 0.008 : 0.0),
                    (open ? 0.090f : 0.058f) * rise,
                    local % 4 == 0 ? -0.30f : 0.36f, open);
            } else if (!orbital && local % 4 == 3) {
                Hat(t, 0.022f, -0.55f, false);
            }
            if (local == 15 && bar % 4 == 3 && !orbital)
                Snare(t, 0.11f, 0.33f);

            // The bass leaves room for the kick, then answers on the upbeat.
            if (step % 2 == 0 && (!orbital || step % 4 == 2 || step % 8 == 0)) {
                int octave = (local == 14 || (local == 6 && bar % 2)) ? 12 : 0;
                int fifth = (local == 10 && bar % 4 == 3) ? 7 : 0;
                Bass(t + 0.014, orbital ? 0.20 : 0.205, chord.root - 12 + octave + fifth,
                    (orbital ? 0.150f : 0.165f) * rise);
            }
            if ((orbital && step % 2 == 0) || (!orbital && local != 7 && local != 15)) {
                const int index = arpPattern[(orbital ? step / 2 : step) % 16];
                const int note = chord.notes[index] + (rebirth && local % 4 == 0 ? 24 : 12);
                const float pan = ((step * 7) % 17 - 8) * 0.075f;
                const float accent = local % 4 == 0 ? 1.18f : 0.85f;
                Arp(t + 0.009, note, (orbital ? 0.063f : rebirth ? 0.054f : 0.059f)
                    * accent * rise, pan, !orbital);
            }
        }
    }

    void Fill(double start, float level) {
        for (int i = 0; i < 8; ++i)
            Snare(start + i * 0.125, level * (0.4f + i * 0.075f), (i % 2 ? 0.32f : -0.32f));
    }

    void Score() {
        Atmosphere();
        Chords(0, 30, 4, 0.067f, false);
        Chords(30, 66, 4, 0.068f, false);
        Chords(66, 108, 4, 0.080f, true);
        Chords(108, 144, 6, 0.074f, false, true);
        Chords(144, 172, 4, 0.090f, true);

        // Four widely spaced notes introduce the melodic fingerprint.
        Glass(4, 78, 0.085f, -0.40f, 2.1);
        Glass(8.5, 85, 0.060f, 0.48f, 2.0);
        Glass(12, 81, 0.075f, -0.15f, 2.3);
        Glass(16.5, 80, 0.059f, 0.36f, 2.2);
        Glass(20, 78, 0.072f, -0.32f, 2.5);
        Glass(24.5, 73, 0.055f, 0.30f, 2.4);
        for (int i = 0; i < 12; ++i) {
            const double t = 18.0 + i;
            const auto& chord = Harmony[(static_cast<int>(t) / 4) % 4];
            Arp(t, chord.notes[(i * 2) % 5] + 12, 0.022f + i * 0.0014f,
                (i % 2 ? 0.58f : -0.58f), false);
        }

        Rhythm(30, 66, 1);
        for (int i = 0; i < 6; ++i) {
            const int notes[] = {78, 85, 81, 80, 78, 76};
            Glass(42 + i * 3.0, notes[i], 0.065f, (i % 2 ? 0.45f : -0.45f), 1.6);
        }

        Rhythm(66, 108, 2);
        Theme(66, 107.4, 0.152f, false);

        // At the singularity the four-on-the-floor disappears. Two close
        // sub pulses recur like a distant heart; fragments drift across it.
        for (int i = 0; i < 18; ++i) {
            const double t = 108.0 + i * 2.0;
            const auto& chord = GravityHarmony[(i / 3) % 4];
            Kick(t, 0.30f, true);
            if (i < 14) Kick(t + 0.375, 0.135f, true);
            Bass(t + 0.05, 1.25, chord.root - 12, 0.15f, true);
            if (i % 2 == 0)
                Glass(t + 0.75, chord.notes[4] + 12, 0.065f, i % 4 ? -0.63f : 0.63f, 2.2);
        }
        const int lostNotes[] = {78, 76, 73, 69, 73, 80};
        for (int i = 0; i < 6; ++i)
            Lead(111.5 + i * 5.0, 1.6, lostNotes[i] - 12, 0.07f, i % 2 ? 0.30f : -0.30f);
        for (int i = 0; i < 32; ++i) {
            const double t = 136.0 + i * 0.25;
            const auto& chord = GravityHarmony[(static_cast<int>(t - 108) / 6) % 4];
            Arp(t, chord.notes[i % 5] + 12, 0.015f + i * 0.0012f, (i % 2 ? 0.47f : -0.47f), true);
            if (i >= 16) Hat(t, 0.022f + (i - 16) * 0.0015f, i % 2 ? -0.3f : 0.3f);
        }

        Rhythm(144, 172, 4);
        Theme(144, 171.7, 0.167f, true);

        // The minor third rises one semitone. A final major-add9 chord hangs
        // in empty space while the last bell rings beyond the picture.
        for (int voice = 0; voice < 5; ++voice)
            Pad(172, 3.4, LastChord.notes[voice], 0.088f, (voice - 2) * 0.32f, true);
        Bass(172, 1.65, 30, 0.17f);
        Kick(172, 0.37f, true);
        Lead(172, 1.6, 78, 0.155f, -0.08f, true);
        Glass(172, 85, 0.087f, -0.40f, 2.0);
        Glass(173, 82, 0.075f, 0.4f, 2.0);
        Glass(174, 90, 0.115f, 0.1f, 2.5);
        Glass(174.02, 78, 0.06f, -0.2f, 2.6);

        Sweep(24, 6, 0.23f);
        Sweep(30, 3.0, 0.14f, true);
        Sweep(60, 6, 0.34f);
        Sweep(66, 3.5, 0.17f, true);
        Sweep(102, 6, 0.34f);
        Sweep(108, 5.0, 0.23f, true);
        Sweep(136, 8, 0.40f);
        Sweep(144, 4.0, 0.20f, true);
        Sweep(168, 4, 0.24f);
        Sweep(172, 4.0, 0.14f, true);
        Crash(30, 0.07f); Crash(66, 0.14f); Crash(82, 0.10f); Crash(98, 0.09f);
        Crash(108, 0.11f); Crash(144, 0.15f); Crash(160, 0.11f); Crash(172, 0.10f);
        Fill(65, 0.17f); Fill(97, 0.13f); Fill(107, 0.19f); Fill(143, 0.22f);
    }

    void SpaceAndMaster() {
        // An eight-line Householder feedback delay network. Unequal prime
        // delays diffuse the original instruments into a dark, long tail.
        static constexpr int sizes[8] = {1423, 1789, 2081, 2389, 2797, 3163, 3541, 4001};
        std::array<std::vector<float>, 8> lines;
        std::array<int, 8> head{};
        std::array<float, 8> damped{};
        for (int j = 0; j < 8; ++j) lines[j].assign(sizes[j], 0.0f);
        std::vector<float> delayL(static_cast<std::size_t>(SampleRate * 0.375), 0.0f);
        std::vector<float> delayR(static_cast<std::size_t>(SampleRate * 0.5625), 0.0f);
        std::size_t dL = 0, dR = 0;
        float dcInL = 0, dcInR = 0, dcOutL = 0, dcOutR = 0;
        float compressorEnvelope = 0;
        const float dcPole = std::exp(-Tau * 18.0f / SampleRate);
        const float attack = std::exp(-1.0f / (0.003f * SampleRate));
        const float release = std::exp(-1.0f / (0.16f * SampleRate));

        for (std::size_t i = 0; i < Frames; ++i) {
            const float echoL = delayL[dL], echoR = delayR[dR];
            delayL[dL] = send[i] * 0.28f + echoR * 0.32f;
            delayR[dR] = send[i] * 0.24f + echoL * 0.32f;
            if (++dL == delayL.size()) dL = 0;
            if (++dR == delayR.size()) dR = 0;

            float sum = 0;
            for (int j = 0; j < 8; ++j) {
                const float sample = lines[j][head[j]];
                damped[j] += 0.24f * (sample - damped[j]);
                sum += damped[j];
            }
            const float injection = send[i] * 0.31f + (echoL + echoR) * 0.07f;
            for (int j = 0; j < 8; ++j) {
                const float feedback = (0.25f * sum - damped[j]) * 0.885f;
                lines[j][head[j]] = feedback + injection * (j % 2 ? -1.0f : 1.0f);
                if (++head[j] == sizes[j]) head[j] = 0;
            }
            const float wetL = (damped[0] + damped[2] - damped[4] + damped[6]) * 0.42f;
            const float wetR = (damped[1] - damped[3] + damped[5] + damped[7]) * 0.42f;
            float l = left[i] + wetL + echoL * 0.31f;
            float r = right[i] + wetR + echoR * 0.31f;

            // DC blocking, linked gentle compression, and a soft saturation
            // stage protect loud transitions without flattening the opening.
            const float hpL = l - dcInL + dcPole * dcOutL;
            const float hpR = r - dcInR + dcPole * dcOutR;
            dcInL = l; dcInR = r; dcOutL = hpL; dcOutR = hpR;
            const float peak = std::max(std::abs(hpL), std::abs(hpR));
            const float coeff = peak > compressorEnvelope ? attack : release;
            compressorEnvelope = peak + coeff * (compressorEnvelope - peak);
            const float gain = compressorEnvelope > 0.46f
                ? std::pow(0.46f / compressorEnvelope, 0.60f) : 1.0f;
            l = hpL * gain * 1.18f; r = hpR * gain * 1.18f;
            l /= 1.0f + std::abs(l) * 0.23f;
            r /= 1.0f + std::abs(r) * 0.23f;
            const float t = static_cast<float>(i) / SampleRate;
            const float fade = Smooth(t / 2.4f) * (1.0f - Smooth((t - 175.0f) / 5.0f));
            left[i] = std::isfinite(l) ? l * fade : 0.0f;
            right[i] = std::isfinite(r) ? r * fade : 0.0f;
        }
    }

    std::vector<int16_t> Finish() {
        Score();
        SpaceAndMaster();
        float peak = 0;
        for (std::size_t i = 0; i < Frames; ++i)
            peak = std::max(peak, std::max(std::abs(left[i]), std::abs(right[i])));
        // A deterministic sample-peak ceiling of -0.5 dBFS. Dither amplitude
        // is below one PCM16 unit; the final clamp makes integer conversion
        // well-defined even on platforms with different libm rounding.
        const float gain = peak > 1.0e-8f ? 0.944f / peak : 1.0f;
        std::vector<int16_t> pcm(Frames * 2);
        Random dither(0xAF7E2119u);
        for (std::size_t i = 0; i < Frames; ++i) {
            const float l = left[i] * gain * 32767.0f + dither.Bipolar() * 0.5f;
            const float r = right[i] * gain * 32767.0f + dither.Bipolar() * 0.5f;
            pcm[i * 2] = static_cast<int16_t>(std::max(-32760.0f, std::min(32760.0f, l)));
            pcm[i * 2 + 1] = static_cast<int16_t>(std::max(-32760.0f, std::min(32760.0f, r)));
        }
        // Exact zero edges prevent device-start/stop clicks.
        pcm[0] = pcm[1] = pcm[pcm.size() - 2] = pcm[pcm.size() - 1] = 0;
        return pcm;
    }
};

} // namespace

std::vector<int16_t> GenerateSoundtrack() {
    Composer composer;
    return composer.Finish();
}

} // namespace Afterlight
