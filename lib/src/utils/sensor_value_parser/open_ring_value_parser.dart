import 'dart:typed_data';

import '../../../open_earable_flutter.dart' show logger;
import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class OpenRingValueParser extends SensorValueParser {
  // 50 Hz -> 20 ms per sample
  static const int _samplePeriodMs = 20;
  // IMU (cmd=0x40) accelerometer channels are reported in milli-g.
  static const double _imuAccRawToGScale = 1000.0;
  // PPG realtime (cmd=0x32) carries accelerometer with half-scale raw counts.
  static const double _ppgAccRawToGScale = 500.0;
  // OpenRing realtime temperature channels are provided in milli-degrees C.
  static const double _tempRawToCelsiusScale = 1000.0;

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

    final int receiveTs =
        _lastTsByCmd[cmd] ?? DateTime.now().millisecondsSinceEpoch;
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
    if (subOpcode == 0x00) {
      return const [];
    }
    if (subOpcode != 0x01 && subOpcode != 0x04 && subOpcode != 0x06) {
      return const [];
    }

    // Firmware variants differ in IMU stream framing:
    // - Variant A: [00,seq,40,sub,status,payload...]
    // - Variant B: [00,seq,40,sub,payload...]
    // Parse both layouts and keep whichever yields more full samples.
    int? statusWithLayout;
    List<Map<String, dynamic>> withStatusLayout = const [];
    if (frame.lengthInBytes >= 5) {
      statusWithLayout = frame.getUint8(4);
      final ByteData payloadWithStatus = frame.lengthInBytes > 5
          ? ByteData.sublistView(frame, 5)
          : ByteData.sublistView(frame, 5, 5);
      withStatusLayout = _parseImuSamples(
        subOpcode: subOpcode,
        payload: payloadWithStatus,
        receiveTs: receiveTs,
        baseHeader: {
          'sequenceNum': sequenceNum,
          'cmd': cmd,
          'subOpcode': subOpcode,
          'status': statusWithLayout,
        },
      );
    }

    List<Map<String, dynamic>> withoutStatusLayout = const [];
    if (frame.lengthInBytes > 4) {
      final ByteData payloadWithoutStatus = ByteData.sublistView(frame, 4);
      withoutStatusLayout = _parseImuSamples(
        subOpcode: subOpcode,
        payload: payloadWithoutStatus,
        receiveTs: receiveTs,
        baseHeader: {
          'sequenceNum': sequenceNum,
          'cmd': cmd,
          'subOpcode': subOpcode,
          // Keep a neutral status marker for inferred no-status layout.
          'status': 0x00,
        },
      );
    }

    if (withoutStatusLayout.length > withStatusLayout.length) {
      return withoutStatusLayout;
    }
    if (withStatusLayout.isNotEmpty) {
      return withStatusLayout;
    }
    if (withoutStatusLayout.isNotEmpty) {
      return withoutStatusLayout;
    }

    // Common busy ACK: [00, seq, 40, subOpcode, 0x01]
    if (statusWithLayout == 0x01 && frame.lengthInBytes == 5) {
      return const [];
    }

    return const [];
  }

  List<Map<String, dynamic>> _parseImuSamples({
    required int subOpcode,
    required ByteData payload,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    switch (subOpcode) {
      case 0x01:
      case 0x04:
        return _parseAccelOnly(
          data: payload,
          receiveTs: receiveTs,
          baseHeader: baseHeader,
          samplePeriodMs: _samplePeriodMs,
        );
      case 0x06:
        return _parseAccelGyro(
          data: payload,
          receiveTs: receiveTs,
          baseHeader: baseHeader,
          samplePeriodMs: _samplePeriodMs,
        );
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
      // Q2 control acks can be 4-byte frames (e.g. stop ack type=0x06).
      if (frame.lengthInBytes == 4) {
        return const [];
      }
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
      if (value == 1) {
        // Legacy Q2 state packet: ignore.
        return const [];
      }
      if (value == 0 || value == 2 || value == 4) {
        final String reason = switch (value) {
          0 => 'not worn',
          2 => 'charging',
          4 => 'busy',
          _ => 'unknown',
        };
        logger.w('OpenRing PPG error packet received: code=$value ($reason)');
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
        final int temp = frame.getUint16(7, Endian.little);

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

      final List<Map<String, dynamic>> waveform14 = _parsePpgWaveform(
        data: waveformPayload,
        nSamples: nSamples,
        receiveTs: receiveTs,
        baseHeader: baseHeader,
      );
      if (waveform14.isEmpty && nSamples > 0) {
        logger.w(
          'OpenRing PPG waveform length mismatch '
          '(type=0x01, nSamples=$nSamples, payloadLen=${waveformPayload.lengthInBytes})',
        );
      }
      return waveform14;
    }

    if (type == 0x02) {
      if (frame.lengthInBytes < 6) {
        throw Exception(
          'PPG extended waveform frame too short: ${frame.lengthInBytes}',
        );
      }

      final int nSamples = frame.getUint8(5);
      final ByteData waveformPayload = ByteData.sublistView(frame, 6);

      final List<Map<String, dynamic>> realtimeType2 =
          _parsePpgWaveformType2Realtime30(
        data: waveformPayload,
        nSamples: nSamples,
        receiveTs: receiveTs,
        baseHeader: baseHeader,
      );
      if (realtimeType2.isNotEmpty) {
        return realtimeType2;
      }

      return const [];
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

      final Map<String, dynamic> accelData = _parseAccelerometerComp(accBytes);
      final Map<String, dynamic> gyroData = _parseGyroscopeComp(gyroBytes);

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'Accelerometer': accelData,
        'Gyroscope': gyroData,
      });
    }
    return parsedData;
  }

  List<Map<String, dynamic>> _parseAccelOnly({
    required ByteData data,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
    required int samplePeriodMs,
  }) {
    final int usableBytes = data.lengthInBytes - (data.lengthInBytes % 6);
    if (usableBytes == 0) {
      return const [];
    }

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < usableBytes; i += 6) {
      final int sampleIndex = i ~/ 6;
      final int ts = receiveTs + (sampleIndex + 1) * samplePeriodMs;

      final ByteData sample = ByteData.sublistView(data, i, i + 6);
      final Map<String, dynamic> accelData = _parseAccelerometerComp(sample);

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'Accelerometer': accelData,
      });
    }
    return parsedData;
  }

  Map<String, dynamic> _parseAccelerometerComp(
    ByteData data, {
    double rawToGScale = _imuAccRawToGScale,
  }) {
    return {
      'X': data.getInt16(0, Endian.little) / rawToGScale,
      'Y': data.getInt16(2, Endian.little) / rawToGScale,
      'Z': data.getInt16(4, Endian.little) / rawToGScale,
    };
  }

  Map<String, dynamic> _parseGyroscopeComp(ByteData data) {
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
    if (nSamples == 0) {
      return const [];
    }

    const int sampleSize = 14;
    final int expectedBytes = nSamples * sampleSize;
    if (data.lengthInBytes < expectedBytes) {
      return const [];
    }
    final ByteData exactSamples = ByteData.sublistView(data, 0, expectedBytes);

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < nSamples; i++) {
      final int offset = i * sampleSize;
      final int ts = receiveTs + (i + 1) * _samplePeriodMs;

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'PPG': {
          'Green': 0,
          'Red': exactSamples.getUint32(offset, Endian.little),
          'Infrared': exactSamples.getUint32(offset + 4, Endian.little),
        },
        // Legacy Q2 waveform packets also carry accelerometer payload
        // (bytes 8..13 in each 14-byte sample).
        'Accelerometer': _parseAccelerometerComp(
          ByteData.sublistView(exactSamples, offset + 8, offset + 14),
          rawToGScale: _ppgAccRawToGScale,
        ),
      });
    }

    return parsedData;
  }

  List<Map<String, dynamic>> _parsePpgWaveformType2Realtime30({
    required ByteData data,
    required int nSamples,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    // Observed OpenRing type-0x02 packet:
    // [8-byte timestamp][n * 30-byte samples]
    // sample bytes (LE):
    //   0..3   green uint32
    //   4..7   red uint32
    //   8..11  infrared uint32
    //   12..17 accX/accY/accZ int16
    //   18..23 gyroX/gyroY/gyroZ int16
    //   24..29 temp0/temp1/temp2 uint16 (milli-degC)
    const int headerSize = 8;
    const int sampleSize = 30;

    if (nSamples == 0 || data.lengthInBytes <= headerSize) {
      return const [];
    }

    final ByteData sampleData = ByteData.sublistView(data, headerSize);
    final int expectedPayloadBytes = nSamples * sampleSize;
    if (sampleData.lengthInBytes != expectedPayloadBytes) {
      // Guard against mis-parsing legacy type-0x02 payload layouts as the
      // realtime30 format. Fallback parser handles those variants.
      return const [];
    }

    final int usableSamples = nSamples;

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < usableSamples; i++) {
      final int offset = i * sampleSize;
      final int ts = receiveTs + (i + 1) * _samplePeriodMs;

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'PPG': {
          'Green': sampleData.getUint32(offset, Endian.little),
          'Red': sampleData.getUint32(offset + 4, Endian.little),
          'Infrared': sampleData.getUint32(offset + 8, Endian.little),
        },
        'Accelerometer': _parseAccelerometerComp(
          ByteData.sublistView(sampleData, offset + 12, offset + 18),
          rawToGScale: _ppgAccRawToGScale,
        ),
        'Gyroscope': {
          'X': sampleData.getInt16(offset + 18, Endian.little),
          'Y': sampleData.getInt16(offset + 20, Endian.little),
          'Z': sampleData.getInt16(offset + 22, Endian.little),
        },
        'Temperature': {
          'Temp0': (sampleData.getUint16(offset + 24, Endian.little) /
                  _tempRawToCelsiusScale)
              .round(),
          'Temp1': (sampleData.getUint16(offset + 26, Endian.little) /
                  _tempRawToCelsiusScale)
              .round(),
          'Temp2': (sampleData.getUint16(offset + 28, Endian.little) /
                  _tempRawToCelsiusScale)
              .round(),
          'units': '°C',
        },
      });
    }

    return parsedData;
  }
}
