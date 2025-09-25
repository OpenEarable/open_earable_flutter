library open_earable_flutter;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:open_earable_flutter/src/models/devices/cosinuss_one_factory.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_factory.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2.dart';
import 'package:open_earable_flutter/src/models/devices/polar_factory.dart';
import 'package:open_earable_flutter/src/models/devices/devkit_factory.dart';
import 'package:open_earable_flutter/src/models/devices/stereo_pairing/pairing_rule.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';

import 'src/managers/ble_manager.dart';
import 'src/managers/pairing_manager.dart';
import 'src/managers/wearable_disconnect_notifier.dart';
import 'src/models/capabilities/stereo_device.dart';
import 'src/models/devices/discovered_device.dart';
import 'src/models/devices/wearable.dart';

export 'src/models/devices/discovered_device.dart';
export 'src/models/devices/wearable.dart';
export 'src/models/devices/cosinuss_one.dart';
export 'src/models/devices/open_earable_v1.dart';
export 'src/models/devices/open_earable_v2.dart';
export 'src/models/devices/polar.dart';

export 'src/managers/wearable_disconnect_notifier.dart';

export 'src/models/capabilities/device_firmware_version.dart' hide DeviceFirmwareVersionNumberExt;
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
export 'src/models/capabilities/stereo_device.dart';
export 'src/models/recorder.dart';
export 'src/models/devices/stereo_pairing/pairing_rule.dart';
export 'src/models/capabilities/edge_recorder_manager.dart';
export 'src/models/capabilities/button_manager.dart';
export 'src/models/wearable_factory.dart';
export 'src/managers/ble_gatt_manager.dart';

export 'src/models/capabilities/version_number.dart';

export 'src/fota/fota.dart';

@Deprecated(
  'This export is deprecated and will be removed in a future release.',
)
export 'src/models/capabilities/sensor_configuration_specializations/sensor_configuration_open_earable_v2.dart';

Logger logger = Logger();

/// WearableManager is a singleton class that manages the connection and interaction
/// with wearable devices using Bluetooth Low Energy (BLE).
/// It provides methods to start scanning for devices,
/// connect to them, and manage connected wearables.
/// It also allows adding custom wearable factories for device support.
class WearableManager {
  static final WearableManager _instance = WearableManager._internal();

  late final BleManager _bleManager;
  final PairingManager _pairingManager = PairingManager(rules: [
    OpenEarableV2PairingRule(),
  ],);

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

  /// Checks if the device has the necessary permissions for BLE operations.
  /// Returns a Future that completes with a boolean indicating whether the permissions
  /// are granted or not.
  Future<bool> hasPermissions() async {
    return await BleManager.checkPermissions();
  }

  /// Adds a wearable factory to the manager.
  /// Wearable factories are used to create wearable instances based on the connected devices.
  /// This allows the manager to support multiple types of wearables.
  /// /// Example usage:
  /// ```dart
  /// WearableManager().addWearableFactory(MyCustomWearableFactory());
  /// ```
  void addWearableFactory(WearableFactory factory) {
    _wearableFactories.add(factory);
  }

  /// Starts scanning for BLE devices.
  /// If `excludeUnsupported` is true, it will filter out devices that do not support
  /// the required services.
  /// If `checkAndRequestPermissions` is true, it will check and request the necessary
  /// permissions before starting the scan.
  /// Returns a Future that completes when the scan starts.
  /// 
  /// The discovered devices can be listened to via the [scanStream].
  /// 
  /// Example usage:
  /// ```dart
  /// await WearableManager().startScan(excludeUnsupported: true);
  /// ```
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

  /// A stream that emits discovered devices during the scan.
  Stream<DiscoveredDevice> get scanStream => _bleManager.scanStream;

  /// A stream that emits connected wearables.
  /// This stream is updated when a device is successfully connected.
  Stream<Wearable> get connectStream => _connectStreamController.stream;

  /// A stream that emits devices that are currently being connected.
  /// This stream is useful for tracking the connection process of devices.
  /// It emits a [DiscoveredDevice] when a connection attempt is made.
  Stream<DiscoveredDevice> get connectingStream =>
      _connectingStreamController.stream;

  /// Connects to a discovered device and returns a [Wearable] instance.
  /// It checks all registered wearable factories to find a matching one for the device.
  /// If a matching factory is found, it creates a wearable instance and adds it to the
  /// connected wearables list.
  /// If the device is not supported by any factory, it throws an exception.
  /// If the connection fails, it also throws an exception.
  Future<Wearable> connectToDevice(DiscoveredDevice device, { Set<ConnectionOption> options = const {}}) async {
    if (_connectedIds.contains(device.id)) {
      logger.w('Device ${device.id} is already connected');
      throw Exception('Device is already connected');
    }
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
      _connectedIds.remove(device.id);
      await _bleManager.disconnect(device.id);
      throw Exception('Device is currently not supported');
    } else {
      throw Exception('Failed to connect to device');
    }
  }

  /// Connects to all wearables that are currently discovered in the system.
  /// It retrieves the system devices and attempts to connect to each one.
  /// Returns a list of successfully connected wearables.
  Future<List<Wearable>> connectToSystemDevices({List<String> ignoredDeviceIds = const []}) async {
    List<DiscoveredDevice> systemDevices =
        await _bleManager.getSystemDevices(filterByServices: true);
    List<Wearable> connectedWearables = [];
    for (DiscoveredDevice device in systemDevices) {
      if (_connectedIds.contains(device.id) || ignoredDeviceIds.contains(device.id)) {
        continue;
      }
      try {
        Wearable wearable = await connectToDevice(device);
        connectedWearables.add(wearable);
      } catch (e) {
        logger.e('Failed to connect to system device ${device.id}: $e');
      }
    }
    return connectedWearables;
  }

  void addPairingRule(PairingRule rule) {
    _pairingManager.addRule(rule);
  }

  /// Finds valid pairs of stereo devices based on the defined pairing rules.
  Future<Map<StereoDevice, List<StereoDevice>>> findValidPairs(List<StereoDevice> devices) async {
    return await _pairingManager.findValidPairs(devices);
  }

  Future<List<StereoDevice>> findValidPairsFor(StereoDevice device, List<StereoDevice> devices) async {
    return await _pairingManager.findValidPairsFor(device, devices);
  }

  /// Automatically connects to devices with the specified IDs as soon as they are discovered.
  /// This method sets up a subscription to the scan stream and listens for discovered devices.
  /// Scanning has to be started in order for this to work.
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

  /// Checks and requests the necessary permissions for BLE operations.
  /// Returns a Future that completes with a boolean indicating whether the permissions
  /// were granted or not.
  static Future<bool> checkAndRequestPermissions() {
    return BleManager.checkAndRequestPermissions();
  }
}
