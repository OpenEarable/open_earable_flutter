import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/v2_sensor_value_parser.dart';

const groups = ['ACCELEROMETER', 'GYROSCOPE', 'MAGNETOMETER'];
const units = ['m/s^2', 'dps', 'uT'];
const axes = ['X', 'Y', 'Z'];
final scheme = SensorScheme(0, '9-Axis IMU', 9, null)
  ..components = [
    for (var group = 0; group < 3; group++)
      for (final axis in axes)
        Component(ParseType.float, groups[group], axis, units[group]),
  ];
double f32(double value) => (ByteData(4)..setFloat32(0, value, Endian.little))
    .getFloat32(0, Endian.little);

ByteData packet(List<List<int>> samples, {required bool compact}) {
  final width = compact ? 24 : 36;
  final data =
      ByteData(10 + samples.length * width + (samples.length > 1 ? 2 : 0))
        ..setUint8(0, 0)
        ..setUint32(2, 123456, Endian.little);
  data.setUint8(1, data.lengthInBytes - 10);
  for (var i = 0; i < samples.length; i++) {
    for (var axis = 0; axis < 6; axis++) {
      if (compact) {
        data.setInt16(
          10 + i * width + 2 * axis,
          samples[i][axis],
          Endian.little,
        );
      } else {
        // Independently reproduce the existing sensor's float32 calculation.
        final scale =
            axis < 3 ? f32(2.0 * f32(9.80665)) / 32768.0 : 2000.0 / 32768.0;
        data.setFloat32(
          10 + i * width + 4 * axis,
          samples[i][axis] * scale,
          Endian.little,
        );
      }
    }
    for (var axis = 0; axis < 3; axis++) {
      data.setFloat32(
        10 + i * width + width - 12 + axis * 4,
        [12.345, -67.89, -0.0][axis],
        Endian.little,
      );
    }
  }
  if (samples.length > 1) {
    data.setUint16(data.lengthInBytes - 2, 10000, Endian.little);
  }
  return data;
}

void main() {
  final compact = V2SensorValueParser.forFirmware('2.3.0');
  final legacy = V2SensorValueParser.forFirmware('2.2.9');

  test('firmware selects compact IMU per connection; files retain legacy', () {
    for (final version in ['2.1.0', '2.2.9', '2.2.10', '2.2.10-dev.1']) {
      expect(V2SensorValueParser.forFirmware(version).compactImu, isFalse);
    }
    for (final version in ['2.3.0', '2.3.0-dev.1+gabc', '2.3.99']) {
      expect(V2SensorValueParser.forFirmware(version).compactImu, isTrue);
    }
    expect(V2SensorValueParser().compactImu, isFalse);
  });

  test('all int16 counts reconstruct the exact existing floats', () {
    for (var raw = -32768; raw <= 32767; raw += 6) {
      final samples = [
        for (var n = raw; n <= min(raw + 5, 32767); n++) List.filled(6, n),
      ];
      expect(
        compact.parse(packet(samples, compact: true), [scheme]),
        legacy.parse(packet(samples, compact: false), [scheme]),
      );
    }
  });

  test(
      'axis order, units, float types, signed limits, timestamps and views remain unchanged',
      () {
    final samples =
        List.generate(6, (i) => [-32768 + i, 32767 - i, -i, i, 12345, -23456]);
    final bytes = packet(samples, compact: true);
    final storage = Uint8List(bytes.lengthInBytes + 7)
      ..setRange(3, 3 + bytes.lengthInBytes, bytes.buffer.asUint8List());
    final result = compact.parse(
      ByteData.sublistView(storage, 3, 3 + bytes.lengthInBytes),
      [scheme],
    );
    expect(result, legacy.parse(packet(samples, compact: false), [scheme]));
    for (var i = 0; i < result.length; i++) {
      expect(result[i]['timestamp'], 123456 + 10000 * i);
      for (var group = 0; group < 3; group++) {
        for (var axis = 0; axis < 3; axis++) {
          expect(result[i][groups[group]][axes[axis]], isA<double>());
          expect(scheme.components[group * 3 + axis].unitName, units[group]);
          expect(scheme.components[group * 3 + axis].type, ParseType.float);
        }
      }
      expect((result[i]['MAGNETOMETER']['Z'] as double).isNegative, isTrue);
    }
    expect(
      V2SensorValueParser().parse(packet(samples, compact: false), [scheme]),
      result,
    );
  });

  test(
      'nine-sample packets and single samples decode; mixed equal lengths do not select format',
      () {
    final samples = List.generate(9, (i) => List.filled(6, i));
    final bytes = packet(samples, compact: true);
    expect(bytes.lengthInBytes, 228);
    final parsed = compact.parse(bytes, [scheme]);
    expect(parsed, hasLength(9));
    expect(parsed.last['timestamp'], 203456);
    final oldBytes = packet(samples.sublist(0, 6), compact: false);
    expect(oldBytes.lengthInBytes, bytes.lengthInBytes);
    for (var i = 0; i < 3; i++) {
      expect(legacy.parse(oldBytes, [scheme]), parsed.sublist(0, 6));
      expect(compact.parse(bytes, [scheme]), parsed);
    }
    final one = packet(samples.sublist(0, 1), compact: true);
    expect(one.lengthInBytes, 34);
    expect(compact.parse(one, [scheme]), parsed.sublist(0, 1));
  });

  test('rejects truncated packets, bad lengths, zero periods and wrong schemes',
      () {
    final good = packet([List.filled(6, 0), List.filled(6, 1)], compact: true);
    for (var length = 0; length < good.lengthInBytes; length++) {
      expect(
        () => compact.parse(ByteData.sublistView(good, 0, length), [scheme]),
        throwsFormatException,
      );
    }
    final badLength =
        ByteData.sublistView(Uint8List.fromList(good.buffer.asUint8List()))
          ..setUint8(1, 1);
    final badPeriod =
        ByteData.sublistView(Uint8List.fromList(good.buffer.asUint8List()))
          ..setUint16(good.lengthInBytes - 2, 0, Endian.little);
    for (final bytes in [badLength, badPeriod]) {
      expect(() => compact.parse(bytes, [scheme]), throwsFormatException);
    }
    final wrongScheme = SensorScheme(0, 'Wrong', 1, null)
      ..components = [Component(ParseType.int16, 'Wrong', 'X', 'counts')];
    expect(() => compact.parse(good, [wrongScheme]), throwsFormatException);
  });
}
