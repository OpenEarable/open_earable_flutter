import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/open_ring_sensor_handler.dart';
import 'package:open_earable_flutter/src/models/devices/open_ring.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/sensor_value_parser.dart';

void main() {
  group('OpenRingSensorHandler', () {
    test('starts direct IMU streaming without forcing PPG transport', () async {
      final ble = _FakeBleGattManager();
      final parser = _StubSensorValueParser();
      final handler = OpenRingSensorHandler(
        discoveredDevice: DiscoveredDevice(
          id: 'ring-1',
          name: 'OpenRing',
          manufacturerData: Uint8List(0),
          rssi: -42,
          serviceUuids: <String>[OpenRingGatt.service],
        ),
        bleManager: ble,
        sensorValueParser: parser,
      );

      await handler.writeSensorConfig(
        OpenRingSensorConfig(
          cmd: OpenRingGatt.cmdIMU,
          payload: const <int>[0x06],
        ),
      );

      expect(ble.writes, hasLength(1));
      expect(ble.writes.single.byteData[2], OpenRingGatt.cmdIMU);
      expect(ble.writes.single.byteData.last, 0x06);
    });

    test('emits direct IMU samples on the IMU stream', () async {
      final ble = _FakeBleGattManager();
      final parser = _StubSensorValueParser();
      final handler = OpenRingSensorHandler(
        discoveredDevice: DiscoveredDevice(
          id: 'ring-1',
          name: 'OpenRing',
          manufacturerData: Uint8List(0),
          rssi: -42,
          serviceUuids: <String>[OpenRingGatt.service],
        ),
        bleManager: ble,
        sensorValueParser: parser,
      );

      final sampleFuture = handler
          .subscribeToSensorData(OpenRingGatt.cmdIMU)
          .first
          .timeout(const Duration(seconds: 1));

      await handler.writeSensorConfig(
        OpenRingSensorConfig(
          cmd: OpenRingGatt.cmdIMU,
          payload: const <int>[0x06],
        ),
      );

      parser.nextResult = <Map<String, dynamic>>[
        <String, dynamic>{
          'cmd': OpenRingGatt.cmdIMU,
          'timestamp': 1234,
          'Accelerometer': <String, dynamic>{'X': 11, 'Y': 22, 'Z': 33},
        },
      ];
      ble.emit(const <int>[0x00, 0x01, 0x40, 0x06]);

      final emitted = await sampleFuture;
      expect(emitted['cmd'], OpenRingGatt.cmdIMU);
      expect(emitted['Accelerometer'], <String, dynamic>{
        'X': 11,
        'Y': 22,
        'Z': 33,
      });
    });
  });
}

class _StubSensorValueParser extends SensorValueParser {
  List<Map<String, dynamic>> nextResult = const <Map<String, dynamic>>[];

  @override
  List<Map<String, dynamic>> parse(
    ByteData data,
    List<SensorScheme> sensorSchemes,
  ) {
    return List<Map<String, dynamic>>.from(nextResult);
  }
}

class _FakeBleGattManager implements BleGattManager {
  final StreamController<List<int>> _streamController =
      StreamController<List<int>>.broadcast();
  final List<_WriteCall> writes = <_WriteCall>[];

  void emit(List<int> packet) {
    _streamController.add(packet);
  }

  @override
  bool isConnected(String deviceId) => true;

  @override
  Future<bool> hasService({
    required String deviceId,
    required String serviceId,
  }) async {
    return true;
  }

  @override
  Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    return true;
  }

  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
  }) async {
    writes.add(
      _WriteCall(
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        byteData: List<int>.from(byteData),
      ),
    );
  }

  @override
  Stream<List<int>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) {
    return _streamController.stream;
  }

  @override
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    return const <int>[];
  }

  @override
  Future<void> disconnect(String deviceId) async {}
}

class _WriteCall {
  const _WriteCall({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required this.byteData,
  });

  final String deviceId;
  final String serviceId;
  final String characteristicId;
  final List<int> byteData;
}
