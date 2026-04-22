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

    test('starts green-only PPG through the realtime PPG command', () async {
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
          cmd: OpenRingGatt.cmdRealTimePpg,
          payload: const <int>[0x00, 0x00, 0x19, 0x01, 0x00, 0x00, 0x01, 0x01],
        ),
      );

      expect(ble.writes, hasLength(1));
      expect(ble.writes.single.byteData[2], OpenRingGatt.cmdRealTimePpg);
      expect(
        ble.writes.single.byteData.sublist(3),
        <int>[0x00, 0x00, 0x19, 0x01, 0x00, 0x00, 0x01, 0x01],
      );
    });

    test('routes realtime PPG samples to the PPG stream', () async {
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
          .subscribeToSensorData(OpenRingGatt.cmdPPGQ2)
          .first
          .timeout(const Duration(seconds: 1));

      await handler.writeSensorConfig(
        OpenRingSensorConfig(
          cmd: OpenRingGatt.cmdRealTimePpg,
          payload: const <int>[0x00, 0x00, 0x19, 0x01, 0x00, 0x00, 0x01, 0x01],
        ),
      );

      parser.nextResult = <Map<String, dynamic>>[
        <String, dynamic>{
          'cmd': OpenRingGatt.cmdRealTimePpg,
          'timestamp': 1234,
          'PPG': <String, dynamic>{'Green': 123456},
          'Accelerometer': <String, dynamic>{'X': 11, 'Y': 22, 'Z': 33},
        },
      ];
      ble.emit(const <int>[0x00, 0x01, 0x3C, 0x02]);

      final emitted = await sampleFuture;
      expect(emitted['cmd'], OpenRingGatt.cmdRealTimePpg);
      expect(emitted['PPG'], <String, dynamic>{
        'Red': 0,
        'Infrared': 0,
        'Green': 123456,
      });
      expect(emitted.containsKey('Accelerometer'), isFalse);
    });

    test(
      'mirrors Q2 IMU payloads to the IMU stream when IMU is enabled',
      () async {
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
            cmd: OpenRingGatt.cmdPPGQ2,
            payload: const <int>[0x00, 0x00, 0x19, 0x01, 0x01],
          ),
        );
        await handler.writeSensorConfig(
          OpenRingSensorConfig(
            cmd: OpenRingGatt.cmdIMU,
            payload: const <int>[0x06],
          ),
        );

        parser.nextResult = <Map<String, dynamic>>[
          <String, dynamic>{
            'cmd': OpenRingGatt.cmdPPGQ2,
            'timestamp': 1234,
            'PPG': <String, dynamic>{'Red': 1, 'Infrared': 2, 'Green': 3},
            'Accelerometer': <String, dynamic>{'X': 11, 'Y': 22, 'Z': 33},
            'Gyroscope': <String, dynamic>{'X': 44, 'Y': 55, 'Z': 66},
          },
        ];
        ble.emit(const <int>[0x00, 0x01, 0x32, 0x02]);

        final emitted = await sampleFuture;
        expect(emitted['cmd'], OpenRingGatt.cmdIMU);
        expect(emitted['sourceCmd'], OpenRingGatt.cmdPPGQ2);
        expect(emitted['Accelerometer'], <String, dynamic>{
          'X': 11,
          'Y': 22,
          'Z': 33,
        });
        expect(emitted['Gyroscope'], <String, dynamic>{
          'X': 44,
          'Y': 55,
          'Z': 66,
        });
      },
    );
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
