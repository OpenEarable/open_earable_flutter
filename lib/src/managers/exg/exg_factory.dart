import 'package:open_earable_flutter/src/models/devices/cosinuss_one.dart';
import 'package:open_earable_flutter/src/models/devices/discovered_device.dart';
import 'package:open_earable_flutter/src/models/devices/wearable.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';
import 'exg_wearable.dart';


class ExGFactory extends WearableFactory {
  // todo ExG Devices are still named OpenEarable-<ident> fixit or keep it index 0 when creating the _wearableFactories
  static final RegExp _nameRegex = RegExp(r'^OpenEarable(?:[-_].*)?$');

  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    final name = (device.name ?? '').trim();
    return _nameRegex.hasMatch(name);
  }

  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device, { Set<ConnectionOption> options = const {} }) async {
    if (bleManager == null) {
      throw Exception("bleManager needs to be set before using the factory");
    }
    if (disconnectNotifier == null) {
      throw Exception("disconnectNotifier needs to be set before using the factory");
    }

    final name = (device.name ?? '').trim();
    if (!_nameRegex.hasMatch(name)) {
      throw Exception("device is not an exg device");
    }

    return ExGWearable(
      name: device.name,
      disconnectNotifier: disconnectNotifier!,
      bleManager: bleManager!,
      discoveredDevice: device,
    );
  }
}
