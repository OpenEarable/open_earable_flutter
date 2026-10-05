import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/constants.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_factory.dart';
import 'package:universal_ble/universal_ble.dart';

const hardwareUuid = '45622512-6468-465a-b141-0b9b0f96b468';
const firmwareUuid = '45622513-6468-465a-b141-0b9b0f96b468';

class VersionGatt extends Fake implements BleGattManager {
  String firmware = '2.2.9';
  final reads = <String>[];
  final schemes = StreamController<List<int>>.broadcast();
  final data = StreamController<List<int>>.broadcast();
  Completer<void> subscribed = Completer<void>();

  @override
  bool isConnected(String deviceId) => true;

  @override
  Future<bool> hasService({
    required String deviceId,
    required String serviceId,
  }) async =>
      false;

  @override
  Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async =>
      false;

  @override
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    reads.add(characteristicId);
    if (characteristicId == hardwareUuid) return '2.0.1\x00'.codeUnits;
    if (characteristicId == firmwareUuid) return '$firmware\x00'.codeUnits;
    if (characteristicId == sensorListCharacteristicUuid) return [1, 4];
    throw StateError('Unexpected read: $characteristicId');
  }

  @override
  Future<Stream<List<int>>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    if (characteristicId == sensorSchemeCharacteristicUuid) {
      return schemes.stream;
    }
    expect(characteristicId, sensorDataCharacteristicUuid);
    subscribed.complete();
    return data.stream;
  }

  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
    bool withoutResponse = false,
  }) async {
    expect(characteristicId, requestSensorSchemeCharacteristicUuid);
    List<int> text(String s) => [s.length, ...s.codeUnits];
    schemes.add([
      4, ...text('PPG'), 4,
      for (final axis in ['RED', 'IR', 'GREEN', 'AMBIENT']) ...[
        5,
        ...text('PPG'),
        ...text(axis),
        ...text('ADC'),
      ],
      1, // Streaming, with no optional frequency table.
    ]);
  }
}

void main() {
  test('real factory selects transport from firmware and refreshes after FOTA',
      () async {
    final ble = VersionGatt();
    addTearDown(ble.schemes.close);
    addTearDown(ble.data.close);
    final factory = OpenEarableFactory()
      ..bleManager = ble
      ..disconnectNotifier = WearableDisconnectNotifier();
    final device = DiscoveredDevice(
      id: 'ear',
      name: 'Ear',
      manufacturerData: Uint8List(0),
      rssi: -40,
      serviceUuids: [],
    );
    for (final version in ['2.2.9', '2.3.0', '2.3.0-dev.91+gabc', '2.2.9']) {
      ble.firmware = version;
      ble.reads.clear();
      ble.subscribed = Completer<void>();
      expect(
        await factory.matches(device, [
          BleService(
            OpenEarableV2.deviceInfoServiceUuid,
            [],
          ),
        ]),
        isTrue,
      );
      final wearable = await factory.createFromDevice(device);
      expect(ble.reads, contains(firmwareUuid));
      expect(
        wearable.hasCapability<LedStateReader>(),
        version.startsWith('2.3.'),
      );
      final sensor = wearable.requireCapability<SensorManager>().sensors.single;
      expect(sensor.axisUnits, ['ADC', 'ADC', 'ADC', 'ADC']);
      final value = sensor.sensorStream.first;
      await ble.subscribed.future;
      await Future<void>.delayed(Duration.zero);
      final compact = version.startsWith('2.3.');
      final sample = compact
          ? [1, 0, 16, 0, 192, 0, 0, 8, 0, 0]
          : [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0];
      ble.data.add([4, sample.length, 123, 0, 0, 0, 0, 0, 0, 0, ...sample]);
      final parsed =
          await value.timeout(const Duration(seconds: 2)) as SensorDoubleValue;
      expect(parsed.values, [1.0, 2.0, 3.0, 4.0]);
      expect(parsed.timestamp, 123);
    }
  });
}
