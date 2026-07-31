import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/managers/ble_manager.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stale controller cannot tear down its replacement subscription',
      () async {
    const deviceId = 'device';
    const serviceId = '7467b395-9043-4453-bc5c-2d8e8b10680a';
    const characteristicId = '7467b39c-9043-4453-bc5c-2d8e8b10680a';
    final platform = _FakeUniversalBlePlatform();
    UniversalBle.setInstance(platform);
    final manager = BleManager();

    platform.updateConnection(deviceId, true);
    final oldStream = await manager.subscribe(
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
    );
    final oldSubscription = oldStream.listen((_) {});
    oldSubscription.pause();

    // Closing a paused stream defers its onCancel callback. Reconnect and
    // subscribe again before that callback is allowed to run.
    platform.updateConnection(deviceId, false);
    platform.updateConnection(deviceId, true);
    final replacementStream = await manager.subscribe(
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
    );
    final replacementValue = Completer<List<int>>();
    final replacementSubscription = replacementStream.listen(
      replacementValue.complete,
    );

    oldSubscription.resume();
    await oldSubscription.asFuture<void>();
    await oldSubscription.cancel();
    await Future<void>.delayed(Duration.zero);

    platform.updateCharacteristicValue(
      deviceId,
      characteristicId,
      Uint8List.fromList([7]),
      null,
    );

    expect(await replacementValue.future, [7]);
    expect(
      platform.notificationChanges,
      [
        BleInputProperty.notification,
        BleInputProperty.notification,
      ],
    );
    await replacementSubscription.cancel();
  });
}

class _FakeUniversalBlePlatform extends UniversalBlePlatform {
  final List<BleInputProperty> notificationChanges = [];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    notificationChanges.add(bleInputProperty);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
