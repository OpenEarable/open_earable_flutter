import 'dart:async';
import 'dart:typed_data';

import '../../../open_earable_flutter.dart';
import '../../managers/ble_manager.dart';

class DevKit extends Wearable {
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  DevKit({
    required super.name,
    required super.disconnectNotifier,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _bleManager = bleManager,
        _discoveredDevice = discoveredDevice;

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }
}
