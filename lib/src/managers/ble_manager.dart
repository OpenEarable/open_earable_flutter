import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../open_earable_flutter.dart';

/// A class that establishes and manages Bluetooth Low Energy (BLE)
/// communication with OpenEarable devices.
class BleManager extends BleGattManager {
  static const int _desiredMtu = 60;
  int _mtu = _desiredMtu; // Largest Byte package sent is 42 bytes for IMU
  int get mtu => _mtu;

  final Map<String, List<StreamController<List<int>>>> _streamControllers = {};

  /// A stream of discovered devices during scanning.
  StreamController<DiscoveredDevice>? _scanStreamController;

  Stream<DiscoveredDevice> get scanStream => _scanStreamController!.stream;

  String _getCharacteristicKey(String deviceId, String characteristicId) =>
      "$deviceId||$characteristicId";

  void _closeStreamControllersForDevice(String deviceId) {
    final prefix = "$deviceId||";
    final keysToRemove = _streamControllers.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);

    for (final key in keysToRemove) {
      final controllers = _streamControllers.remove(key);
      if (controllers == null) {
        continue;
      }
      for (final controller in controllers) {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }
  }

  final Map<String, Completer> _connectionCompleters = {};
  final Map<String, VoidCallback> _connectCallbacks = {};
  final Map<String, VoidCallback> _disconnectCallbacks = {};

  final List<String> _connectedDevicesIds = [];

  bool _firstScan = true;

  BleManager() {
    _init();
  }

  @override
  bool isConnected(String deviceId) {
    return _connectedDevicesIds.contains(deviceId);
  }

  void _init() {
    _scanStreamController = StreamController<DiscoveredDevice>.broadcast();

    UniversalBle.onConnectionChange = (
      String deviceId,
      bool isConnected,
      String? error,
    ) {
      logger.d("Connection change for $deviceId: $isConnected");
      if (isConnected) {
        _connectedDevicesIds.add(deviceId);
        _connectCallbacks[deviceId]?.call();
        _connectCallbacks.remove(deviceId);
      } else {
        _connectedDevicesIds.remove(deviceId);
        _disconnectCallbacks[deviceId]?.call();
        _disconnectCallbacks.remove(deviceId);
      }
    };

    UniversalBle.onValueChange = (
      String deviceId,
      String characteristicId,
      Uint8List value,
    ) {
      String streamIdentifier =
          _getCharacteristicKey(deviceId, characteristicId);
      if (!_streamControllers.containsKey(streamIdentifier)) {
        return;
      }
      final controllers = _streamControllers[streamIdentifier]!;
      for (var e in controllers) {
        if (!e.isClosed) {
          e.add(value);
        }
      }
    };
  }

  static Future<bool> checkAndRequestPermissions() async {
    bool permGranted = false;

    // Don't run `Platform.is*` on web
    if (!kIsWeb && Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      permGranted = (statuses[Permission.bluetoothScan]!.isGranted &&
          statuses[Permission.bluetoothConnect]!.isGranted &&
          statuses[Permission.location]!.isGranted);
    } else {
      permGranted = true;
    }

    return permGranted;
  }

  static Future<bool> checkPermissions() async {
    if (kIsWeb) {
      return true; // Permissions are not required on web
    }

    return await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted &&
        await Permission.location.isGranted;
  }

  /// Initiates the BLE device scan to discover nearby Bluetooth devices.
  Future<void> startScan({
    bool checkAndRequestPermissions = true,
  }) async {
    bool? permGranted;

    if (checkAndRequestPermissions) {
      permGranted = await BleManager.checkAndRequestPermissions();
    }

    if (permGranted == true || !checkAndRequestPermissions) {
      // Workaround for iOS, otherwise we need to press the scan button twice for it
      for (int i = 0;
          i < ((!kIsWeb && Platform.isIOS && _firstScan) ? 2 : 1);
          ++i) {
        if (i == 1) {
          await Future.delayed(const Duration(seconds: 1));
        }

        await UniversalBle.stopScan();

        UniversalBle.onScanResult = (bleDevice) {
          _scanStreamController?.add(
            DiscoveredDevice(
              id: bleDevice.deviceId,
              name: bleDevice.name ?? "",
              manufacturerData:
                  bleDevice.manufacturerDataList.firstOrNull?.toUint8List() ??
                      Uint8List.fromList([]),
              rssi: bleDevice.rssi ?? -1,
              serviceUuids: bleDevice.services,
            ),
          );
        };

        if (!kIsWeb) {
          List<DiscoveredDevice> devices = await getSystemDevices();
          for (var device in devices) {
            _scanStreamController?.add(device);
          }
        }
        await UniversalBle.startScan();
      }
      _firstScan = false;
    }
  }

  /// Retrieves a list of system devices.
  /// Throws an exception if called on web.
  /// If no devices are found, returns an empty list.
  /// If the platform is not web, it uses `UniversalBle.getSystemDevices`.
  Future<List<DiscoveredDevice>> getSystemDevices() async {
    if (!await checkAndRequestPermissions()) {
      throw Exception("Permissions not granted");
    }
    if (kIsWeb) {
      throw Exception("getSystemDevices is not supported on web");
    }
    return UniversalBle.getSystemDevices().then((devices) {
      return devices.map((device) {
        return DiscoveredDevice(
          id: device.deviceId,
          name: device.name ?? "",
          manufacturerData:
              device.manufacturerDataList.firstOrNull?.toUint8List() ??
                  Uint8List.fromList([]),
          rssi: device.rssi ?? -1,
          serviceUuids: device.services,
        );
      }).toList();
    });
  }

  /// Connects to the specified Earable device.
  Future<(bool, List<BleService>)> connectToDevice(
    DiscoveredDevice device,
    VoidCallback onDisconnect,
  ) {
    _closeStreamControllersForDevice(device.id);

    Completer<(bool, List<BleService>)> completer =
        Completer<(bool, List<BleService>)>();
    _connectionCompleters[device.id] = completer;

    _connectCallbacks[device.id] = () async {
      if (!kIsWeb && !Platform.isLinux) {
        _mtu = await UniversalBle.requestMtu(device.id, _desiredMtu);
      }
      bool connectionResult = false;
      List<BleService> services = [];

      services = await UniversalBle.discoverServices(device.id);
      connectionResult = true;

      _connectionCompleters[device.id]?.complete((connectionResult, services));
      _connectionCompleters.remove(device.id);
    };

    _disconnectCallbacks[device.id] = () {
      _closeStreamControllersForDevice(device.id);
      _connectionCompleters[device.id]?.complete((false, <BleService>[]));
      _connectionCompleters.remove(device.id);

      onDisconnect();
    };

    UniversalBle.connect(device.id);

    return completer.future;
  }

  /// Checks if the connected device has a specific service.
  @override
  Future<bool> hasService({
    required String deviceId,
    required String serviceId,
  }) async {


    if (!isConnected(deviceId)) {
      throw Exception("Device is not connected");
    }

    List<BleService> services = await UniversalBle.discoverServices(deviceId);
    for (final service in services) {
      if (service.uuid.toLowerCase() == serviceId.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  /// Checks if the connected device has a specific characteristic.
  @override
  Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    if (!isConnected(deviceId)) {
      throw Exception("Device is not connected");
    }
    List<BleService> services = await UniversalBle.discoverServices(deviceId);
    for (final service in services) {
      if (service.uuid.toLowerCase() == serviceId.toLowerCase()) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid.toLowerCase() == characteristicId.toLowerCase()) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Writes byte data to a specific characteristic of the connected Earable device.
  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
  }) async {
    if (!isConnected(deviceId)) {
      throw Exception("Write failed because no Earable is connected");
    }
    await UniversalBle.write(
      deviceId,
      serviceId,
      characteristicId,
      Uint8List.fromList(byteData),
    );
  }

  /// Subscribes to a specific characteristic of the connected Earable device.
  @override
  Stream<List<int>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) {
    final streamController = StreamController<List<int>>();
    String streamIdentifier = _getCharacteristicKey(deviceId, characteristicId);
    if (!_streamControllers.containsKey(streamIdentifier)) {
      UniversalBle.subscribeNotifications(
        deviceId,
        serviceId,
        characteristicId,
      );
      _streamControllers[streamIdentifier] = [streamController];
    } else {
      _streamControllers[streamIdentifier]!.add(streamController);
    }

    streamController.onCancel = () {
      if (_streamControllers.containsKey(streamIdentifier)) {
        _streamControllers[streamIdentifier]!.remove(streamController);
        if (_streamControllers[streamIdentifier]!.isEmpty) {
          UniversalBle.unsubscribe(
            deviceId,
            serviceId,
            characteristicId,
          );
          _streamControllers.remove(streamIdentifier);
        }
      }
    };

    return streamController.stream;
  }

  /// Reads data from a specific characteristic of the connected Earable device.
  @override
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    if (!isConnected(deviceId)) {
      throw Exception("Read failed because no Earable is connected");
    }

    final response = await UniversalBle.read(
      deviceId,
      serviceId,
      characteristicId,
    );
    return response.toList();
  }

  @override
  Future<void> disconnect(String deviceId) {
    return UniversalBle.disconnect(deviceId);
  }

  /// Cancel connection state subscription
  void dispose() {
    UniversalBle.onConnectionChange = (
      String deviceId,
      bool isConnected,
      String? error,
    ) {};
    UniversalBle.stopScan();
    UniversalBle.onScanResult = (_) {};
    _scanStreamController?.close();

    for (var list in _streamControllers.values) {
      for (var e in list) {
        if (!e.isClosed) {
          e.close();
        }
      }
    }
    _streamControllers.clear();
  }
}
