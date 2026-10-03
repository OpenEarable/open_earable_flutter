import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/models/devices/battery_gatt_reader/battery_health_status_gatt_reader.dart';
import 'package:open_earable_flutter/src/models/devices/battery_gatt_reader/battery_level_status_service_gatt_reader.dart';
import 'package:open_earable_flutter/src/models/devices/bluetooth_wearable.dart';

void main() {
  test('decodes captured charged-ear payload and cycle count', () async {
    final reader = _Reader(_Gatt([0, 0xe3, 0]));
    final status = await reader.readPowerStatus();
    expect(status.batteryPresent, isTrue);
    expect(status.wiredExternalPowerSourceConnected,
        ExternalPowerSourceConnected.yes,);
    expect(status.wirelessExternalPowerSourceConnected,
        ExternalPowerSourceConnected.no,);
    expect(status.chargeState, ChargeState.dischargingInactive);
    expect(status.chargeLevel, BatteryChargeLevel.good);
    expect(status.chargingType, BatteryChargingType.unknown);
    expect(status.chargingFaultReason, isEmpty);
    final health = await _Reader(_Gatt([7, 100, 1, 0, 29])).readHealthStatus();
    expect(health.cycleCount, 1);
  });

  test('decodes independent power-state fields and all fault bits', () async {
    final status = await _Reader(_Gatt([0, 0x55, 0x79])).readPowerStatus();
    expect(status.batteryPresent, isTrue);
    expect(status.wiredExternalPowerSourceConnected,
        ExternalPowerSourceConnected.unknown,);
    expect(status.wirelessExternalPowerSourceConnected,
        ExternalPowerSourceConnected.unknown,);
    expect(status.chargeState, ChargeState.dischargingActive);
    expect(status.chargingType, BatteryChargingType.float);
    expect(status.chargingFaultReason, ChargingFaultReason.values);
  });

  test('reserved enum values are unknown, not out-of-range accesses', () async {
    final status = await _Reader(_Gatt([0, 0x1e, 0x0e])).readPowerStatus();
    expect(status.wiredExternalPowerSourceConnected,
        ExternalPowerSourceConnected.unknown,);
    expect(status.wirelessExternalPowerSourceConnected,
        ExternalPowerSourceConnected.unknown,);
    expect(status.chargingType, BatteryChargingType.unknown);
  });

  test('rejects truncated power status', () async {
    await expectLater(
        _Reader(_Gatt([0, 0xe3])).readPowerStatus(), throwsStateError,);
  });
}

class _Gatt implements BleGattManager {
  _Gatt(this.bytes);
  final List<int> bytes;
  @override
  Future<List<int>> read(
          {required String deviceId,
          required String serviceId,
          required String characteristicId,}) async =>
      bytes;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reader extends BluetoothWearable
    with BatteryLevelStatusServiceGattReader, BatteryHealthStatusGattReader {
  _Reader(BleGattManager manager)
      : super(
            name: 'ear',
            bleManager: manager,
            disconnectNotifier: WearableDisconnectNotifier(),
            discoveredDevice: DiscoveredDevice(
                id: 'ear',
                name: 'ear',
                manufacturerData: Uint8List(0),
                rssi: -40,
                serviceUuids: [],),);
  @override
  String get deviceId => 'ear';
  @override
  Future<void> disconnect() async {}
}
