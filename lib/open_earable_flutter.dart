library open_earable_flutter;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:open_earable_flutter/src/models/devices/cosinuss_one_factory.dart';
import 'package:open_earable_flutter/src/models/devices/devkit_factory.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_factory.dart';
import 'package:open_earable_flutter/src/models/devices/polar_factory.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';

import 'src/managers/ble_manager.dart';
import 'src/managers/notifier.dart';
import 'src/models/devices/discovered_device.dart';
import 'src/models/devices/wearable.dart';

export 'src/models/devices/discovered_device.dart';
export 'src/models/devices/wearable.dart';
export 'src/models/capabilities/device_firmware_version.dart';
export 'src/models/capabilities/device_hardware_version.dart';
export 'src/models/capabilities/device_identifier.dart';
export 'src/models/capabilities/battery_level.dart';
export 'src/models/capabilities/battery_level_status.dart';
export 'src/models/capabilities/battery_health_status.dart';
export 'src/models/capabilities/battery_energy_status.dart';
export 'src/models/capabilities/rgb_led.dart';
export 'src/models/capabilities/status_led.dart';
export 'src/models/capabilities/sensor.dart';
export 'src/models/capabilities/sensor_configuration.dart';
export 'src/models/capabilities/sensor_manager.dart';
export 'src/models/capabilities/sensor_configuration_manager.dart';
export 'src/models/capabilities/frequency_player.dart';
export 'src/models/capabilities/jingle_player.dart';
export 'src/models/capabilities/audio_player_controls.dart';
export 'src/models/capabilities/storage_path_audio_player.dart';
export 'src/managers/firmware_update_manager.dart';

Logger logger = Logger();

class WearableManager {
  static final WearableManager _instance = WearableManager._internal();

  late final BleManager _bleManager;

  final List<WearableFactory> _wearableFactories = [
    OpenEarableFactory(),
    CosinussOneFactory(),
    PolarFactory(),
    DevKitFactory(),
  ];

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

  void addWearableFactory(WearableFactory factory) {
    _wearableFactories.add(factory);
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
      for (WearableFactory wearableFactory in _wearableFactories) {
        wearableFactory.bleManager = _bleManager;
        wearableFactory.disconnectNotifier = disconnectNotifier;
        logger.t("checking factory: $wearableFactory");
        if (await wearableFactory.matches(device, connectionResult.$2)) {
          Wearable wearable = await wearableFactory.createFromDevice(device);
          return wearable;
        } else {
          logger.d("'$wearableFactory' does not support '$device'");
        }
      }
      throw Exception('Device is currently not supported');
    } else {
      throw Exception('Failed to connect to device');
    }
  }
}
