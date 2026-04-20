import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/open_ring_value_parser.dart';

void main() {
  group('OpenRingValueParser', () {
    test('parses 6-axis IMU frames as raw little-endian values', () {
      final parser = OpenRingValueParser();
      final frame = Uint8List.fromList(<int>[
        0x00,
        0x01,
        0x40,
        0x06,
        0xE8,
        0x03,
        0x18,
        0xFC,
        0xFA,
        0x00,
        0x2C,
        0x01,
        0xD4,
        0xFE,
        0x2A,
        0x00,
      ]);

      final result = parser.parse(ByteData.sublistView(frame), const []);

      expect(result, hasLength(1));
      expect(result.single['Accelerometer'], <String, dynamic>{
        'X': 1000,
        'Y': -1000,
        'Z': 250,
      });
      expect(result.single['Gyroscope'], <String, dynamic>{
        'X': 300,
        'Y': -300,
        'Z': 42,
      });
    });

    test(
      'parses vendor Q2 waveform samples with raw accelerometer payload',
      () {
        final parser = OpenRingValueParser();
        final frame = Uint8List.fromList(<int>[
          0x00,
          0x02,
          0x32,
          0x01,
          0x07,
          0x01,
          0x04,
          0x03,
          0x02,
          0x01,
          0x08,
          0x07,
          0x06,
          0x05,
          0x34,
          0x12,
          0x78,
          0x56,
          0xBC,
          0x9A,
        ]);

        final result = parser.parse(ByteData.sublistView(frame), const []);

        expect(result, hasLength(1));
        expect(result.single['PPG'], <String, dynamic>{
          'Green': 0,
          'Red': 0x01020304,
          'Infrared': 0x05060708,
        });
        expect(result.single['Accelerometer'], <String, dynamic>{
          'X': 0x1234,
          'Y': 0x5678,
          'Z': -25924,
        });
      },
    );

    test('accepts vendor final Q2 result packets with value 1', () {
      final parser = OpenRingValueParser();
      final frame = Uint8List.fromList(<int>[
        0x00,
        0x03,
        0x32,
        0x00,
        0x01,
        97,
        61,
        32,
      ]);

      final result = parser.parse(ByteData.sublistView(frame), const []);

      expect(result, isEmpty);
    });
  });
}
