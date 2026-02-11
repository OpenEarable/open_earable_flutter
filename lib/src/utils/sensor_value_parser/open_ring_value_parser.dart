import 'dart:typed_data';

import '../../../open_earable_flutter.dart' show logger;
import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class OpenRingValueParser extends SensorValueParser {
  // 100 Hz -> 10 ms per sample
  static const int _samplePeriodMs = 10;

  final Map<int, int> _lastSeqByCmd = {};
  final Map<int, int> _lastTsByCmd = {};

  @override
  List<Map<String, dynamic>> parse(
    ByteData data,
    List<SensorScheme> sensorSchemes,
  ) {
    if (data.lengthInBytes < 4) {
      throw Exception('Data too short to parse');
    }

    final int framePrefix = data.getUint8(0);
    if (framePrefix != 0x00) {
      throw Exception('Invalid frame prefix: $framePrefix');
    }

    final int sequenceNum = data.getUint8(1);
    final int cmd = data.getUint8(2);

    final int receiveTs = _lastTsByCmd[cmd] ?? 0;
    _lastSeqByCmd[cmd] = sequenceNum;

    List<Map<String, dynamic>> result;
    switch (cmd) {
      case 0x40: // IMU
        result = _parseImuFrame(data, sequenceNum, cmd, receiveTs);
        break;
      case 0x32: // PPG Q2
        result = _parsePpgFrame(data, sequenceNum, cmd, receiveTs);
        break;
      default:
        return const [];
    }

    if (result.isNotEmpty) {
      final int updatedTs = result.last['timestamp'] as int;
      _lastTsByCmd[cmd] = updatedTs;
    }

    return result;
  }

  List<Map<String, dynamic>> _parseImuFrame(
    ByteData frame,
    int sequenceNum,
    int cmd,
    int receiveTs,
  ) {
    if (frame.lengthInBytes < 4) {
      throw Exception('IMU frame too short: ${frame.lengthInBytes}');
    }

    final int subOpcode = frame.getUint8(3);
    if (frame.lengthInBytes < 5) {
      if (subOpcode == 0x00) {
        return const [];
      }
      throw Exception('IMU frame missing status byte: ${frame.lengthInBytes}');
    }

    final int status = frame.getUint8(4);
    final ByteData payload = frame.lengthInBytes > 5
        ? ByteData.sublistView(frame, 5)
        : ByteData.sublistView(frame, 5, 5);

    final Map<String, dynamic> baseHeader = {
      'sequenceNum': sequenceNum,
      'cmd': cmd,
      'subOpcode': subOpcode,
      'status': status,
    };

    switch (subOpcode) {
      case 0x01: // Accel-only stream (ignored by design)
      case 0x04: // Accel-only stream (ignored by design)
        if (status == 0x01) {
          return const [];
        }
        return const [];
      case 0x06: // Accel + Gyro (12 bytes per sample)
        if (status == 0x01) {
          return const [];
        }
        return _parseAccelGyro(
          data: payload,
          receiveTs: receiveTs,
          baseHeader: baseHeader,
          samplePeriodMs: _samplePeriodMs,
        );
      case 0x00:
        // Common non-streaming/control response.
        return const [];
      default:
        return const [];
    }
  }

  List<Map<String, dynamic>> _parsePpgFrame(
    ByteData frame,
    int sequenceNum,
    int cmd,
    int receiveTs,
  ) {
    if (frame.lengthInBytes < 5) {
      throw Exception('PPG frame too short: ${frame.lengthInBytes}');
    }

    final int type = frame.getUint8(3);
    final int value = frame.getUint8(4);

    final Map<String, dynamic> baseHeader = {
      'sequenceNum': sequenceNum,
      'cmd': cmd,
      'type': type,
      'value': value,
    };

    if (type == 0xFF) {
      logger.d('OpenRing PPG progress: $value%');
      if (value >= 100) {
        logger.d('OpenRing PPG progress complete');
      }
      return const [];
    }

    if (type == 0x00) {
      if (value == 0 || value == 2 || value == 4) {
        logger.w('OpenRing PPG error packet received: code=$value');
        return const [];
      }

      if (value == 3) {
        if (frame.lengthInBytes < 9) {
          throw Exception(
            'Invalid final PPG result length: ${frame.lengthInBytes}',
          );
        }

        final int heart = frame.getUint8(5);
        final int q2 = frame.getUint8(6);
        final int temp = frame.getInt16(7, Endian.little);

        logger.d(
          'OpenRing PPG result received: heart=$heart q2=$q2 temp=$temp',
        );
        return const [];
      }

      logger.w('OpenRing PPG result packet with unknown value=$value');
      return const [];
    }

    if (type == 0x01) {
      if (frame.lengthInBytes < 6) {
        throw Exception('PPG waveform frame too short: ${frame.lengthInBytes}');
      }

      final int nSamples = frame.getUint8(5);
      final ByteData waveformPayload = ByteData.sublistView(frame, 6);

      return _parsePpgWaveform(
        data: waveformPayload,
        nSamples: nSamples,
        receiveTs: receiveTs,
        baseHeader: baseHeader,
      );
    }

    if (type == 0x02) {
      if (frame.lengthInBytes < 6) {
        throw Exception(
          'PPG extended waveform frame too short: ${frame.lengthInBytes}',
        );
      }

      final int nSamples = frame.getUint8(5);
      final ByteData waveformPayload = ByteData.sublistView(frame, 6);

      return _parsePpgWaveformType2(
        data: waveformPayload,
        nSamples: nSamples,
        receiveTs: receiveTs,
        baseHeader: baseHeader,
      );
    }

    return const [];
  }

  List<Map<String, dynamic>> _parseAccelGyro({
    required ByteData data,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
    required int samplePeriodMs,
  }) {
    final int usableBytes = data.lengthInBytes - (data.lengthInBytes % 12);
    if (usableBytes == 0) {
      return const [];
    }

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < usableBytes; i += 12) {
      final int sampleIndex = i ~/ 12;
      final int ts = receiveTs + (sampleIndex + 1) * samplePeriodMs;

      final ByteData sample = ByteData.sublistView(data, i, i + 12);
      final ByteData accBytes = ByteData.sublistView(sample, 0, 6);
      final ByteData gyroBytes = ByteData.sublistView(sample, 6);

      final Map<String, dynamic> accelData = _parseImuComp(accBytes);
      final Map<String, dynamic> gyroData = _parseImuComp(gyroBytes);

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'Accelerometer': accelData,
        'Gyroscope': gyroData,
      });
    }
    return parsedData;
  }

  Map<String, dynamic> _parseImuComp(ByteData data) {
    return {
      'X': data.getInt16(0, Endian.little),
      'Y': data.getInt16(2, Endian.little),
      'Z': data.getInt16(4, Endian.little),
    };
  }

  List<Map<String, dynamic>> _parsePpgWaveform({
    required ByteData data,
    required int nSamples,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    final int expectedBytes = nSamples * 14;
    final int usableBytes = data.lengthInBytes - (data.lengthInBytes % 14);
    if (usableBytes == 0 || nSamples == 0) {
      return const [];
    }

    int usableSamples = usableBytes ~/ 14;
    if (usableSamples > nSamples) {
      usableSamples = nSamples;
    }

    if (data.lengthInBytes != expectedBytes && nSamples > usableSamples) {
      logger.w(
        'PPG waveform length mismatch len=${data.lengthInBytes} expected=$expectedBytes; parsing $usableSamples sample(s)',
      );
    }

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < usableSamples; i++) {
      final int offset = i * 14;
      final int ts = receiveTs + (i + 1) * _samplePeriodMs;

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'PPG': {
          'Red': data.getInt32(offset, Endian.little),
          'Infrared': data.getInt32(offset + 4, Endian.little),
          'AccX': data.getInt16(offset + 8, Endian.little),
          'AccY': data.getInt16(offset + 10, Endian.little),
          'AccZ': data.getInt16(offset + 12, Endian.little),
        },
      });
    }

    return parsedData;
  }

  List<Map<String, dynamic>> _parsePpgWaveformType2({
    required ByteData data,
    required int nSamples,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    // Observed packet type 0x02 layout:
    // [sampleCount][n * 34-byte samples]
    // sample bytes (LE):
    //   0..3   unknown int32
    //   4..7   red int32
    //   8..11  infrared int32
    //   12..19 unknown int32 x2
    //   20..25 accX/accY/accZ int16
    //   26..33 unknown tail (4x int16/uint16)
    const int sampleSize = 34;

    final int expectedBytes = nSamples * sampleSize;
    final int usableBytes =
        data.lengthInBytes - (data.lengthInBytes % sampleSize);
    if (usableBytes == 0 || nSamples == 0) {
      return const [];
    }

    int usableSamples = usableBytes ~/ sampleSize;
    if (usableSamples > nSamples) {
      usableSamples = nSamples;
    }

    if (data.lengthInBytes != expectedBytes && nSamples > usableSamples) {
      logger.w(
        'PPG type2 length mismatch len=${data.lengthInBytes} expected=$expectedBytes; parsing $usableSamples sample(s)',
      );
    }

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < usableSamples; i++) {
      final int offset = i * sampleSize;
      final int ts = receiveTs + (i + 1) * _samplePeriodMs;

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'PPG': {
          'Red': data.getInt32(offset + 4, Endian.little),
          'Infrared': data.getInt32(offset + 8, Endian.little),
          'AccX': data.getInt16(offset + 20, Endian.little),
          'AccY': data.getInt16(offset + 22, Endian.little),
          'AccZ': data.getInt16(offset + 24, Endian.little),
        },
      });
    }

    return parsedData;
  }
}
