import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/ble_manager.dart';
import 'package:universal_ble/universal_ble.dart';

abstract class WearableFactory {
  BleManager? bleManager;
  WearableDisconnectNotifier? disconnectNotifier;

  Future<bool> matches(DiscoveredDevice device, List<BleService> services);
  Future<Wearable> createFromDevice(DiscoveredDevice device);
}
