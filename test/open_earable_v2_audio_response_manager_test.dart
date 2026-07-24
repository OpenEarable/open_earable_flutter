import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/managers/ble_gatt_manager.dart';
import 'package:open_earable_flutter/src/models/capabilities/audio_response_manager.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2_audio_response_manager.dart';
import 'package:open_earable_protocols/open_earable_protocols.dart';

void main() {
  group('OpenEarableV2AudioResponseManager', () {
    test('uploads chunks according to credits and commits the transfer',
        () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );
      const samples = [0, 1000, -1000, 32767, -32768];
      var uploadedSamples = 0;

      bleManager.onWrite = (write) {
        if (write.characteristicId ==
            AudioResponseBleUuids.transferControlCharacteristicUuid) {
          final control = AudioResponseTransferControl.fromBytes(write.bytes);
          if (_controlType(control) == 0) {
            final start = control.command as AudioResponseTransferStart;
            expect(start.transfer_id, 42);
            expect(start.total_samples, samples.length);
            expect(start.sampling_rate, 16000);
            expect(start.checksum, 0x8c06db29);
            bleManager.emitStatus(
              AudioResponseTransferStatus(
                transfer_id: 42,
                status: 0,
                next_sample_offset: 0,
                credits: 2,
              ),
            );
          } else if (_controlType(control) == 1) {
            bleManager.emitStatus(
              AudioResponseTransferStatus(
                transfer_id: 42,
                status: 1,
                next_sample_offset: samples.length,
                credits: 0,
              ),
            );
          }
        } else if (write.characteristicId ==
            AudioResponseBleUuids.transferDataCharacteristicUuid) {
          final chunk = AudioResponseTransferChunk.fromBytes(write.bytes);
          expect(chunk.sample_offset, uploadedSamples);
          uploadedSamples += chunk.sample_count;
          bleManager.emitStatus(
            AudioResponseTransferStatus(
              transfer_id: 42,
              status: 0,
              next_sample_offset: uploadedSamples,
              credits: 2,
            ),
          );
        }
      };

      await manager.uploadAudioBuffer(
        transferId: 42,
        samples: samples,
        samplingRate: 16000,
        maximumSamplesPerChunk: 2,
      );

      final controls = bleManager.writes
          .where(
            (write) =>
                write.characteristicId ==
                AudioResponseBleUuids.transferControlCharacteristicUuid,
          )
          .map((write) => AudioResponseTransferControl.fromBytes(write.bytes))
          .toList();
      final chunks = bleManager.writes
          .where(
            (write) =>
                write.characteristicId ==
                AudioResponseBleUuids.transferDataCharacteristicUuid,
          )
          .map((write) => AudioResponseTransferChunk.fromBytes(write.bytes))
          .toList();

      expect(controls.map(_controlType), [0, 1]);
      expect(chunks.map((chunk) => chunk.samples), [
        [0, 1000],
        [-1000, 32767],
        [-32768],
      ]);
      expect(
        bleManager.writes
            .where(
              (write) =>
                  write.characteristicId ==
                  AudioResponseBleUuids.transferDataCharacteristicUuid,
            )
            .every((write) => write.withoutResponse),
        isTrue,
      );
      expect(
        bleManager.writes
            .where(
              (write) =>
                  write.characteristicId !=
                  AudioResponseBleUuids.transferDataCharacteristicUuid,
            )
            .every((write) => !write.withoutResponse),
        isTrue,
      );
    });

    test('writes config and returns the matching typed result', () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );
      final config = AudioResponseConfig(
        id: 7,
        transfer_id: 42,
        volume: 0.5,
        points: 2,
        frequencies: [100, 200],
      );

      bleManager.onWrite = (write) {
        if (write.characteristicId ==
            AudioResponseBleUuids.configCharacteristicUuid) {
          final decodedConfig = AudioResponseConfig.fromBytes(write.bytes);
          expect(decodedConfig.id, 7);
          expect(decodedConfig.transfer_id, 42);
          expect(decodedConfig.volume, closeTo(0.5, 0.0001));
          expect(decodedConfig.points, 2);
          expect(decodedConfig.frequencies, [100, 200]);
          bleManager.emitResult(
            AudioResponseResult(
              id: 7,
              points: 2,
              frequencies: [100, 200],
              response: [10, 20],
            ),
          );
        }
      };

      final result = await manager.measureAudioResponse(config);

      expect(result.id, 7);
      expect(result.frequencies, [100, 200]);
      expect(result.response, [10, 20]);
    });

    test('allows device default measurement points', () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );
      final config = AudioResponseConfig(
        id: 7,
        transfer_id: 42,
        volume: 0.5,
        points: 0,
        frequencies: [],
      );

      bleManager.onWrite = (write) {
        if (write.characteristicId ==
            AudioResponseBleUuids.configCharacteristicUuid) {
          final decodedConfig = AudioResponseConfig.fromBytes(write.bytes);
          expect(decodedConfig.points, 0);
          expect(decodedConfig.frequencies, isEmpty);
          bleManager.emitResult(
            AudioResponseResult(
              id: 7,
              points: 2,
              frequencies: [100, 200],
              response: [10, 20],
            ),
          );
        }
      };

      final result = await manager.measureAudioResponse(config);

      expect(result.points, 2);
      expect(result.frequencies, [100, 200]);
    });

    test('rejects invalid point configuration before writing config', () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );

      await expectLater(
        manager.measureAudioResponse(
          AudioResponseConfig(
            id: 7,
            transfer_id: 42,
            volume: 0.5,
            points: 2,
            frequencies: [100],
          ),
        ),
        throwsArgumentError,
      );
      expect(bleManager.writes, isEmpty);
    });

    test('rejects result points that do not match requested points', () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );
      final config = AudioResponseConfig(
        id: 7,
        transfer_id: 42,
        volume: 0.5,
        points: 2,
        frequencies: [100, 200],
      );

      bleManager.onWrite = (write) {
        if (write.characteristicId ==
            AudioResponseBleUuids.configCharacteristicUuid) {
          bleManager.emitResult(
            AudioResponseResult(
              id: 7,
              points: 2,
              frequencies: [100, 300],
              response: [10, 20],
            ),
          );
        }
      };

      await expectLater(
        manager.measureAudioResponse(config),
        throwsStateError,
      );
    });

    test('uses the default protocol chunk size when not overridden', () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );
      final samples = List<int>.generate(119, (index) => index);
      var uploadedSamples = 0;

      bleManager.onWrite = (write) {
        if (write.characteristicId ==
            AudioResponseBleUuids.transferControlCharacteristicUuid) {
          final control = AudioResponseTransferControl.fromBytes(write.bytes);
          bleManager.emitStatus(
            AudioResponseTransferStatus(
              transfer_id: 42,
              status: _controlType(control) == 1 ? 1 : 0,
              next_sample_offset: uploadedSamples,
              credits: 10,
            ),
          );
        } else if (write.characteristicId ==
            AudioResponseBleUuids.transferDataCharacteristicUuid) {
          final chunk = AudioResponseTransferChunk.fromBytes(write.bytes);
          uploadedSamples += chunk.sample_count;
          bleManager.emitStatus(
            AudioResponseTransferStatus(
              transfer_id: 42,
              status: 0,
              next_sample_offset: uploadedSamples,
              credits: 10,
            ),
          );
        }
      };

      await manager.uploadAudioBuffer(
        transferId: 42,
        samples: samples,
        samplingRate: 16000,
      );

      final chunkSizes = bleManager.writes
          .where(
            (write) =>
                write.characteristicId ==
                AudioResponseBleUuids.transferDataCharacteristicUuid,
          )
          .map(
            (write) =>
                AudioResponseTransferChunk.fromBytes(write.bytes).sample_count,
          );
      expect(chunkSizes, [118, 1]);
    });

    test('rejects invalid chunk size before writing transfer start', () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );

      await expectLater(
        manager.uploadAudioBuffer(
          transferId: 42,
          samples: const [0],
          samplingRate: 16000,
          maximumSamplesPerChunk: 0,
        ),
        throwsRangeError,
      );
      expect(bleManager.writes, isEmpty);
    });

    test('aborts a transfer after a protocol error', () async {
      final bleManager = _FakeBleGattManager();
      final manager = OpenEarableV2AudioResponseManager(
        bleManager: bleManager,
        deviceId: 'device',
      );

      bleManager.onWrite = (write) {
        if (write.characteristicId !=
            AudioResponseBleUuids.transferControlCharacteristicUuid) {
          return;
        }
        final control = AudioResponseTransferControl.fromBytes(write.bytes);
        if (_controlType(control) == 0) {
          bleManager.emitStatus(
            AudioResponseTransferStatus(
              transfer_id: 42,
              status: 5,
              next_sample_offset: 0,
              credits: 0,
            ),
          );
        }
      };

      await expectLater(
        manager.uploadAudioBuffer(
          transferId: 42,
          samples: const [0],
          samplingRate: 16000,
        ),
        throwsA(
          isA<AudioResponseTransferException>().having(
            (error) => error.status,
            'status',
            5,
          ),
        ),
      );

      final controls = bleManager.writes
          .where(
            (write) =>
                write.characteristicId ==
                AudioResponseBleUuids.transferControlCharacteristicUuid,
          )
          .map((write) => AudioResponseTransferControl.fromBytes(write.bytes));
      expect(controls.map(_controlType), [0, 2]);
    });
  });
}

int _controlType(AudioResponseTransferControl control) {
  final command = control.command;
  if (command is AudioResponseTransferStart) {
    return 0;
  }
  if (command is AudioResponseTransferCommit) {
    return 1;
  }
  if (command is AudioResponseTransferAbort) {
    return 2;
  }
  throw StateError(
    'Unsupported transfer control command: ${command.runtimeType}',
  );
}

class _FakeBleGattManager implements BleGattManager {
  final _streams = <String, StreamController<List<int>>>{};
  final writes = <_Write>[];

  void Function(_Write write)? onWrite;

  void emitStatus(AudioResponseTransferStatus status) {
    _controller(AudioResponseBleUuids.transferStatusCharacteristicUuid)
        .add(status.toBytes());
  }

  void emitResult(AudioResponseResult result) {
    _controller(
      AudioResponseBleUuids.resultCharacteristicUuid,
    ).add(result.toBytes());
  }

  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
    bool withoutResponse = false,
  }) async {
    final write = _Write(
      characteristicId,
      Uint8List.fromList(byteData),
      withoutResponse,
    );
    writes.add(write);
    onWrite?.call(write);
  }

  @override
  Future<Stream<List<int>>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    return _controller(characteristicId).stream;
  }

  StreamController<List<int>> _controller(String characteristicId) {
    return _streams.putIfAbsent(
      characteristicId,
      () => StreamController<List<int>>.broadcast(sync: true),
    );
  }

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    return true;
  }

  @override
  Future<bool> hasService({
    required String deviceId,
    required String serviceId,
  }) async {
    return true;
  }

  @override
  bool isConnected(String deviceId) => true;

  @override
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    return [];
  }
}

class _Write {
  const _Write(this.characteristicId, this.bytes, this.withoutResponse);

  final String characteristicId;
  final Uint8List bytes;
  final bool withoutResponse;
}
