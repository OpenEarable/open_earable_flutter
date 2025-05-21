library open_earable_flutter;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:open_earable_flutter/src/models/devices/cosinuss_one_factory.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_factory.dart';
import 'package:open_earable_flutter/src/models/devices/polar_factory.dart';
import 'package:open_earable_flutter/src/models/devices/devkit_factory.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';

import 'src/managers/ble_manager.dart';
import 'src/managers/wearable_disconnect_notifier.dart';
import 'src/models/devices/discovered_device.dart';
import 'src/models/devices/wearable.dart';

export 'src/models/devices/discovered_device.dart';
export 'src/models/devices/wearable.dart';
export 'src/models/devices/cosinuss_one.dart';
export 'src/models/devices/open_earable_v1.dart';
export 'src/models/devices/open_earable_v2.dart';
export 'src/models/devices/polar.dart';

export 'src/managers/wearable_disconnect_notifier.dart';

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
export 'src/models/capabilities/sensor_specializations/heart_rate_sensor.dart';
export 'src/models/capabilities/sensor_specializations/heart_rate_variability_sensor.dart';
export 'src/models/capabilities/sensor_configuration.dart';
export 'src/models/capabilities/sensor_configuration_specializations/sensor_frequency_configuration.dart';
export 'src/models/capabilities/sensor_configuration_specializations/configurable_sensor_configuration.dart';
export 'src/models/capabilities/sensor_configuration_specializations/recordable_sensor_configuration.dart';
export 'src/models/capabilities/sensor_configuration_specializations/streamable_sensor_configuration.dart';
export 'src/models/capabilities/sensor_manager.dart';
export 'src/models/capabilities/sensor_configuration_manager.dart';
export 'src/models/capabilities/frequency_player.dart';
export 'src/models/capabilities/jingle_player.dart';
export 'src/models/capabilities/audio_player_controls.dart';
export 'src/models/capabilities/storage_path_audio_player.dart';
export 'src/models/capabilities/audio_mode_manager.dart';
export 'src/models/capabilities/microphone_manager.dart';

export 'src/fota/fota.dart';

@Deprecated(
    'This export is deprecated and will be removed in a future release.')
export 'src/models/capabilities/sensor_configuration_specializations/sensor_configuration_open_earable_v2.dart';

Logger logger = Logger();

class WearableManager {
  static final WearableManager _instance = WearableManager._internal();

  late final BleManager _bleManager;

  late final StreamController<Wearable> _connectStreamController;
  late final StreamController<DiscoveredDevice> _connectingStreamController;

  final List<String> _connectedIds = [];

  List<String> _autoConnectDeviceIds = [];
  StreamSubscription<DiscoveredDevice>? _autoconnectScanSubscription;

  bool? _scanExcludeUnsupported;

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
    _connectStreamController = StreamController<Wearable>.broadcast();
    _connectingStreamController =
        StreamController<DiscoveredDevice>.broadcast();

    _bleManager = BleManager();
    _init();
  }

  void _init() {
    logger.i('WearableManager initialized');
  }

  void addWearableFactory(WearableFactory factory) {
    _wearableFactories.add(factory);
  }

  Future<void> startScan({
    bool excludeUnsupported = false,
    bool checkAndRequestPermissions = true,
  }) {
    _scanExcludeUnsupported = excludeUnsupported;
    return _bleManager.startScan(
      filterByServices: excludeUnsupported,
      checkAndRequestPermissions: checkAndRequestPermissions,
    );
  }

  Stream<DiscoveredDevice> get scanStream => _bleManager.scanStream;

  Stream<Wearable> get connectStream => _connectStreamController.stream;

  Stream<DiscoveredDevice> get connectingStream =>
      _connectingStreamController.stream;

  Future<Wearable> connectToDevice(DiscoveredDevice device) async {
    _connectingStreamController.add(device);

    WearableDisconnectNotifier disconnectNotifier =
        WearableDisconnectNotifier();
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

          _connectedIds.add(device.id);
          wearable.addDisconnectListener(() {
            _connectedIds.remove(device.id);
          });

          _connectStreamController.add(wearable);
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

  void setAutoConnect(List<String> deviceIds) {
    _autoConnectDeviceIds = deviceIds;
    if (deviceIds.isEmpty) {
      _autoconnectScanSubscription?.cancel();
      _autoconnectScanSubscription = null;
    } else {
      _autoconnectScanSubscription ??=
          scanStream.listen((discoveredDevice) async {
        if (_autoConnectDeviceIds.contains(discoveredDevice.id) &&
            !_connectedIds.contains(discoveredDevice.id)) {
          try {
            await connectToDevice(discoveredDevice);
          } catch (e) {
            logger.e('Error auto connecting device ${discoveredDevice.id}: $e');
          }
        }
      });

      if (_scanExcludeUnsupported == null) {
        startScan();
      } else {
        startScan(excludeUnsupported: _scanExcludeUnsupported!);
      }
    }
  }

  void dispose() {
    _autoconnectScanSubscription?.cancel();
    _bleManager.dispose();
  }

  static Future<bool> checkAndRequestPermissions() {
    return BleManager.checkAndRequestPermissions();
  }
}
