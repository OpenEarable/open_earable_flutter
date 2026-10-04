import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/v2_sensor_value_parser.dart';

const channels = ['Red', 'Infrared', 'Green', 'Ambient'];
const timestamp = 1700000000123456;

class UnusedBle extends Fake implements BleGattManager {}

final scheme = SensorScheme(4, 'PPG', 4, null)
  ..components = [
    for (final name in channels)
      Component(ParseType.uint32, 'PPG', name, 'raw'),
  ];

ByteData packet(
  List<List<int>> samples, {
  required bool compact,
  int period = 1953,
}) {
  final width = compact ? 10 : 16;
  final data =
      ByteData(10 + samples.length * width + (samples.length > 1 ? 2 : 0));
  data.setUint8(0, 4);
  data.setUint8(1, data.lengthInBytes - 10);
  data.setUint32(2, timestamp % 0x100000000, Endian.little);
  data.setUint32(6, timestamp ~/ 0x100000000, Endian.little);
  for (var n = 0; n < samples.length; n++) {
    if (compact) {
      // Independent reference packing, including on Dart web.
      var bits = BigInt.zero;
      for (var c = 0; c < 4; c++) {
        bits |= BigInt.from(samples[n][c]) << (19 * c);
      }
      for (var b = 0; b < 10; b++) {
        data.setUint8(
          10 + n * width + b,
          ((bits >> (8 * b)) & BigInt.from(255)).toInt(),
        );
      }
    } else {
      for (var c = 0; c < 4; c++) {
        data.setUint32(10 + n * width + 4 * c, samples[n][c], Endian.little);
      }
    }
  }
  if (samples.length > 1) {
    data.setUint16(data.lengthInBytes - 2, period, Endian.little);
  }
  return data;
}

void expectSamples(
  V2SensorValueParser parser,
  ByteData bytes,
  List<List<int>> expected,
) {
  final result = parser.parse(bytes, [scheme]);
  expect(result, hasLength(expected.length));
  for (var n = 0; n < result.length; n++) {
    expect(result[n]['sensorId'], 4);
    expect(result[n]['timestamp'], timestamp + n * 1953);
    for (var c = 0; c < 4; c++) {
      expect(result[n]['PPG'][channels[c]], expected[n][c]);
    }
  }
}

void main() {
  test('device support range retains older firmware and accepts all 2.3.x', () {
    final wearable = OpenEarableV2(
      name: 'Test',
      disconnectNotifier: WearableDisconnectNotifier(),
      sensors: [],
      sensorConfigurations: [],
      bleManager: UnusedBle(),
      discoveredDevice: DiscoveredDevice(
        id: 'test',
        name: 'Test',
        manufacturerData: Uint8List(0),
        rssi: -40,
        serviceUuids: [],
      ),
    );
    for (final version in [
      '2.1.0',
      '2.2.9',
      '2.2.10',
      '2.3.0-dev.1+gabc',
      '2.3.0',
      '2.3.99',
    ]) {
      expect(
        wearable.supportedFirmwareRange.allows(semver.Version.parse(version)),
        isTrue,
      );
    }
    expect(
      wearable.supportedFirmwareRange.allows(semver.Version(2, 4, 0)),
      isFalse,
    );
  });

  test(
      'selects compact BLE data by each device firmware, including prereleases',
      () {
    for (final version in ['2.1.0', '2.2.9', '2.2.10', '2.2.10-dev.3+gabc']) {
      expect(V2SensorValueParser.forFirmware(version).compactPpg, isFalse);
    }
    for (final version in ['2.3.0', '2.3.0-dev.1+gabc', '2.3.99']) {
      expect(V2SensorValueParser.forFirmware(version).compactPpg, isTrue);
    }
  });

  test('retains every channel bit and timestamps in maximum-sized batches', () {
    final random = Random(318);
    for (var run = 0; run < 100; run++) {
      final samples = List.generate(
        23,
        (_) => List.generate(4, (_) => random.nextInt(1 << 19)),
      );
      samples[0] = [0, 0x7ffff, 0x40000, 1];
      samples[1] = [0x7ffff, 0x7ffff, 0x7ffff, 0x7ffff];
      expectSamples(
        V2SensorValueParser.forFirmware('2.3.0'),
        packet(samples, compact: true),
        samples,
      );
    }
  });

  test('single sample fits a 20-byte notification and handles ByteData views',
      () {
    final samples = [
      [1, 2, 3, 4],
    ];
    final bytes = packet(samples, compact: true);
    expect(bytes.lengthInBytes, 20);
    expect(
      bytes.buffer.asUint8List().sublist(10),
      [1, 0, 16, 0, 192, 0, 0, 8, 0, 0],
    );
    final storage = Uint8List(30)..setRange(5, 25, bytes.buffer.asUint8List());
    expectSamples(
      V2SensorValueParser.forFirmware('2.3.0'),
      ByteData.sublistView(storage, 5, 25),
      samples,
    );
  });

  test('mixed-version peers independently decode equal-length packets', () {
    final oldSamples = List.generate(5, (i) => [i, i + 1, i + 2, i + 3]);
    final newSamples = List.generate(8, (i) => [i, i + 1, i + 2, i + 3]);
    final oldPacket = packet(oldSamples, compact: false);
    final newPacket = packet(newSamples, compact: true);
    expect(oldPacket.lengthInBytes, newPacket.lengthInBytes);
    for (var i = 0; i < 3; i++) {
      expectSamples(
        V2SensorValueParser.forFirmware('2.2.9'),
        oldPacket,
        oldSamples,
      );
      expectSamples(
        V2SensorValueParser.forFirmware('2.3.0'),
        newPacket,
        newSamples,
      );
    }
    // File/SD decoding uses the legacy default even for recordings from 2.3.x.
    expectSamples(V2SensorValueParser(), oldPacket, oldSamples);
  });

  test('rejects malformed compact packets without emitting partial results',
      () {
    final parser = V2SensorValueParser.forFirmware('2.3.0');
    final samples = [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
    ];
    final badLength = packet(samples, compact: true)..setUint8(1, 10);
    final badReserved = packet(samples, compact: true)..setUint8(29, 0x80);
    final badPeriod = packet(samples, compact: true, period: 0);
    for (final malformed in [badLength, badReserved, badPeriod]) {
      expect(() => parser.parse(malformed, [scheme]), throwsFormatException);
    }
    final good = packet(samples, compact: true);
    for (var length = 0; length < good.lengthInBytes; length++) {
      expect(
        () => parser.parse(ByteData.sublistView(good, 0, length), [scheme]),
        throwsFormatException,
      );
    }
  });

  test('2.3 parser leaves non-PPG sensor decoding unchanged', () {
    final temperature = SensorScheme(6, 'Temperature', 1, null)
      ..components = [Component(ParseType.float, 'Temperature', 'value', 'C')];
    final bytes = ByteData(14)
      ..setUint8(0, 6)
      ..setUint8(1, 4)
      ..setUint32(2, 123, Endian.little)
      ..setFloat32(10, 36.5, Endian.little);
    expect(
      V2SensorValueParser.forFirmware('2.3.0').parse(bytes, [temperature]),
      V2SensorValueParser.forFirmware('2.2.9').parse(bytes, [temperature]),
    );
  });
}
