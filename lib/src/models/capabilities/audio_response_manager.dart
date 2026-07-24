import 'package:open_earable_protocols/open_earable_protocols.dart';

/// Receives progress updates for an audio buffer upload.
typedef AudioResponseUploadProgressCallback = void Function(
  AudioResponseUploadProgress progress,
);

/// Current phase of an audio buffer upload.
enum AudioResponseUploadPhase {
  /// The transfer is being initialized on the device.
  starting,

  /// Audio samples are being transferred and acknowledged by the device.
  uploading,

  /// All samples are acknowledged and the transfer is being committed.
  committing,

  /// The device successfully committed the transfer.
  completed,
}

/// Immutable progress reported while uploading an audio buffer.
class AudioResponseUploadProgress {
  /// Creates an audio buffer upload progress update.
  const AudioResponseUploadProgress({
    required this.phase,
    required this.acknowledgedSamples,
    required this.totalSamples,
  });

  /// Current transfer phase.
  final AudioResponseUploadPhase phase;

  /// Number of samples acknowledged by the device.
  final int acknowledgedSamples;

  /// Total number of samples in the transfer.
  final int totalSamples;

  /// Fraction of samples acknowledged by the device, between zero and one.
  double get fraction =>
      totalSamples == 0 ? 0 : acknowledgedSamples / totalSamples;
}

/// An interface for managing audio response measurements.
abstract class AudioResponseManager {
  /// Uploads and commits signed 16-bit PCM [samples] for later measurements.
  ///
  /// [maximumSamplesPerChunk] must fit the effective GATT write payload.
  /// [onProgress] receives synchronous updates based on sample offsets
  /// acknowledged by the device. Exceptions thrown by the callback terminate
  /// the upload.
  Future<void> uploadAudioBuffer({
    required int transferId,
    required List<int> samples,
    required int samplingRate,
    int maximumSamplesPerChunk = 118,
    AudioResponseUploadProgressCallback? onProgress,
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
