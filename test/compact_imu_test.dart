import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/v2_sensor_value_parser.dart';

void main() {
  final scheme = SensorScheme(0, 'IMU', 9, null);
  for (final group in ['ACCELEROMETER', 'GYROSCOPE', 'MAGNETOMETER']) {
    for (final axis in ['X', 'Y', 'Z']) {
      scheme.components.add(Component(
          ParseType.float,
          group,
          axis,
          group == 'ACCELEROMETER'
              ? 'm/s^2'
              : group == 'GYROSCOPE'
                  ? 'dps'
                  : 'uT',),);
    }
  }

  ByteData packet(int count, {bool compact = true}) {
    final width = compact ? 24 : 36;
    final b = ByteData(10 + count * width + (count > 1 ? 2 : 0));
    b.setUint8(0, compact ? 0x80 : 0);
    b.setUint8(1, b.lengthInBytes - 10);
    b.setUint64(2, 0x100000010, Endian.little);
    for (var n = 0; n < count; n++) {
      for (var i = 0; i < 6; i++) {
        if (compact) {
          b.setInt16(
              10 + n * width + i * 2, i.isEven ? -32768 : 32767, Endian.little,);
        } else {
          b.setFloat32(10 + n * width + i * 4, 1.25, Endian.little);
        }
      }
      for (var i = 0; i < 3; i++) {
        b.setFloat32(
            10 + n * width + (compact ? 12 : 24) + i * 4, 42.5, Endian.little,);
      }
    }
    if (count > 1) b.setUint16(b.lengthInBytes - 2, 10000, Endian.little);
    return b;
  }

  test(
      'compact batches preserve physical units, sign and microsecond timestamps',
      () {
    for (final count in [1, 2, 9]) {
      final result = V2SensorValueParser().parse(packet(count), [scheme]);
      expect(result.length, count);
      for (var n = 0; n < count; n++) {
        expect(result[n]['timestamp'], 0x100000010 + n * 10000);
        expect(result[n]['sensorId'], 0);
        expect(result[n]['ACCELEROMETER']['X'], closeTo(-19.6133, 1e-6));
        expect(
            result[n]['GYROSCOPE']['X'], closeTo(32767 * 2000 / 32768, 1e-6),);
        expect(result[n]['MAGNETOMETER']['Z'], 42.5);
        expect(result[n]['ACCELEROMETER']['units']['X'], 'm/s^2');
      }
    }
  });
  test('legacy single and batched float samples still decode', () {
    for (final count in [1, 6]) {
      final result =
          V2SensorValueParser().parse(packet(count, compact: false), [scheme]);
      expect(result.length, count);
      expect(result.last['ACCELEROMETER']['X'], 1.25);
      expect(result.last['timestamp'], 0x100000010 + (count - 1) * 10000);
    }
  });
  test('truncated compact data and incompatible schemas are rejected', () {
    final bytes = packet(2).buffer.asUint8List();
    expect(
        () => V2SensorValueParser()
            .parse(ByteData.sublistView(bytes, 0, bytes.length - 1), [scheme]),
        throwsFormatException,);
    final invalid = SensorScheme(0, 'bad', 1, null)
      ..components.add(Component(ParseType.int16, 'A', 'X', 'raw'));
    expect(() => V2SensorValueParser().parse(packet(1), [invalid]),
        throwsFormatException,);
  });
}
