import 'package:open_earable_flutter/src/models/devices/discovered_device.dart';
import 'package:open_earable_flutter/src/models/devices/polar.dart';
import 'package:open_earable_flutter/src/models/devices/wearable.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';

class PolarFactory extends WearableFactory {
  static const String _namePrefix = "Polar";

  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device) async {
    if (bleManager == null) {
      throw Exception("bleManager needs to be set before using the factory");
    }
    if (disconnectNotifier == null) {
      throw Exception("disconnectNotifier needs to be set before using the factory");
    }

    if (!device.name.startsWith(_namePrefix)) {
      throw Exception("device is not a polar device");
    }

    return Polar(
      name: device.name,
      disconnectNotifier: disconnectNotifier!,
      bleManager: bleManager!,
      discoveredDevice: device,
    );
  }

  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    return device.name.startsWith(_namePrefix);
  }
}
