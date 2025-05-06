import 'dart:async';

import '../capabilities/device_firmware_version.dart';
import '../capabilities/device_hardware_version.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_manager.dart';
import '../../managers/ble_manager.dart';
import 'discovered_device.dart';
import 'wearable.dart';

class Polar extends Wearable
    implements SensorManager, DeviceFirmwareVersion, DeviceHardwareVersion {
  static const disServiceUuid = "0000180a-0000-1000-8000-00805f9b34fb";
  static const heartRateServiceUuid = "0000180D-0000-1000-8000-00805f9b34fb";

  final List<Sensor> _sensors;
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  Polar({
    required super.name,
    required super.disconnectNotifier,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
    required List<Sensor> sensors,
  })  : _sensors = sensors,
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice;

  @override
  String? getWearableIconPath({bool darkmode = false}) {
    String basePath =
        'packages/open_earable_flutter/assets/wearable_icons/polar';

    if (_discoveredDevice.name.contains("Unite") ||
        _discoveredDevice.name.contains("Ignite") ||
        _discoveredDevice.name.contains("Vantage") ||
        _discoveredDevice.name.contains("Pacer")) {
      basePath += '/watch';
    } else if (_discoveredDevice.name.contains("H9") ||
        _discoveredDevice.name.contains("H10")) {
      basePath += '/strap_sensor';
    } else {
      basePath += '/default';
    }

    if (darkmode) {
      return '$basePath/icon_white.svg';
    }
    return '$basePath/icon.svg';
  }

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);

  /// Reads the device firmware version from the connected Polar device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceFirmwareVersion() async {
    List<int> deviceGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: Polar.disServiceUuid,
      characteristicId: '00002a28-0000-1000-8000-00805f9b34fb',
    );

    // End string after non-printable chars
    String firmwareVersion = '';
    for (int b in deviceGenerationBytes) {
      if (b >= 32 && b < 127) {
        firmwareVersion += String.fromCharCode(b);
      } else {
        break;
      }
    }

    return firmwareVersion;
  }

  /// Reads the device hardware version from the connected Polar device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceHardwareVersion() async {
    List<int> hardwareGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: Polar.disServiceUuid,
      characteristicId: "00002a27-0000-1000-8000-00805f9b34fb",
    );

    // End string after non-printable chars (and some braces, for Polar Unite)
    String hardwareVersion = '';
    for (int b in hardwareGenerationBytes) {
      if (b >= 33 && b <= 122) {
        hardwareVersion += String.fromCharCode(b);
      } else {
        break;
      }
    }

    return hardwareVersion;
  }
}
