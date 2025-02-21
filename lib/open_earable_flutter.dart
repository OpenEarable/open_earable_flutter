library open_earable_flutter;

import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'src/managers/ble_manager.dart';
import 'src/managers/notifier.dart';
import 'src/models/devices/cosinuss_one.dart';
import 'src/models/devices/discovered_device.dart';
import 'src/models/devices/polar.dart';
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
export 'src/managers/firmware_update_manager.dart';

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
      if (device.name.startsWith("Polar")) {
        return Polar(
          name: device.name,
          disconnectNotifier: disconnectNotifier,
          bleManager: _bleManager,
          discoveredDevice: device,
        );
      }

      if (device.name == "earconnect") {
        return CosinussOne(
          name: device.name,
          disconnectNotifier: disconnectNotifier,
          bleManager: _bleManager,
          discoveredDevice: device,
        );
      }

      return OpenEarableV1(
        name: device.name,
        disconnectNotifier: disconnectNotifier,
        bleManager: _bleManager,
        discoveredDevice: device,
      );
    } else {
      throw Exception('Failed to connect to device');
    }
  }
}
