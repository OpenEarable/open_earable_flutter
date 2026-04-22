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

    test('accepts final Q2 result packets with value 3', () {
      final parser = OpenRingValueParser();
      final frame = Uint8List.fromList(<int>[
        0x00,
        0x03,
        0x32,
        0x00,
        0x03,
        97,
        61,
        0x86,
        0x0E,
      ]);

      final result = parser.parse(ByteData.sublistView(frame), const []);

      expect(result, isEmpty);
    });

    test('parses Heart Rota green-only PPG waveform samples', () {
      final parser = OpenRingValueParser();
      final frame = Uint8List.fromList(<int>[
        0x00,
        0x05,
        0x31,
        0x01,
        0x09,
        0x01,
        0x04,
        0x03,
        0x02,
        0x01,
        0x34,
        0x12,
        0x78,
        0x56,
        0xBC,
        0x9A,
      ]);

      final result = parser.parse(ByteData.sublistView(frame), const []);

      expect(result, hasLength(1));
      expect(result.single['cmd'], 0x31);
      expect(result.single['PPG'], <String, dynamic>{'Green': 0x01020304});
      expect(result.single['Accelerometer'], <String, dynamic>{
        'X': 0x1234,
        'Y': 0x5678,
        'Z': -25924,
      });
    });

    test('parses PPG SHOUSHI green-only waveform samples', () {
      final parser = OpenRingValueParser();
      final frame = Uint8List.fromList(<int>[
        0x00,
        0x06,
        0x3D,
        0x01,
        0x0A,
        0x02,
        0x00,
        0x04,
        0x03,
        0x02,
        0x01,
        0x08,
        0x07,
        0x06,
        0x05,
      ]);

      final result = parser.parse(ByteData.sublistView(frame), const []);

      expect(result, hasLength(2));
      expect(result.first['cmd'], 0x3D);
      expect(result.first['waveType'], 0);
      expect(result.first['PPG'], <String, dynamic>{'Green': 0x01020304});
      expect(result.last['PPG'], <String, dynamic>{'Green': 0x05060708});
    });

    test('parses realtime PPG green channel waveform samples', () {
      final parser = OpenRingValueParser();
      final frame = Uint8List.fromList(<int>[
        0x00,
        0x07,
        0x3C,
        0x02,
        0x0B,
        0x01,
        0x88,
        0x77,
        0x66,
        0x55,
        0x44,
        0x33,
        0x22,
        0x11,
        0x04,
        0x03,
        0x02,
        0x01,
        0x08,
        0x07,
        0x06,
        0x05,
        0x0C,
        0x0B,
        0x0A,
        0x09,
        0x34,
        0x12,
        0x78,
        0x56,
        0xBC,
        0x9A,
        0x11,
        0x00,
        0x22,
        0x00,
        0x33,
        0x00,
        0xF0,
        0x00,
        0xC9,
        0x0E,
        0x92,
        0x10,
      ]);

      final result = parser.parse(ByteData.sublistView(frame), const []);

      expect(result, hasLength(1));
      expect(result.single['cmd'], 0x3C);
      expect(result.single['PPG'], <String, dynamic>{
        'Infrared': 0x01020304,
        'Red': 0x05060708,
        'Green': 0x090A0B0C,
      });
    });

    test(
        'parses realtime PPG packets with IR/red/green and centi-degree temperatures',
        () {
      final parser = OpenRingValueParser();
      final frame = Uint8List.fromList(<int>[
        0x00,
        0x04,
        0x32,
        0x02,
        0x07,
        0x01,
        0x88,
        0x77,
        0x66,
        0x55,
        0x44,
        0x33,
        0x22,
        0x11,
        0x04,
        0x03,
        0x02,
        0x01,
        0x08,
        0x07,
        0x06,
        0x05,
        0x0C,
        0x0B,
        0x0A,
        0x09,
        0x34,
        0x12,
        0x78,
        0x56,
        0xBC,
        0x9A,
        0x11,
        0x00,
        0x22,
        0x00,
        0x33,
        0x00,
        0xF0,
        0x00,
        0xC9,
        0x0E,
        0x92,
        0x10,
      ]);

      final result = parser.parse(ByteData.sublistView(frame), const []);

      expect(result, hasLength(1));
      expect(result.single['PPG'], <String, dynamic>{
        'Infrared': 0x01020304,
        'Red': 0x05060708,
        'Green': 0x090A0B0C,
      });
      expect(result.single['Accelerometer'], <String, dynamic>{
        'X': 0x1234,
        'Y': 0x5678,
        'Z': -25924,
      });
      expect(result.single['Gyroscope'], <String, dynamic>{
        'X': 17,
        'Y': 34,
        'Z': 51,
      });
      expect(result.single['Temperature'], <String, dynamic>{
        'Temp0': 2.4,
        'Temp1': 37.85,
        'Temp2': 42.42,
        'units': '°C',
      });
    });
  });
}
