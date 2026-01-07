import '../../managers/ble_gatt_manager.dart';
import 'discovered_device.dart';
import 'wearable.dart';

abstract class BluetoothWearable extends Wearable {
  BluetoothWearable({
    required super.name,
    required super.disconnectNotifier,
    required this.bleManager,
    required this.discoveredDevice,
  });

  final BleGattManager bleManager;
  final DiscoveredDevice discoveredDevice;
}
