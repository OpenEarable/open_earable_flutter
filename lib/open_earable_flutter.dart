library open_earable_flutter;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2.dart';
import 'package:universal_ble/universal_ble.dart';

import 'src/managers/ble_manager.dart';
import 'src/managers/notifier.dart';
import 'src/models/devices/discovered_device.dart';
import 'src/models/devices/wearable.dart';

import 'src/models/devices/open_earable_v1.dart';
export 'src/models/devices/discovered_device.dart';
export 'src/models/devices/wearable.dart';
export 'src/models/capabilities/device_firmware_version.dart';
export 'src/models/capabilities/device_hardware_version.dart';
export 'src/models/capabilities/device_identifier.dart';
export 'src/models/capabilities/rgb_led.dart';
export 'src/models/capabilities/sensor.dart';
export 'src/models/capabilities/sensor_configuration.dart';
export 'src/models/capabilities/sensor_manager.dart';
export 'src/models/capabilities/sensor_configuration_manager.dart';
export 'src/models/capabilities/frequency_player.dart';
export 'src/models/capabilities/jingle_player.dart';
export 'src/models/capabilities/audio_player_controls.dart';
export 'src/models/capabilities/storage_path_audio_player.dart';

part 'src/constants.dart';

Logger _logger = Logger();

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";

class WearableManager {
  static final WearableManager _instance = WearableManager._internal();

  late final BleManager _bleManager;

  factory WearableManager() {
    return _instance;
  }

  WearableManager._internal() {
    _bleManager = BleManager();
    _init();
  }

  void _init() {
    print('WearableManager initialized');
  }

  Future<void> startScan() {
    return _bleManager.startScan();
  }

  Stream<DiscoveredDevice> get scanStream => _bleManager.scanStream;

  Future<Wearable> connectToDevice(DiscoveredDevice device) async {
    Notifier disconnectNotifier = Notifier();
    (bool, List<BleService>) connectionResult =
        await _bleManager.connectToDevice(
      device,
      disconnectNotifier.notifyListeners,
    );
    if (connectionResult.$1) {
      _logger.d("found following BLEServices: ${connectionResult.$2}");

      if (connectionResult.$2.any((service) => service.uuid == _deviceInfoServiceUuid)) {
        List<int> softwareGenerationBytes = await _bleManager.read(
          deviceId: device.id,
          serviceId: _deviceInfoServiceUuid,
          characteristicId: _deviceFirmwareVersionCharacteristicUuid,
        );
        String softwareVersion = String.fromCharCodes(softwareGenerationBytes);
        _logger.i("Softare version: $softwareVersion");

        final versionRegex = RegExp(r'^\d+\.\d+\.\d+$');
        if (!versionRegex.hasMatch(softwareVersion)) {
          throw Exception('Invalid software version format');
        }

        final version1Regex = RegExp(r'^1\.\d+\.\d+$');
        if (version1Regex.hasMatch(softwareVersion)) {
          return OpenEarableV1(
            name: device.name,
            disconnectNotifier: disconnectNotifier,
            bleManager: _bleManager,
            discoveredDevice: device,
          );
        }

        final v2Regex = RegExp(r'^\d+\.\d+.\d+$');
        if (v2Regex.hasMatch(softwareVersion)) {
          return OpenEarableV2(
            name: device.name,
            disconnectNotifier: disconnectNotifier,
            bleManager: _bleManager,
            discoveredDevice: device,
          );
        }

        throw Exception('Unsupported Firmware Version');
      } else {
        throw Exception('Unsupported Device');
      }
    } else {
      throw Exception('Failed to connect to device');
    }
  }
}
