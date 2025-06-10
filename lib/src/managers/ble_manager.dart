import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../open_earable_flutter.dart';
import '../constants.dart';

/// A class that establishes and manages Bluetooth Low Energy (BLE)
/// communication with OpenEarable devices.
class BleManager {
  int mtu = 60; // Largest Byte package sent is 42 bytes for IMU

  final Map<String, List<StreamController<List<int>>>> _streamControllers = {};

  /// A stream of discovered devices during scanning.
  StreamController<DiscoveredDevice>? _scanStreamController;

  Stream<DiscoveredDevice> get scanStream => _scanStreamController!.stream;

  String _getCharacteristicKey(String deviceId, String characteristicId) =>
      "$deviceId||$characteristicId";

  final Map<String, Completer> _connectionCompleters = {};
  final Map<String, VoidCallback> _connectCallbacks = {};
  final Map<String, VoidCallback> _disconnectCallbacks = {};

  final List<String> _connectedDevicesIds = [];

  bool _firstScan = true;

  BleManager() {
    _init();
  }

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
      for (var e in _streamControllers[streamIdentifier]!) {
        e.add(value);
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

  /// Initiates the BLE device scan to discover nearby Bluetooth devices.
  Future<void> startScan({
    bool filterByServices = false,
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
          UniversalBle.getSystemDevices(
            // This filter has several generic services by default as filter
            // and is required on iOS/MacOS
            withServices: allServiceUuids,
          ).then((devices) {
            for (var bleDevice in devices) {
              _scanStreamController?.add(
                DiscoveredDevice(
                  id: bleDevice.deviceId,
                  name: bleDevice.name ?? "",
                  manufacturerData: bleDevice.manufacturerDataList.firstOrNull
                          ?.toUint8List() ??
                      Uint8List.fromList([]),
                  rssi: bleDevice.rssi ?? -1,
                  serviceUuids: bleDevice.services,
                ),
              );
            }
          });
        }

        await UniversalBle.startScan(
          scanFilter: ScanFilter(
            // Needs to be passed for web, can be empty for the rest
            withServices: (kIsWeb || filterByServices) ? allServiceUuids : [],
          ),
        );
      }
      _firstScan = false;
    }
  }

  /// Connects to the specified Earable device.
  Future<(bool, List<BleService>)> connectToDevice(
    DiscoveredDevice device,
    VoidCallback onDisconnect,
  ) {
    for (var list in _streamControllers.values) {
      for (var e in list) {
        e.close();
      }
    }

    Completer<(bool, List<BleService>)> completer =
        Completer<(bool, List<BleService>)>();
    _connectionCompleters[device.id] = completer;

    _connectCallbacks[device.id] = () async {
      if (!kIsWeb && !Platform.isLinux) {
        UniversalBle.requestMtu(device.id, mtu);
      }
      bool connectionResult = false;
      List<BleService> services = [];

      services = await UniversalBle.discoverServices(device.id);
      connectionResult = true;

      _connectionCompleters[device.id]?.complete((connectionResult, services));
      _connectionCompleters.remove(device.id);
    };

    _disconnectCallbacks[device.id] = () {
      _connectionCompleters[device.id]?.complete((false, <BleService>[]));
      _connectionCompleters.remove(device.id);

      onDisconnect();
    };

    UniversalBle.connect(device.id);

    return completer.future;
  }

  /// Writes byte data to a specific characteristic of the connected Earable device.
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
  }) async {
    if (!isConnected(deviceId)) {
      throw Exception("Write failed because no Earable is connected");
    }
    await UniversalBle.writeValue(
      deviceId,
      serviceId,
      characteristicId,
      Uint8List.fromList(byteData),
      BleOutputProperty.withResponse,
    );
  }

  /// Subscribes to a specific characteristic of the connected Earable device.
  Stream<List<int>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) {
    final streamController = StreamController<List<int>>();
    String streamIdentifier = _getCharacteristicKey(deviceId, characteristicId);
    if (!_streamControllers.containsKey(streamIdentifier)) {
      UniversalBle.setNotifiable(
        deviceId,
        serviceId,
        characteristicId,
        BleInputProperty.notification,
      );
      _streamControllers[streamIdentifier] = [streamController];
    } else {
      _streamControllers[streamIdentifier]!.add(streamController);
    }

    streamController.onCancel = () {
      if (_streamControllers.containsKey(streamIdentifier)) {
        _streamControllers[streamIdentifier]!.remove(streamController);
        if (_streamControllers[streamIdentifier]!.isEmpty) {
          UniversalBle.setNotifiable(
            deviceId,
            serviceId,
            characteristicId,
            BleInputProperty.disabled,
          );
          _streamControllers.remove(streamIdentifier);
        }
      }
    };

    return streamController.stream;
  }

  /// Reads data from a specific characteristic of the connected Earable device.
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    if (!isConnected(deviceId)) {
      throw Exception("Read failed because no Earable is connected");
    }

    final response = await UniversalBle.readValue(
      deviceId,
      serviceId,
      characteristicId,
    );
    return response.toList();
  }

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
        e.close();
      }
    }
  }
}
