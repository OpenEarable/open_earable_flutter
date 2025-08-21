import 'package:universal_ble/universal_ble.dart';

import '../wearable_factory.dart';
import 'discovered_device.dart';
import 'wearable.dart';

class JuBotImuFactory extends WearableFactory {
  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device) {
    // TODO: implement createFromDevice
    throw UnimplementedError();
  }

  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    // TODO: implement matches
    return false;
  }
}
