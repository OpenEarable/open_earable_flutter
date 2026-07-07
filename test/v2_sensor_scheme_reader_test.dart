import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/constants.dart';
import 'package:open_earable_flutter/src/managers/ble_gatt_manager.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/v2_sensor_scheme_reader.dart';

void main() {
  test(
    'waits for notification subscription before requesting a v2 scheme',
    () async {
      final bleManager = _FakeBleGattManager();
      final reader = V2SensorSchemeReader(bleManager, 'device-1');

      final schemes = await reader.readSensorSchemes();

      expect(schemes, hasLength(1));
      expect(schemes.single.sensorId, 7);
      expect(schemes.single.sensorName, 'IMU');
      expect(
        bleManager.events,
        containsAllInOrder([
          'read:sensor-list',
          'prepare:scheme',
          'subscribe:scheme',
          'write:7',
        ]),
      );
    },
  );

  test(
    'falls back to direct read when the notification path times out',
    () async {
      final bleManager = _FakeBleGattManager(deliverNotification: false);
      final reader = V2SensorSchemeReader(bleManager, 'device-1');

      final scheme = await reader.getSchemeForSensor(7);

      expect(scheme.sensorId, 7);
      expect(scheme.sensorName, 'IMU');
      expect(
        bleManager.events,
        containsAllInOrder([
          'read:sensor-list',
          'prepare:scheme',
          'subscribe:scheme',
          'write:7',
          'read:scheme',
        ]),
      );
    },
  );

  test(
    'keeps the returned sensor id on direct-read fallback',
    () async {
      final bleManager = _FakeBleGattManager(
        deliverNotification: false,
        sensorIds: const [0, 5],
        directReadResponses: <List<int>>[
          _schemeBytes(sensorId: 0, name: 'IMU'),
        ],
      );
      final reader = V2SensorSchemeReader(bleManager, 'device-1');

      final scheme = await reader.getSchemeForSensor(5);

      expect(scheme.sensorId, 0);
      expect(scheme.sensorName, 'IMU');
      expect(bleManager.events, containsAllInOrder(['write:5', 'read:scheme']));
    },
  );

  test(
    'retries passes until all schemes are collected',
    () async {
      final bleManager = _FakeBleGattManager(
        deliverNotification: false,
        sensorIds: const [0, 4, 5],
        directReadResponses: <List<int>>[
          _schemeBytes(sensorId: 0, name: 'IMU'),
          _schemeBytes(sensorId: 0, name: 'IMU'),
          _schemeBytes(sensorId: 4, name: 'PPG'),
          _schemeBytes(sensorId: 5, name: 'BARO'),
        ],
      );
      final reader = V2SensorSchemeReader(bleManager, 'device-1');

      final schemes = await reader.readSensorSchemes();

      expect(schemes.map((scheme) => scheme.sensorId).toSet(), {0, 4, 5});
      expect(
        bleManager.events.where((event) => event.startsWith('write:')).length,
        greaterThan(3),
      );
    },
  );
}

class _FakeBleGattManager extends BleGattManager {
  _FakeBleGattManager({
    this.deliverNotification = true,
    this.sensorIds = const [7],
    List<List<int>>? directReadResponses,
  }) : _directReadResponses =
            directReadResponses ?? <List<int>>[_imuSchemeBytes];

  final List<String> events = [];
  final StreamController<List<int>> _schemeController =
      StreamController<List<int>>.broadcast();
  final bool deliverNotification;
  final List<int> sensorIds;
  final List<List<int>> _directReadResponses;
  int _directReadIndex = 0;
  int? lastRequestedSensorId;

  bool _prepared = false;

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
  Future<void> prepareSubscription({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    expect(serviceId, parseInfoServiceUuid);
    expect(characteristicId, sensorSchemeCharacteristicUuid);
    events.add('prepare:scheme');
    _prepared = true;
  }

  @override
  Stream<List<int>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) {
    expect(serviceId, parseInfoServiceUuid);
    expect(characteristicId, sensorSchemeCharacteristicUuid);
    events.add('subscribe:scheme');
    return _schemeController.stream;
  }

  @override
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    expect(serviceId, parseInfoServiceUuid);
    if (characteristicId == sensorListCharacteristicUuid) {
      events.add('read:sensor-list');
      return [sensorIds.length, ...sensorIds];
    }
    expect(characteristicId, sensorSchemeCharacteristicUuid);
    events.add('read:scheme');
    final index = _directReadIndex < _directReadResponses.length
        ? _directReadIndex++
        : _directReadResponses.length - 1;
    return _directReadResponses[index];
  }

  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
  }) async {
    expect(_prepared, isTrue);
    expect(serviceId, parseInfoServiceUuid);
    expect(characteristicId, requestSensorSchemeCharacteristicUuid);
    expect(byteData, hasLength(1));
    lastRequestedSensorId = byteData.single;
    events.add('write:${byteData.single}');
    if (deliverNotification) {
      Future.microtask(() => _schemeController.add(_imuSchemeBytes));
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {}
}

final List<int> _imuSchemeBytes = [7, 3, ...'IMU'.codeUnits, 0, 0];

List<int> _schemeBytes({
  required int sensorId,
  required String name,
}) {
  return [sensorId, name.length, ...name.codeUnits, 0, 0];
}
