import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

/// Option for connecting to a wearable.
abstract class ConnectionOption {
  const ConnectionOption();
}

/// Abstract factory for creating [Wearable] instances from [DiscoveredDevice]s.
abstract class WearableFactory {
  /// The bleManager is used to perform GATT operations on the wearable.
  /// It is provided by the [WearableManager] and should not be set directly.
  BleGattManager? bleManager;

  /// The disconnect notifier is used to notify listeners when the wearable is disconnected.
  /// It is provided by the [WearableManager] and should not be set directly.
  WearableDisconnectNotifier? disconnectNotifier;

  /// Checks if the factory can create a wearable from the given device and services.
  Future<bool> matches(DiscoveredDevice device, List<BleService> services);
  /// Creates a wearable from the given device.
  Future<Wearable> createFromDevice(DiscoveredDevice device, { Set<ConnectionOption> options = const {} });
}
