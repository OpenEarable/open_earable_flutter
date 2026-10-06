import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/ble_manager.dart';
import 'package:universal_ble/universal_ble.dart';

DiscoveredDevice device(String id) => DiscoveredDevice(
      id: id,
      name: 'Test wearable',
      manufacturerData: Uint8List(0),
      rssi: -40,
      serviceUuids: const [],
    );

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('power off disconnects both peers even without native callbacks',
      () async {
    final platform = _Platform();
    UniversalBle.setInstance(platform);
    final manager = BleManager();
    addTearDown(manager.dispose);
    final disconnected = <String>[];
    for (final id in ['left', 'right']) {
      await manager.connectToDevice(device(id), () => disconnected.add(id));
    }
    final stream = await manager.subscribe(
      deviceId: 'left',
      serviceId: '180f',
      characteristicId: '2a19',
    );
    final closed = Completer<void>();
    final sub = stream.listen((_) {}, onDone: closed.complete);
    addTearDown(sub.cancel);

    platform.updateAvailability(AvailabilityState.poweredOff);
    await flushEvents();
    expect(manager.isConnected('left'), isFalse);
    expect(manager.isConnected('right'), isFalse);
    expect(disconnected, ['left', 'right']);
    expect(platform.disconnects, ['left', 'right']);
    await closed.future.timeout(const Duration(seconds: 1));

    // Some platforms also deliver per-device events, possibly after power-off.
    platform.updateConnection('left', false);
    platform.updateConnection('right', false);
    platform.updateAvailability(AvailabilityState.poweredOff);
    await flushEvents();
    expect(disconnected, ['left', 'right']);

    platform.updateAvailability(AvailabilityState.poweredOn);
    await manager.connectToDevice(
      device('left'),
      () => disconnected.add('left'),
    );
    expect(manager.isConnected('left'), isTrue);
    platform.updateConnection('left', false);
    expect(disconnected, ['left', 'right', 'left']);
  });

  test('reconnect waits until the old native handle is released', () async {
    final platform = _Platform();
    UniversalBle.setInstance(platform);
    final manager = BleManager();
    addTearDown(manager.dispose);
    await manager.connectToDevice(device('left'), () {});
    final cleanup = Completer<void>();
    platform.disconnectGate = cleanup.future;
    platform.updateAvailability(AvailabilityState.poweredOff);
    await flushEvents();
    platform.updateAvailability(AvailabilityState.poweredOn);
    final reconnected = manager.connectToDevice(device('left'), () {});
    await flushEvents();
    expect(platform.connectCalls, 1);
    cleanup.complete();
    expect((await reconnected).$1, isTrue);
    expect(platform.connectCalls, 2);
  });

  test(
      'an old service discovery cannot finish a new connection after power off',
      () async {
    UniversalBle.queueType = QueueType.none;
    addTearDown(() => UniversalBle.queueType = QueueType.global);
    final oldServices = Completer<List<BleService>>();
    final newServices = Completer<List<BleService>>();
    final platform = _Platform()..discoveryReplies = [oldServices, newServices];
    UniversalBle.setInstance(platform);
    final manager = BleManager();
    addTearDown(manager.dispose);
    final first = manager.connectToDevice(device('left'), () {});
    await flushEvents();
    expect(platform.discoveryCalls, 1);
    platform.updateAvailability(AvailabilityState.poweredOff);
    await flushEvents();
    expect((await first).$1, isFalse);

    platform.updateAvailability(AvailabilityState.poweredOn);
    var completed = false;
    final second =
        manager.connectToDevice(device('left'), () {}).then((result) {
      completed = true;
      return result;
    });
    await flushEvents();
    expect(platform.discoveryCalls, 2);
    oldServices.complete([]);
    await flushEvents();
    expect(completed, isFalse);
    final expected = [BleService('180f', [])];
    newServices.complete(expected);
    expect((await second).$2, expected);
  });

  test('wearable manager permits reconnect after a missing disconnect event',
      () async {
    final platform = _Platform();
    UniversalBle.setInstance(platform);
    final manager = WearableManager();
    manager.clearWearableFactories();
    manager.addWearableFactory(_Factory());
    addTearDown(manager.dispose);
    final left = await manager.connectToDevice(device('left'));
    final right = await manager.connectToDevice(device('right'));
    var disconnects = 0;
    left.addDisconnectListener(() => disconnects++);
    right.addDisconnectListener(() => disconnects++);

    platform.updateAvailability(AvailabilityState.poweredOff);
    await flushEvents();
    expect(disconnects, 2);
    platform.updateAvailability(AvailabilityState.poweredOn);
    final newLeft = await manager.connectToDevice(device('left'));
    final newRight = await manager.connectToDevice(device('right'));
    expect(identical(newLeft, left), isFalse);
    expect(identical(newRight, right), isFalse);
  });
}

class _Platform extends UniversalBlePlatform {
  List<Completer<List<BleService>>>? discoveryReplies;
  int discoveryCalls = 0;
  int connectCalls = 0;
  final disconnects = <String>[];
  Future<void>? disconnectGate;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;
  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    Object? platformConfig,
  }) async {
    connectCalls++;
    updateConnection(deviceId, true);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      BleConnectionState.disconnected;
  @override
  Future<void> disconnect(String deviceId) async {
    disconnects.add(deviceId);
    await disconnectGate;
    updateConnection(deviceId, false);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => expectedMtu;
  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async {
    final index = discoveryCalls++;
    return discoveryReplies == null
        ? []
        : await discoveryReplies![index].future;
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty property,
  ) async {}
  @override
  Future<void> stopScan() async {}
}

class _Factory extends WearableFactory {
  @override
  Future<bool> matches(
    DiscoveredDevice device,
    List<BleService> services,
  ) async =>
      true;
  @override
  Future<Wearable> createFromDevice(
    DiscoveredDevice device, {
    Set<ConnectionOption> options = const {},
  }) async =>
      _Wearable(device.id, disconnectNotifier!);
}

class _Wearable extends Wearable {
  _Wearable(this.deviceId, WearableDisconnectNotifier notifier)
      : super(name: 'Test wearable', disconnectNotifier: notifier);
  @override
  final String deviceId;
  @override
  Future<void> disconnect() async {}
}
