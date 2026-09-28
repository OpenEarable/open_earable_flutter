import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/constants.dart';
import 'package:open_earable_flutter/src/managers/ble_gatt_manager.dart';
import 'package:open_earable_flutter/src/managers/v2_sensor_handler.dart';
import 'package:open_earable_flutter/src/models/devices/discovered_device.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/v2_sensor_value_parser.dart';

class _Ble implements BleGattManager {
  final bool compact;
  _Ble(this.compact) { data.onCancel = () { cancellations++; }; }
  int cancellations = 0;
  final data = StreamController<List<int>>.broadcast();
  String? subscribed;
  @override
  bool isConnected(String deviceId) => true;
  @override
  Future<bool> hasCharacteristic({required String deviceId, required String serviceId, required String characteristicId}) async => compact;
  @override
  Future<List<int>> read({required String deviceId, required String serviceId, required String characteristicId}) async => [1];
  @override
  Future<Stream<List<int>>> subscribe({required String deviceId, required String serviceId, required String characteristicId}) async {
    subscribed = characteristicId;
    return data.stream;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Schemes implements SensorSchemeReader {
  final scheme = SensorScheme(0, 'IMU', 9, null)
    ..components.addAll(List.generate(9, (i) => Component(ParseType.float, 'group', 'axis$i', 'unit')));
  @override
  Future<List<SensorScheme>> readSensorSchemes({bool forceRead = false}) async => [scheme];
  @override
  Future<SensorScheme> getSchemeForSensor(int sensorId) async => scheme;
}

void main() {
  for (final compact in [false, true]) {
    test('subscription routes ${compact ? "compact" : "legacy"} IMU notifications to sensor 0', () async {
      final ble = _Ble(compact);
      final handler = V2SensorHandler(
        discoveredDevice: DiscoveredDevice(id: 'earable', name: 'Earable', manufacturerData: Uint8List(0), rssi: -40, serviceUuids: []),
        bleManager: ble,
        sensorSchemeParser: _Schemes(),
        sensorValueParser: V2SensorValueParser(),
      );
      final stream = await handler.subscribeToSensorData(0);
      expect(ble.cancellations, compact ? 1 : 0);
      final result = stream.first.timeout(const Duration(seconds: 1));
      expect(ble.subscribed, compact ? sensorCompactDataCharacteristicUuid : sensorDataCharacteristicUuid);
      final bytes = ByteData(compact ? 34 : 46);
      bytes.setUint8(0, compact ? 0x80 : 0);
      bytes.setUint8(1, bytes.lengthInBytes - 10);
      bytes.setUint64(2, 123456789, Endian.little);
      if (compact) {
        bytes.setInt16(10, -32768, Endian.little);
      } else {
        bytes.setFloat32(10, -19.6133, Endian.little);
      }
      ble.data.add(bytes.buffer.asUint8List());
      final sample = await result;
      expect(sample['sensorId'], 0);
      expect(sample['timestamp'], 123456789);
      expect(sample['group']['axis0'], closeTo(-19.6133, 0.00001));
      await ble.data.close();
    });
  }
}
