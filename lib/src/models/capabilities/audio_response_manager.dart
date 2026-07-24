import 'package:open_earable_protocols/open_earable_protocols.dart';

/// An interface for managing audio response measurements.
abstract class AudioResponseManager {
  /// Uploads and commits signed 16-bit PCM [samples] for later measurements.
  ///
  /// [maximumSamplesPerChunk] must fit the effective GATT write payload.
  Future<void> uploadAudioBuffer({
    required int transferId,
    required List<int> samples,
    required int samplingRate,
    int maximumSamplesPerChunk = 118,
  });

  /// Starts a measurement and returns its protocol result.
  ///
  /// The [config] must reference a buffer previously committed by
  /// [uploadAudioBuffer].
  Future<AudioResponseResult> measureAudioResponse(AudioResponseConfig config);
}

/// Error reported by the device while transferring an audio response buffer.
class AudioResponseTransferException implements Exception {
  /// Creates an audio response transfer error from a protocol status value.
  const AudioResponseTransferException({
    required this.status,
    required this.message,
  });

  /// Numeric status reported by the audio response protocol.
  final int status;

  /// Human-readable description of [status].
  final String message;

  @override
  String toString() => 'AudioResponseTransferException($status): $message';
}
