import 'dart:typed_data';

/// Provides access to the firmware microphone check (seal check) over GATT.
abstract class MicrophoneCheckManager {
  /// Runs the outer microphone check.
  Future<MicrophoneCheckResult> runOuterMicrophoneCheck({
    Duration timeout = const Duration(seconds: 12),
  });

  /// Runs the inner microphone check.
  Future<MicrophoneCheckResult> runInnerMicrophoneCheck({
    Duration timeout = const Duration(seconds: 12),
  });

  /// Runs a microphone check with explicit channel selection.
  ///
  /// The firmware expects two bytes:
  /// `leftEnabled` and `rightEnabled`.
  Future<MicrophoneCheckResult> runMicrophoneCheck({
    required bool leftEnabled,
    required bool rightEnabled,
    Duration timeout = const Duration(seconds: 12),
  });
}

class MicrophoneCheckPeak {
  final double frequencyHz;
  final int amplitude;

  const MicrophoneCheckPeak({
    required this.frequencyHz,
    required this.amplitude,
  });
}

class MicrophoneCheckResult {
  static const int expectedPayloadBytes = 40;
  static const int _targetBinCount = 9;

  final int version;
  final int quality;
  final int meanMagnitude;
  final int numPeaks;
  final List<double> frequenciesHz;
  final List<int> magnitudes;

  const MicrophoneCheckResult({
    required this.version,
    required this.quality,
    required this.meanMagnitude,
    required this.numPeaks,
    required this.frequenciesHz,
    required this.magnitudes,
  });

  factory MicrophoneCheckResult.fromBytes(List<int> bytes) {
    if (bytes.length < expectedPayloadBytes) {
      throw StateError(
        'Microphone check payload too short. '
        'Expected at least $expectedPayloadBytes bytes, got ${bytes.length}.',
      );
    }

    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final version = data.getUint8(0);
    final quality = data.getUint8(1);
    final meanMagnitude = data.getUint8(2);
    final numPeaks = data.getUint8(3);

    final frequenciesHz = <double>[];
    final magnitudes = <int>[];

    const frequencyOffset = 4;
    const magnitudeOffset = frequencyOffset + (_targetBinCount * 2);

    for (int i = 0; i < _targetBinCount; i++) {
      final fixedPoint =
          data.getUint16(frequencyOffset + (i * 2), Endian.little);
      frequenciesHz.add(fixedPoint / 16.0);
    }
    for (int i = 0; i < _targetBinCount; i++) {
      magnitudes.add(data.getUint16(magnitudeOffset + (i * 2), Endian.little));
    }

    return MicrophoneCheckResult(
      version: version,
      quality: quality,
      meanMagnitude: meanMagnitude,
      numPeaks: numPeaks,
      frequenciesHz: frequenciesHz,
      magnitudes: magnitudes,
    );
  }

  List<MicrophoneCheckPeak> get peaks {
    final results = <MicrophoneCheckPeak>[];
    for (int i = 0; i < frequenciesHz.length && i < magnitudes.length; i++) {
      final frequency = frequenciesHz[i];
      final amplitude = magnitudes[i];
      if (frequency <= 0 && amplitude <= 0) {
        continue;
      }
      results.add(
        MicrophoneCheckPeak(
          frequencyHz: frequency,
          amplitude: amplitude,
        ),
      );
    }
    return results;
  }

  MicrophoneCheckPeak? peakNearest(
    double targetHz, {
    required double toleranceHz,
  }) {
    MicrophoneCheckPeak? best;
    double? bestDelta;
    for (final peak in peaks) {
      final delta = (peak.frequencyHz - targetHz).abs();
      if (delta > toleranceHz) {
        continue;
      }
      if (best == null || delta < (bestDelta ?? double.infinity)) {
        best = peak;
        bestDelta = delta;
      }
    }
    return best;
  }
}
