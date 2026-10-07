import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/omnibuds/omnibuds_transport.dart';
import 'package:universal_ble/universal_ble.dart';

const left = DevicePosition.left;
const right = DevicePosition.right;

// Synthetic wire fixtures derived from the APK's decoder, NOT hardware captures.
List<int> data(int peripheral, int metadata, String csv) =>
    [peripheral, 2, csv.length, metadata, 0, ...utf8.encode(csv)];
List<int> ack(
  int peripheral,
  int endpoint, {
  int error = 0,
  String text = '',
}) =>
    [
      peripheral,
      0x11,
      text.length + 2,
      0,
      0,
      endpoint,
      error,
      ...utf8.encode(text),
    ];

class OmniGatt extends Fake implements BleGattManager {
  final characteristics = {
    OmniBudsGatt.left,
    OmniBudsGatt.right,
    OmniBudsGatt.control,
  };
  final streams = <String, StreamController<List<int>>>{};
  final writes = <(String, List<int>)>[];
  final subscriptions = <String, int>{};
  final endpointValues = <(String, int, int), String>{};
  final errors = <(int, int), int>{};
  int statusFlags = 3;
  bool respond = true;
  bool connected = true;
  bool echo = true;
  Future<void>? discoveryGate;
  Future<void>? writeGate;

  @override
  Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    await discoveryGate;
    return characteristics.contains(characteristicId);
  }

  @override
  Future<Stream<List<int>>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    subscriptions.update(characteristicId, (v) => v + 1, ifAbsent: () => 1);
    return (streams[characteristicId] ??=
            StreamController<List<int>>.broadcast(sync: true))
        .stream;
  }

  void emit(DevicePosition ear, List<int> bytes) =>
      streams[OmniBudsGatt.characteristic(ear)]!.add(bytes);
  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
    bool withoutResponse = false,
  }) async {
    expect(serviceId, OmniBudsGatt.service);
    expect(withoutResponse, false);
    writes.add((characteristicId, List.of(byteData)));
    await writeGate;
    if (!respond) return;
    if (characteristicId == OmniBudsGatt.control) {
      expect(byteData, [2]);
      streams[characteristicId]!.add([3, statusFlags >> 8, statusFlags & 255]);
    } else if (byteData[0] != 35) {
      final key = (characteristicId, byteData[0], byteData[5]);
      final error = errors[(key.$2, key.$3)] ?? 0;
      if (byteData[1] == 9 && error == 0) {
        endpointValues[key] = utf8.decode(byteData.sublist(6));
      }
      streams[characteristicId]!.add(
        ack(
          key.$2,
          key.$3,
          error: error,
          text: echo ? endpointValues[key] ?? '0' : '',
        ),
      );
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    connected = false;
  }

  @override
  bool isConnected(String deviceId) => connected;
  Future<void> dispose() async {
    for (final stream in streams.values) {
      await stream.close();
    }
  }
}

Future<(OmniBuds, OmniGatt, WearableDisconnectNotifier)> makeWearable({
  OmniGatt? ble,
}) async {
  final gatt = ble ?? OmniGatt();
  final transport = OmniBudsTransport(
    ble: gatt,
    deviceId: 'pair',
    responseTimeout: const Duration(milliseconds: 25),
  );
  await transport.initialize();
  final notifier = WearableDisconnectNotifier();
  final wearable = OmniBuds(
    name: 'OmniBuds-FF03',
    transport: transport,
    disconnectNotifier: notifier,
  );
  addTearDown(() async {
    await wearable.disconnect();
    await gatt.dispose();
  });
  return (wearable, gatt, notifier);
}

void main() {
  test('frequency helpers enable the requested or maximum stream', () {
    final applied = <OmniBudsRateValue>[];
    final config = OmniBudsRateConfiguration(
      name: 'PPG',
      rates: [25, 50, 100],
      apply: (v) async {
        applied.add(v);
      },
      reportError: (e) => fail('$e'),
    );
    expect(config.setMaximumFrequency(), OmniBudsRateValue(100));
    expect(config.setFrequencyBestEffort(30), OmniBudsRateValue(50));
    expect(config.setFrequencyBestEffort(200), OmniBudsRateValue(100));
    expect(applied.every((v) => v.enabled), true);
    expect(() => config.apply(OmniBudsRateValue(75)), throwsArgumentError);
  });

  test('disconnect during discovery never leaves a notification listener',
      () async {
    final gate = Completer<void>();
    final gatt = OmniGatt()..discoveryGate = gate.future;
    final transport = OmniBudsTransport(ble: gatt, deviceId: 'pair');
    final init = expectLater(transport.initialize(), throwsStateError);
    await transport.dispose();
    gate.complete();
    await init;
    expect(gatt.subscriptions, isEmpty);
    await gatt.dispose();
  });

  test('a hung GATT write times out without wedging the command queue',
      () async {
    final (w, g, _) = await makeWearable();
    final gate = Completer<void>();
    g.writeGate = gate.future;
    g.respond = false;
    await expectLater(
      w.readConfiguration(left, OmniBudsSensorKind.ppg, 1),
      throwsA(isA<TimeoutException>()),
    );
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    g.writeGate = null;
    g.respond = true;
    await w.readConfiguration(right, OmniBudsSensorKind.ppg, 1);
    await expectLater(
      w.readConfiguration(left, OmniBudsSensorKind.ppg, 1),
      throwsStateError,
    );
  });

  test('range controls encode supported physical values and reject others',
      () async {
    final (w, g, _) = await makeWearable();
    g.writes.clear();
    await w.setSensorRange(left, OmniBudsSensorKind.accelerometer, 16);
    await w.setSensorRange(right, OmniBudsSensorKind.gyroscope, 2000);
    await w.setSensorRange(left, OmniBudsSensorKind.ppg, 93);
    expect(g.writes.map((w) => utf8.decode(w.$2.sublist(6))), ['3', '4', '93']);
    expect(
      () => w.setSensorRange(left, OmniBudsSensorKind.ppg, 100),
      throwsArgumentError,
    );
    expect(g.writes.length, 3);
  });

  test(
      'invalid settings produce no BLE writes and observed readback updates state',
      () async {
    final (w, g, _) = await makeWearable();
    g.writes.clear();
    expect(
      () => w.configureSensor(
        left,
        OmniBudsSensorKind.ppg,
        enabled: true,
        frequencyHz: 999,
      ),
      throwsArgumentError,
    );
    expect(
      () => w.configureSensor(
        left,
        OmniBudsSensorKind.heartRate,
        enabled: true,
        frequencyHz: 1,
      ),
      throwsArgumentError,
    );
    expect(g.writes, isEmpty);
    g.endpointValues[(OmniBudsGatt.left, 5, 0)] = '1';
    g.endpointValues[(OmniBudsGatt.left, 5, 1)] = '50';
    await w.readConfiguration(left, OmniBudsSensorKind.ppg, 0);
    await w.readConfiguration(left, OmniBudsSensorKind.ppg, 1);
    expect(
      (await w.sensorConfigurationStream.first).values.single,
      OmniBudsRateValue(50),
    );
    g.endpointValues[(OmniBudsGatt.left, 5, 1)] = '999';
    await w.readConfiguration(left, OmniBudsSensorKind.ppg, 1);
    expect(await w.sensorConfigurationStream.first, isEmpty);
  });

  test('configuration bytes match the APK header and text wire format', () {
    expect(
      encodeOmniBudsConfiguration(0, 1, value: '3'),
      [0, 9, 2, 0, 0, 1, 51],
    );
    expect(
      encodeOmniBudsConfiguration(5, 1, value: '100'),
      [5, 9, 4, 0, 0, 1, 49, 48, 48],
    );
    expect(
      encodeOmniBudsConfiguration(7, 1, value: '0.2'),
      [7, 9, 4, 0, 0, 1, 48, 46, 50],
    );
    expect(encodeOmniBudsConfiguration(41, 0), [41, 1, 1, 0, 0, 0]);
    expect(
      encodeOmniBudsConfiguration(35, 0, value: '123', errorCode: 0),
      [35, 9, 4, 0, 0, 0, 0, 49, 50, 51],
    );
    expect(() => encodeOmniBudsConfiguration(256, 0), throwsArgumentError);
    expect(
      () => encodeOmniBudsConfiguration(1, 0, value: 'a' * 255),
      throwsArgumentError,
    );
  });

  test('all raw rate options encode to the vendor settings', () {
    expect(
      OmniBudsSensorKind.accelerometer.rates
          .map(OmniBudsSensorKind.accelerometer.encodeRate),
      ['0', '1', '2', '3'],
    );
    expect(OmniBudsSensorKind.gyroscope.rates, [10, 25, 50, 100]);
    expect(OmniBudsSensorKind.magnetometer.rates, [10, 20, 50, 100]);
    expect(
      OmniBudsSensorKind.ppg.rates.map(OmniBudsSensorKind.ppg.encodeRate),
      ['25', '50', '100'],
    );
    expect(OmniBudsSensorKind.temperature.encodeRate(0.2), '0.2');
  });

  test(
      'negative motion values, units, raw readings and ear identity survive decoding',
      () {
    final msg =
        OmniBudsMessage.decode(right, data(0, 0x30, '1000,-16384,0,16384'));
    final value =
        decodeOmniBudsSamples(msg, OmniBudsSensorKind.accelerometer).single;
    expect(value.values[0], closeTo(-0.999424, 1e-9));
    expect(value.rawValues, [-16384, 0, 16384]);
    expect(value.message.ear, right);
    expect(value.timestamp, 1000000);
    final gyro = decodeOmniBudsSamples(
      OmniBudsMessage.decode(left, data(1, 0x34, '1000,-100,100,0')),
      OmniBudsSensorKind.gyroscope,
    ).single;
    expect(gyro.values, [closeTo(-7, 1e-9), closeTo(7, 1e-9), 0]);
    final mag = decodeOmniBudsSamples(
      OmniBudsMessage.decode(left, data(2, 0x30, '1000,-1000,1000,0')),
      OmniBudsSensorKind.magnetometer,
    ).single;
    expect(mag.values, [-1.5, 1.5, 0]);
  });

  test('batches retain every reading at each known motion and PPG rate', () {
    for (final kind in [
      OmniBudsSensorKind.accelerometer,
      OmniBudsSensorKind.gyroscope,
      OmniBudsSensorKind.magnetometer,
      OmniBudsSensorKind.ppg,
    ]) {
      for (var code = 0; code < kind.rates.length; code++) {
        final metadata = kind == OmniBudsSensorKind.ppg
            ? kind.rates[code].toInt()
            : code << 4;
        final packet = OmniBudsMessage.decode(
          left,
          data(kind.peripheralId, metadata, '1000,1,2,3,4,5,6,7,8,9'),
        );
        final samples = decodeOmniBudsSamples(packet, kind);
        expect(samples.length, 3);
        expect(samples.map((v) => v.rawValues), [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ]);
        final rate = kind.peripheralId < 2 && code == 0 ? 12 : kind.rates[code];
        expect(samples[2].timestamp, 1000000 + (2000000 / rate).round());
        expect(samples[2].sampleIndex, 2);
      }
    }
  });

  test(
      'temperature and all four supported vital outputs retain device timestamp',
      () {
    for (final kind
        in OmniBudsSensorKind.values.where((k) => k.peripheralId >= 7)) {
      final samples = decodeOmniBudsSamples(
        OmniBudsMessage.decode(
          left,
          data(kind.peripheralId, 0, '1728000000000,36.75'),
        ),
        kind,
      );
      expect(samples.single.timestamp, 1728000000000000);
      expect(samples.single.values, [36.75]);
    }
  });

  test('malformed packets and unknown metadata do not invent sensor samples',
      () {
    for (final bytes in [
      <int>[],
      [0, 1, 2, 3, 4],
      data(0, 0x40, '1000,1,2,3'),
      data(0, 0x3f, '1000,1,2,3'),
      data(0, 0x30, '1000,1,2'),
      data(0, 0x30, '1000,NaN,1,2'),
      data(0, 0x30, 'oops,1,2,3'),
    ]) {
      expect(
        () => decodeOmniBudsSamples(
          OmniBudsMessage.decode(left, bytes),
          OmniBudsSensorKind.accelerometer,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => decodeOmniBudsSamples(
        OmniBudsMessage.decode(left, data(5, 0, '1,1,2,3')),
        OmniBudsSensorKind.ppg,
      ),
      throwsFormatException,
    );
  });

  test(
      'one connection exposes both sides and shares one subscription per channel',
      () async {
    final (w, g, _) = await makeWearable();
    expect(w.sensors.length, 18);
    expect(w.connectedEars, {left, right});
    expect(w.getWearableIconPath(), endsWith('/pair.svg'));
    final ls = w.sensors
        .firstWhere((s) => s.ear == left && s.kind == OmniBudsSensorKind.ppg);
    final rs = w.sensors
        .firstWhere((s) => s.ear == right && s.kind == OmniBudsSensorKind.ppg);
    final l = ls.sensorStream.first;
    final r = rs.sensorStream.first;
    g.emit(right, data(5, 100, '1000,4,5,6'));
    g.emit(left, data(5, 100, '1000,1,2,3'));
    expect((await l).values, [1, 2, 3]);
    expect((await r).values, [4, 5, 6]);
    expect(g.subscriptions[OmniBudsGatt.left], 1);
    expect(g.subscriptions[OmniBudsGatt.right], 1);
    g.statusFlags = 1;
    await w.refreshConnectionStatus();
    expect(w.getWearableIconPath(), endsWith('/left.svg'));
    expect(
      w.getWearableIconPath(variant: WearableIconVariant.right),
      endsWith('/right.svg'),
    );
  });

  test('one-ear firmware works without the optional status characteristic',
      () async {
    final g = OmniGatt()
      ..characteristics.remove(OmniBudsGatt.right)
      ..characteristics.remove(OmniBudsGatt.control);
    final (w, _, _) = await makeWearable(ble: g);
    expect(w.sensors.length, 9);
    expect(w.connectedEars, isNull);
    expect(w.getWearableIconPath(), endsWith('/left.svg'));
    expect(g.writes, isEmpty); // Connecting never starts or stops sensing.
  });

  test(
      'configuration transactions serialize and ACK-only replies update UI state',
      () async {
    final (w, g, _) = await makeWearable();
    g.echo = false;
    g.writes.clear();
    expect(await w.sensorConfigurationStream.first, isEmpty);
    await Future.wait([
      w.configureSensor(
        left,
        OmniBudsSensorKind.ppg,
        enabled: true,
        frequencyHz: 100,
      ),
      w.configureSensor(
        right,
        OmniBudsSensorKind.accelerometer,
        enabled: true,
        frequencyHz: 50,
      ),
    ]);
    expect(g.writes.map((v) => v.$2), [
      [5, 9, 2, 0, 0, 0, 48],
      [5, 9, 4, 0, 0, 1, 49, 48, 48],
      [5, 9, 2, 0, 0, 0, 49],
      [0, 9, 2, 0, 0, 0, 48],
      [0, 9, 2, 0, 0, 1, 50],
      [0, 9, 2, 0, 0, 0, 49],
    ]);
    final state = await w.sensorConfigurationStream.first;
    expect(
      state.values.whereType<OmniBudsRateValue>().every((v) => v.enabled),
      true,
    );
    expect(state.length, 2);
  });

  test(
      'failed rate change leaves sensor off and never reports successful start',
      () async {
    final (w, g, _) = await makeWearable();
    g.echo = false;
    g.writes.clear();
    g.errors[(5, 1)] = 4;
    await expectLater(
      w.configureSensor(
        left,
        OmniBudsSensorKind.ppg,
        enabled: true,
        frequencyHz: 50,
      ),
      throwsA(isA<OmniBudsConfigurationException>()),
    );
    expect(g.writes.length, 2);
    final state = await w.sensorConfigurationStream.first;
    expect((state.values.single as OmniBudsRateValue).enabled, false);
  });

  test(
      'timed-out endpoint is quarantined and late responses cannot confirm a retry',
      () async {
    final (w, g, _) = await makeWearable();
    g.respond = false;
    await expectLater(
      w.readConfiguration(left, OmniBudsSensorKind.ppg, 1),
      throwsA(isA<TimeoutException>()),
    );
    g.respond = true;
    g.emit(left, ack(5, 1, text: '100'));
    await expectLater(
      w.readConfiguration(left, OmniBudsSensorKind.ppg, 1),
      throwsStateError,
    );
    // An independent ear/endpoint remains usable.
    await w.readConfiguration(right, OmniBudsSensorKind.ppg, 1);
  });

  test(
      'disconnect rejects pending commands, closes streams and cancels BLE listeners',
      () async {
    final (w, g, n) = await makeWearable();
    g.respond = false;
    final pending = w.readConfiguration(left, OmniBudsSensorKind.ppg, 1);
    final checked = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    n.notifyListeners();
    await checked;
    await Future<void>.delayed(Duration.zero);
    expect(g.streams.values.any((s) => s.hasListener), false);
  });

  test('time requests are answered in Unix ms without switching device modes',
      () async {
    final (w, g, _) = await makeWearable();
    g.writes.clear();
    g.emit(left, [35, 1, 1, 0, 0, 0]);
    await Future<void>.delayed(Duration.zero);
    final bytes = g.writes.single.$2;
    expect(bytes.take(2), [35, 9]);
    expect(bytes[6], 0);
    final time = int.parse(utf8.decode(bytes.sublist(7)));
    expect(
      (DateTime.now().millisecondsSinceEpoch - time).abs(),
      lessThan(1000),
    );
    expect(w.connectedEars, {left, right});
  });

  test('factory requires the vendor service and excludes charging cases',
      () async {
    final factory = OmniBudsFactory();
    DiscoveredDevice device(String name) => DiscoveredDevice(
          id: 'id',
          name: name,
          manufacturerData: Uint8List(0),
          rssi: -50,
          serviceUuids: [],
        );
    final services = [BleService(OmniBudsGatt.service, [])];
    expect(await factory.matches(device('OmniBuds-FF03'), services), true);
    expect(
      await factory.matches(device('OmniBuds-Case-FF03'), services),
      false,
    );
    expect(await factory.matches(device('OmniBuds-FF03'), []), false);
  });
}
