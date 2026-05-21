import 'package:open_earable_flutter/src/models/devices/cosinuss_one.dart';
import 'package:open_earable_flutter/src/models/devices/discovered_device.dart';
import 'package:open_earable_flutter/src/models/devices/wearable.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';

class CosinussOneFactory extends WearableFactory {
  static const String _name = "earconnect";

  @override
  Set<String> get usedServiceUuids => const {
        CosinussOne.ppgAndAccServiceUuid,
        CosinussOne.temperatureServiceUuid,
        CosinussOne.heartRateServiceUuid,
        CosinussOne.batteryServiceUuid,
      };

  @override
  Future<bool> matches(
    DiscoveredDevice device,
    List<BleService> services,
  ) async {
    return device.name == _name;
  }

  @override
  Future<Wearable> createFromDevice(
    DiscoveredDevice device, {
    Set<ConnectionOption> options = const {},
  }) async {
    if (bleManager == null) {
      throw StateError("bleManager needs to be set before using the factory");
    }
    if (disconnectNotifier == null) {
      throw StateError(
        "disconnectNotifier needs to be set before using the factory",
      );
    }

    if (device.name != _name) {
      throw ArgumentError.value(device.name, 'device.name', 'Expected $_name');
    }

    return CosinussOne(
      name: device.name,
      disconnectNotifier: disconnectNotifier!,
      bleManager: bleManager!,
      discoveredDevice: device,
    );
  }
}
