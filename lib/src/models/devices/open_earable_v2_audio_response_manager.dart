import 'dart:async';
import 'dart:typed_data';

import 'package:open_earable_protocols/open_earable_protocols.dart';

import '../../managers/ble_gatt_manager.dart';
import '../capabilities/audio_response_manager.dart';

/// Audio response protocol implementation for OpenEarable V2 devices.
class OpenEarableV2AudioResponseManager implements AudioResponseManager {
  /// Creates an audio response manager backed by [bleManager].
  OpenEarableV2AudioResponseManager({
    required this.bleManager,
    required this.deviceId,
    this.notificationTimeout = const Duration(seconds: 10),
  });

  /// BLE manager used to communicate with the device.
  final BleGattManager bleManager;

  /// Identifier of the OpenEarable device.
  final String deviceId;

  /// Maximum time to wait for each protocol notification.
  final Duration notificationTimeout;

  bool _operationInProgress = false;

  @override
  Future<void> uploadAudioBuffer({
    required int transferId,
    required List<int> samples,
    required int samplingRate,
    int maximumSamplesPerChunk = 118,
    AudioResponseUploadProgressCallback? onProgress,
  }) {
    return _runExclusive(() async {
      _validateTransferParameters(
        transferId: transferId,
        samples: samples,
        samplingRate: samplingRate,
        maximumSamplesPerChunk: maximumSamplesPerChunk,
      );

      final statusIterator = StreamIterator<List<int>>(
        await bleManager.subscribe(
          deviceId: deviceId,
          serviceId: AudioResponseBleUuids.serviceUuid,
          characteristicId:
              AudioResponseBleUuids.transferStatusCharacteristicUuid,
        ),
      );
      var committed = false;
      var lastAcknowledgedSamples = 0;

      void reportProgress(
        AudioResponseUploadPhase phase,
        int acknowledgedSamples,
      ) {
        onProgress?.call(
          AudioResponseUploadProgress(
            phase: phase,
            acknowledgedSamples: acknowledgedSamples,
            totalSamples: samples.length,
          ),
        );
      }

      void reportAcknowledgedProgress(AudioResponseTransferStatus status) {
        if (status.next_sample_offset <= lastAcknowledgedSamples) {
          return;
        }
        lastAcknowledgedSamples = status.next_sample_offset;
        reportProgress(
          AudioResponseUploadPhase.uploading,
          lastAcknowledgedSamples,
        );
      }

      try {
        reportProgress(AudioResponseUploadPhase.starting, 0);
        var statusFuture = _nextTransferStatus(statusIterator, transferId);
        await _write(
          AudioResponseBleUuids.transferControlCharacteristicUuid,
          AudioResponseTransferControl.start(
            AudioResponseTransferStart(
              transfer_id: transferId,
              total_samples: samples.length,
              sampling_rate: samplingRate,
              checksum: _crc32IsoHdlc(samples),
            ),
          ).toBytes(),
        );

        var status = await statusFuture;
        _requireStatus(status, expectedStatus: 0);
        if (status.next_sample_offset != 0) {
          throw StateError(
            'New audio response transfer started at unexpected sample offset '
            '${status.next_sample_offset}',
          );
        }
        reportProgress(AudioResponseUploadPhase.uploading, 0);

        var sentOffset = status.next_sample_offset;
        while (sentOffset < samples.length) {
          if (status.credits == 0) {
            status = await _nextTransferStatus(statusIterator, transferId);
            _requireStatus(status, expectedStatus: 0);
            if (status.next_sample_offset > sentOffset) {
              throw StateError(
                'Device acknowledged unsent sample offset '
                '${status.next_sample_offset}',
              );
            }
            reportAcknowledgedProgress(status);
            continue;
          }

          statusFuture = _nextTransferStatus(statusIterator, transferId);
          for (var credit = 0;
              credit < status.credits && sentOffset < samples.length;
              credit++) {
            final end = (sentOffset + maximumSamplesPerChunk).clamp(
              0,
              samples.length,
            );
            final chunkSamples = samples.sublist(sentOffset, end);
            await _write(
              AudioResponseBleUuids.transferDataCharacteristicUuid,
              AudioResponseTransferChunk(
                transfer_id: transferId,
                sample_offset: sentOffset,
                sample_count: chunkSamples.length,
                samples: chunkSamples,
              ).toBytes(),
              withoutResponse: true,
            );
            sentOffset = end;
          }

          status = await statusFuture;
          while (true) {
            _requireStatus(status, expectedStatus: 0);
            if (status.next_sample_offset > sentOffset) {
              throw StateError(
                'Device acknowledged unsent sample offset '
                '${status.next_sample_offset}',
              );
            }
            reportAcknowledgedProgress(status);
            if (status.next_sample_offset == sentOffset) {
              break;
            }
            status = await _nextTransferStatus(statusIterator, transferId);
          }
        }

        reportProgress(
          AudioResponseUploadPhase.committing,
          lastAcknowledgedSamples,
        );
        statusFuture = _nextTransferStatus(statusIterator, transferId);
        await _write(
          AudioResponseBleUuids.transferControlCharacteristicUuid,
          AudioResponseTransferControl.commit(
            AudioResponseTransferCommit(transfer_id: transferId),
          ).toBytes(),
        );
        _requireStatus(await statusFuture, expectedStatus: 1);
        committed = true;
        reportProgress(
          AudioResponseUploadPhase.completed,
          lastAcknowledgedSamples,
        );
      } finally {
        if (!committed) {
          await _abortTransfer(transferId);
        }
        await statusIterator.cancel();
      }
    });
  }

  @override
  Future<AudioResponseResult> measureAudioResponse(AudioResponseConfig config) {
    return _runExclusive(() async {
      _validateConfig(config);

      final resultIterator = StreamIterator<List<int>>(
        await bleManager.subscribe(
          deviceId: deviceId,
          serviceId: AudioResponseBleUuids.serviceUuid,
          characteristicId: AudioResponseBleUuids.resultCharacteristicUuid,
        ),
      );

      try {
        final resultFuture = _nextResult(resultIterator, config.id);
        await _write(
          AudioResponseBleUuids.configCharacteristicUuid,
          config.toBytes(),
        );
        final result = await resultFuture;
        _validateResult(config, result);
        return result;
      } finally {
        await resultIterator.cancel();
      }
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_operationInProgress) {
      throw StateError('An audio response operation is already in progress');
    }

    _operationInProgress = true;
    try {
      return await operation();
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _write(
    String characteristicId,
    Uint8List bytes, {
    bool withoutResponse = false,
  }) {
    return bleManager.write(
      deviceId: deviceId,
      serviceId: AudioResponseBleUuids.serviceUuid,
      characteristicId: characteristicId,
      byteData: bytes,
      withoutResponse: withoutResponse,
    );
  }

  Future<AudioResponseTransferStatus> _nextTransferStatus(
    StreamIterator<List<int>> iterator,
    int transferId,
  ) async {
    while (await iterator.moveNext().timeout(notificationTimeout)) {
      final status = AudioResponseTransferStatus.fromBytes(
        Uint8List.fromList(iterator.current),
      );
      if (status.transfer_id == transferId) {
        return status;
      }
    }
    throw StateError('Audio response transfer status stream closed');
  }

  Future<AudioResponseResult> _nextResult(
    StreamIterator<List<int>> iterator,
    int measurementId,
  ) async {
    while (await iterator.moveNext().timeout(notificationTimeout)) {
      final result = AudioResponseResult.fromBytes(
        Uint8List.fromList(iterator.current),
      );
      if (result.id == measurementId) {
        return result;
      }
    }
    throw StateError('Audio response result stream closed');
  }

  void _requireStatus(
    AudioResponseTransferStatus status, {
    required int expectedStatus,
  }) {
    if (status.status == expectedStatus) {
      return;
    }
    throw AudioResponseTransferException(
      status: status.status,
      message: _transferStatusMessages[status.status] ?? 'Unknown status',
    );
  }

  Future<void> _abortTransfer(int transferId) async {
    try {
      await _write(
        AudioResponseBleUuids.transferControlCharacteristicUuid,
        AudioResponseTransferControl.abort(
          AudioResponseTransferAbort(transfer_id: transferId),
        ).toBytes(),
      );
    } on Object {
      // Preserve the original transfer error if best-effort cleanup fails.
    }
  }

  void _validateTransferParameters({
    required int transferId,
    required List<int> samples,
    required int samplingRate,
    required int maximumSamplesPerChunk,
  }) {
    if (transferId < 0 || transferId > 0xffff) {
      throw RangeError.range(transferId, 0, 0xffff, 'transferId');
    }
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'must not be empty');
    }
    if (samples.length > 0xffffffff) {
      throw RangeError('samples length must fit an unsigned 32-bit integer');
    }
    if (samples.any((sample) => sample < -0x8000 || sample > 0x7fff)) {
      throw RangeError('Every sample must fit a signed 16-bit integer');
    }
    if (samplingRate <= 0 || samplingRate > 0xffffffff) {
      throw RangeError.range(samplingRate, 1, 0xffffffff, 'samplingRate');
    }
    if (maximumSamplesPerChunk <= 0 || maximumSamplesPerChunk > 0xffff) {
      throw RangeError.range(
        maximumSamplesPerChunk,
        1,
        0xffff,
        'maximumSamplesPerChunk',
      );
    }
  }

  void _validateConfig(AudioResponseConfig config) {
    if (config.id < 0 || config.id > 0xff) {
      throw RangeError.range(config.id, 0, 0xff, 'config.id');
    }
    if (config.transfer_id < 0 || config.transfer_id > 0xffff) {
      throw RangeError.range(
        config.transfer_id,
        0,
        0xffff,
        'config.transfer_id',
      );
    }
    if (!config.volume.isFinite) {
      throw ArgumentError.value(
        config.volume,
        'config.volume',
        'must be finite',
      );
    }
    if (config.points < 0 || config.points > 0xff) {
      throw RangeError.range(config.points, 0, 0xff, 'config.points');
    }
    if (config.frequencies.length != config.points) {
      throw ArgumentError.value(
        config.frequencies,
        'config.frequencies',
        'length must match config.points',
      );
    }
    if (config.frequencies
        .any((frequency) => frequency < 0 || frequency > 0xffff)) {
      throw RangeError(
        'Every config frequency must fit an unsigned 16-bit integer',
      );
    }
  }

  void _validateResult(
    AudioResponseConfig config,
    AudioResponseResult result,
  ) {
    if (config.points == 0) {
      return;
    }
    if (result.points != config.points ||
        !_listEquals(result.frequencies, config.frequencies)) {
      throw StateError(
        'Audio response result points do not match the requested frequencies',
      );
    }
  }
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

const Map<int, String> _transferStatusMessages = {
  0: 'Ready to receive chunks',
  1: 'Transfer committed',
  2: 'Transfer aborted',
  3: 'Invalid command or transfer state',
  4: 'Invalid chunk offset or length',
  5: 'Insufficient storage',
  6: 'Checksum mismatch',
  7: 'Transfer timed out',
};

int _crc32IsoHdlc(List<int> samples) {
  var crc = 0xffffffff;
  for (final sample in samples) {
    final value = sample & 0xffff;
    crc = _updateCrc32(crc, value & 0xff);
    crc = _updateCrc32(crc, value >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

int _updateCrc32(int crc, int byte) {
  var updated = crc ^ byte;
  for (var bit = 0; bit < 8; bit++) {
    updated = (updated & 1) != 0 ? (updated >> 1) ^ 0xedb88320 : updated >> 1;
  }
  return updated;
}
