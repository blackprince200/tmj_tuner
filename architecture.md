# Guitar Tuner — Pitch Detection Architecture

## Overview Pipeline

```
Microphone
    ↓
 PCM audio
    ↓
  STFT
    ↓
Frequency spectrum
    ↓
┌──────────┴──────────┐
↓                     ↓
Single pitch      Multiple peaks
 detection          detection
    ↓                     ↓
  YIN/               FFT +
pitch_detector_dart  peak finding
```

---

## 1. Single String Plucked → Extremely Accurate Pitch

For one clearly plucked string, use:

- PCM 16-bit
- 44.1 kHz mono
- 4096–8192 samples per analysis window
- Overlapping windows (e.g. 50–75%)
- DC-offset removal
- Windowing such as Hann
- YIN or McLeod Pitch Method (MPM) as the primary pitch detector
- Autocorrelation as a secondary/checking method
- RMS/noise gate
- Confidence score
- Temporal smoothing/median filtering
- Octave-error rejection

### Engine A — Single-String Tuner

```
YIN / MPM
   +
autocorrelation verification
   +
FFT verification
   +
confidence
   +
smoothing
```

**Example output:**
```
Detected: 110.13 Hz
Target:   110.00 Hz
Cents: +2.0
```

For tuning, cents are much more useful than displaying only Hz.

**Formula:**
```dart
double centsDifference(double frequency, double target) {
  return 1200 * log(frequency / target) / ln2;
}
```

**Examples:**
- 110.00 Hz → 0 cents
- 110.50 Hz → slightly sharp
- 109.50 Hz → slightly flat

---

## 2. Multiple-String Detection

```
Microphone
    ↓
PCM16 44.1 kHz mono
    ↓
PCM → samples
    ↓
DC removal
    ↓
Hann window
    ↓
   FFT
    ↓
Magnitude spectrum
    ↓
Peak detection
    ↓
Harmonic grouping
    ↓
Fundamental estimation
    ↓
Remove duplicate harmonics
    ↓
Return multiple frequencies
```

### Engine B — Multiple-String Detector

```
FFT
 ↓
spectral peaks
 ↓
harmonic analysis
 ↓
fundamental estimation
 ↓
frequency list
```

**Example output:**
```
Detected strings:
E2 = 82.4 Hz
A2 = 110.0 Hz
D3 = 146.8 Hz
```

Then map them to guitar strings.

---

## Window Size Consideration

Current setting:
```dart
const requiredBytes = 4096 * 2;
```

That's 4096 samples, which at 44.1 kHz is:
```
4096 / 44100 = 92.9 ms
```

That's okay, but for very sensitive low-frequency detection, use **8192 samples**, because E2 = 82.41 Hz has a period of approximately:
```
44100 / 82.41 ≈ 535 samples
```

- With 4096 samples → only ~7.6 cycles
- With 8192 samples → ~15.3 cycles

---

---

## Processing Branches

```
Raw audio
   │
   ├── YIN/MPM ──────── Single pitch
   │
   ├── FFT ──────────── Multiple pitches
   │
   └── RMS/confidence ─ Signal quality
```

---

## Full Pipeline (Frame-Based)

```
                 AUDIO STREAM
                      │
                      ▼
                PCM16 samples
                      │
                      ▼
                Frame manager
              8192 window / 4096 hop
                      │
             ┌────────┴────────┐
             │                 │
             ▼                 ▼
       SINGLE MODE        MULTI MODE
             │                 │
             ▼                 ▼
        YIN / MPM             FFT
             │                 │
             ▼                 ▼
      autocorrelation     spectral peaks
             │                 │
             └──────┬──────────┘
                    │
                    ▼
              validation
                    │
                    ▼
               smoothing
                    │
                    ▼
                 OUTPUT
```

---

## Requirements Summary

| Requirement | Technique |
|---|---|
| Audio capture | PCM16 |
| Channels | Mono |
| Sample rate | 44.1 kHz, verify actual rate |
| Single string | YIN or MPM |
| Single-string backup | Autocorrelation |
| Multiple strings | FFT |
| Multiple fundamental detection | HPS / harmonic summation |
| DC | Remove |
| Window | Hann |
| Frame | 8192 samples |
| Hop | 4096 samples |
| Noise | RMS/noise gate |
| Reliability | Confidence score |
| Stability | Median/EMA smoothing |
| Tuning display | Hz + cents |
| Guitar range | ~70–400 Hz fundamentals |
| Harmonics | Explicitly suppress/group |
| Octave errors | Reject using harmonic consistency |

---

## Confidence Scoring

```
Confidence =
    correlation strength
  + peak clarity
  + signal strength
  + harmonic/frequency consistency
```

```dart
final rms = sqrt(sumSquared / samples.length);

final clarity = bestValue - secondBestValue;
```

### Confidence Factors

```
                ┌─ autocorrelation strength
                │
                ├─ peak clarity
                │
                ├─ RMS / noise floor
                │
                ├─ fundamental vs harmonics
                │
                └─ frame-to-frame stability
                         ↓
                    CONFIDENCE
```

### Confidence Thresholds

| Range | Meaning |
|---|---|
| ≥ 0.90 | Very reliable → display normally |
| 0.75–0.90 | Probably reliable → display but smooth |
| 0.50–0.75 | Uncertain → don't update tuner needle aggressively |
| < 0.50 | Reject → NO PITCH |

---

## Feature Decision Table

| Feature | Use | Why |
|---|---|---|
| 🎸 Single string plucked | YIN | Accurate fundamental detection, good at rejecting octave/harmonic errors |
| 🎸 Single string, very stable | YIN + confidence + smoothing | Best for a sensitive tuner UI |
| 🎸 Multiple strings plucked | FFT + harmonic analysis | Finds multiple frequencies simultaneously |
| 🎵 Multiple-frequency fundamental detection | FFT + Harmonic Product Spectrum (HPS) | Helps distinguish fundamentals from harmonics |
| 🔊 Signal detection | RMS + adaptive noise gate | Prevents noise from producing pitches |
| 📈 Stable display | Median + EMA | Prevents jumping |
| 🎯 Tuning | Frequency → cents | Shows how sharp/flat the string is |

---

## Final Combined Pipeline

```
Microphone
   ↓
PCM16 @ 44.1 kHz
   ↓
Frame/window
   ↓
Remove DC offset
   ↓
Hann window
   ↓
┌───────────────┬───────────────┐
│      YIN      │      FFT      │
│               │               │
│ Accurate      │ Multiple      │
│ single pitch  │ frequencies   │
└───────────────┴───────────────┘
         ↓
  Confidence score
         ↓
  Median / EMA smoothing
         ↓
     Final pitch
```

---

## Dependencies

```yaml
fftea: ^1.5.0
```
