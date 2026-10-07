import 'package:universal_ble/universal_ble.dart';

import '../../omnibuds/omnibuds_protocol.dart';
import '../../omnibuds/omnibuds_transport.dart';
import '../wearable_factory.dart';
import 'discovered_device.dart';
import 'omnibuds.dart';
import 'wearable.dart';

/// Recognizes OmniBuds by its vendor service rather than accepting a name alone.
class OmniBudsFactory extends WearableFactory {
  @override
  Set<String> get usedServiceUuids => const {OmniBudsGatt.service};

  @override
  Future<bool> matches(
    DiscoveredDevice device,
    List<BleService> services,
  ) async =>
      !RegExp(r'(Case|Charger)', caseSensitive: false).hasMatch(device.name) &&
      services.any((s) => s.uuid.toLowerCase() == OmniBudsGatt.service);

  @override
  Future<Wearable> createFromDevice(
    DiscoveredDevice device, {
    Set<ConnectionOption> options = const {},
  }) async {
    final ble = bleManager;
    final notifier = disconnectNotifier;
    if (ble == null || notifier == null) {
      throw StateError('OmniBuds factory is not attached to a WearableManager');
    }
    final transport = OmniBudsTransport(ble: ble, deviceId: device.id);
    // Cover a disconnect during initialization as well as after construction.
    notifier.addListener(transport.dispose);
    await transport.initialize();
    return OmniBuds(
      name: device.name,
      transport: transport,
      disconnectNotifier: notifier,
    );
  }
}
