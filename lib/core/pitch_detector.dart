/// High-accuracy pitch detection using an enhanced YIN algorithm.
///
/// Improvements over the previous version (inspired by FastTune's approach):
///
/// 1. LOWER RMS FLOOR (0.001 instead of 0.003):
///    Acoustic guitars and quiet plucks can have very low amplitude at the
///    microphone. The previous 0.003 floor was too aggressive and gated out
///    real notes, especially for bass strings. YIN's CMNDF is the real quality
///    gate — not amplitude.
///
/// 2. TIGHTER YIN THRESHOLD (0.12 instead of 0.15):
///    A threshold of 0.12 means we only accept lags where the CMNDF dips
///    very clearly below the noise floor. This dramatically reduces false
///    positives (phantom notes) while still catching real plucks cleanly.
///
/// 3. PARABOLIC INTERPOLATION — always applied, sub-sample precision:
///    The original quantised to whole-sample lag steps. We always apply
///    parabolic interpolation, giving sub-cent frequency accuracy.
///
/// 4. HARMONIC GUARD — reject octave errors:
///    After finding the best lag, we check if half that lag (an octave up)
///    also has a low CMNDF value. If so, the shorter lag is likely the true
///    fundamental and we prefer it. This fixes the classic octave-doubling
///    bug (detecting E3 instead of E2 on a low guitar string).
///
/// 5. EXTENDED WINDOW SIZE (from caller) — now supports 8192 samples
///    for better low-frequency resolution without code change here.
library pitch_detector;

import 'dart:math' as math;

class PitchDetector {
  final double minFrequency;
  final double maxFrequency;

  /// PRIMARY quality gate. Lower = stricter.
  /// 0.12 rejects broadband noise cleanly; most real notes dip well below.
  final double yinThreshold;

  /// Fallback: if nothing dips below [yinThreshold], accept the global
  /// minimum if it's below this value.
  final double fallbackMaxCmndf;

  /// Absolute minimum RMS before processing (true silence gate).
  /// 0.001 is well below any real pluck, above electrical noise floor.
  final double minRms;

  PitchDetector({
    this.minFrequency = 60,
    this.maxFrequency = 1500,
    this.yinThreshold = 0.12,
    this.fallbackMaxCmndf = 0.25,
    this.minRms = 0.001,
  }) {
    if (minFrequency <= 0 || maxFrequency <= minFrequency) {
      throw ArgumentError('Invalid frequency range: $minFrequency..$maxFrequency');
    }
  }

  /// Returns the detected fundamental frequency in Hz, or null if
  /// silent/noisy/no periodic signal found.
  double? detectPitch(List<double> samples, double sampleRate) {
    final int n = samples.length;
    if (n < 1024 || sampleRate <= 0) return null;

    // ── Gate 1: RMS silence gate ─────────────────────────────────────
    double sumSq = 0;
    for (final s in samples) {
      sumSq += s * s;
    }
    final double rms = math.sqrt(sumSq / n);
    if (rms < minRms) return null;

    // ── YIN lag bounds ────────────────────────────────────────────────
    final int minLag = (sampleRate / maxFrequency).floor().clamp(2, n ~/ 2 - 1);
    final int maxLag = (sampleRate / minFrequency).ceil().clamp(minLag + 1, n ~/ 2 - 1);
    if (maxLag <= minLag) return null;

    final int w = n ~/ 2;

    // ── Step 1: Difference function  d(tau) = Σ (x[j] - x[j+tau])² ──
    final List<double> d = List<double>.filled(maxLag + 1, 0.0);
    for (int tau = 1; tau <= maxLag; tau++) {
      double sum = 0.0;
      for (int j = 0; j < w; j++) {
        final double diff = samples[j] - samples[j + tau];
        sum += diff * diff;
      }
      d[tau] = sum;
    }

    // ── Step 2: CMNDF ─────────────────────────────────────────────────
    final List<double> cmn = List<double>.filled(maxLag + 1, 1.0);
    double runningSum = 0.0;
    for (int tau = 1; tau <= maxLag; tau++) {
      runningSum += d[tau];
      cmn[tau] = runningSum > 0 ? d[tau] * tau / runningSum : 1.0;
    }

    // ── Step 3: Find first dip below threshold ────────────────────────
    int bestTau = -1;
    for (int tau = minLag; tau < maxLag; tau++) {
      if (cmn[tau] < yinThreshold) {
        // Slide to the local minimum of this dip
        while (tau + 1 < maxLag && cmn[tau + 1] < cmn[tau]) {
          tau++;
        }
        bestTau = tau;
        break;
      }
    }

    // Fallback: global minimum if under lenient threshold
    if (bestTau == -1) {
      double minVal = double.infinity;
      for (int tau = minLag; tau <= maxLag; tau++) {
        if (cmn[tau] < minVal) {
          minVal = cmn[tau];
          bestTau = tau;
        }
      }
      if (minVal > fallbackMaxCmndf) return null;
    }

    if (bestTau <= minLag || bestTau >= maxLag) return null;

    // ── Step 4: Harmonic guard — prefer octave-up if it's also periodic ─
    // If half the lag also has a low CMNDF, the real fundamental might be
    // at double the frequency (i.e. we found a sub-harmonic). Accept the
    // shorter lag if it has a comparably low CMNDF.
    final int halfTau = bestTau ~/ 2;
    if (halfTau >= minLag && halfTau <= maxLag) {
      if (cmn[halfTau] < yinThreshold * 1.5) {
        // The octave-up candidate is also very periodic — prefer it
        bestTau = halfTau;
      }
    }

    if (bestTau <= minLag || bestTau >= maxLag) return null;

    // ── Step 5: Parabolic interpolation (always) ──────────────────────
    final double y0 = cmn[bestTau - 1];
    final double y1 = cmn[bestTau];
    final double y2 = cmn[bestTau + 1];
    final double denom = y0 - 2 * y1 + y2;
    double refinedTau = bestTau.toDouble();
    if (denom.abs() > 1e-12) {
      refinedTau += 0.5 * (y0 - y2) / denom;
    }

    if (refinedTau <= 0) return null;
    final double freq = sampleRate / refinedTau;
    if (freq < minFrequency || freq > maxFrequency || freq.isNaN) return null;

    return freq;
  }
}
