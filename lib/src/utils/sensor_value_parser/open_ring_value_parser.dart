import 'dart:typed_data';

import '../../../open_earable_flutter.dart' show logger;
import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class OpenRingValueParser extends SensorValueParser {
  // 50 Hz -> 20 ms per sample
  static const int _samplePeriodMs = 20;
  // ChipletRing displays OpenRing temperature readings as centi-degrees C.
  static const double _tempRawToCelsiusScale = 100.0;

  final Map<int, int> _lastSeqByCmd = {};
  final Map<int, int> _lastTsByCmd = {};
  final Set<int> _loggedWaveformByCmd = {};

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
      case 0x31: // Heart/HRV green-only PPG
        result = _parseHeartRotaFrame(data, sequenceNum, cmd, receiveTs);
        break;
      case 0x3D: // PPG SHOUSHI green-only waveform
        result = _parsePpgShoushiFrame(data, sequenceNum, cmd, receiveTs);
        break;
      case 0x3C: // Realtime PPG with configurable LEDs
        result = _parseRealTimePpgFrame(data, sequenceNum, cmd, receiveTs);
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

      if (value == 1) {
        logger.w(
          'OpenRing PPG result packet with unsupported legacy value=1 '
          '(len=${frame.lengthInBytes})',
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

  List<Map<String, dynamic>> _parseHeartRotaFrame(
    ByteData frame,
    int sequenceNum,
    int cmd,
    int receiveTs,
  ) {
    if (frame.lengthInBytes < 5) {
      if (frame.lengthInBytes == 4) {
        return const [];
      }
      throw Exception('Heart Rota frame too short: ${frame.lengthInBytes}');
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
      logger.d('OpenRing heart progress: $value%');
      return const [];
    }

    if (type == 0x00) {
      if (value == 0 || value == 2 || value == 4 || value == 5) {
        final String reason = switch (value) {
          0 => 'not worn',
          2 => 'charging',
          4 => 'busy',
          5 => 'timeout',
          _ => 'unknown',
        };
        logger.w(
          'OpenRing heart measurement error packet received: '
          'code=$value ($reason)',
        );
        return const [];
      }

      if (value == 3) {
        if (frame.lengthInBytes < 10) {
          throw Exception(
            'Invalid final Heart Rota result length: ${frame.lengthInBytes}',
          );
        }

        final int heart = frame.getUint8(5);
        final int hrv = frame.getUint8(6);
        final int stress = frame.getUint8(7);
        final int temp = frame.getUint16(8, Endian.little);
        logger.d(
          'OpenRing heart result received: '
          'heart=$heart hrv=$hrv stress=$stress temp=$temp',
        );
      }
      return const [];
    }

    if (type == 0x01) {
      if (frame.lengthInBytes < 6) {
        throw Exception(
          'Heart Rota waveform frame too short: ${frame.lengthInBytes}',
        );
      }

      final int nSamples = frame.getUint8(5);
      final ByteData waveformPayload = ByteData.sublistView(frame, 6);
      final parsed = _parseHeartRotaWaveform(
        data: waveformPayload,
        nSamples: nSamples,
        receiveTs: receiveTs,
        baseHeader: baseHeader,
      );
      if (parsed.isEmpty && nSamples > 0) {
        logger.w(
          'OpenRing Heart Rota waveform length mismatch '
          '(nSamples=$nSamples, payloadLen=${waveformPayload.lengthInBytes})',
        );
      }
      return parsed;
    }

    // type 0x02 carries RRI values; keep it separate from optical PPG samples.
    logger.d(
      'OpenRing Heart Rota non-PPG packet ignored: '
      'type=$type value=$value len=${frame.lengthInBytes}',
    );
    return const [];
  }

  List<Map<String, dynamic>> _parsePpgShoushiFrame(
    ByteData frame,
    int sequenceNum,
    int cmd,
    int receiveTs,
  ) {
    if (frame.lengthInBytes < 5) {
      if (frame.lengthInBytes == 4) {
        return const [];
      }
      throw Exception('PPG SHOUSHI frame too short: ${frame.lengthInBytes}');
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
      logger.d('OpenRing PPG SHOUSHI progress: $value%');
      return const [];
    }

    if (type == 0x00) {
      if (value == 0 || value == 2 || value == 4 || value == 5) {
        final String reason = switch (value) {
          0 => 'not worn',
          2 => 'charging',
          4 => 'busy',
          5 => 'timeout',
          _ => 'unknown',
        };
        logger.w(
          'OpenRing PPG SHOUSHI error packet received: '
          'code=$value ($reason)',
        );
        return const [];
      }

      if (value == 3) {
        if (frame.lengthInBytes >= 7) {
          logger.d(
            'OpenRing PPG SHOUSHI result received: '
            'heart=${frame.getUint8(5)} spo2=${frame.getUint8(6)}',
          );
        }
        return const [];
      }

      logger.w('OpenRing PPG SHOUSHI result packet with unknown value=$value');
      return const [];
    }

    if (type == 0x01) {
      if (frame.lengthInBytes < 7) {
        throw Exception(
          'PPG SHOUSHI waveform frame too short: ${frame.lengthInBytes}',
        );
      }

      final int nSamples = frame.getUint8(5);
      final int waveType = frame.getUint8(6);
      final ByteData waveformPayload = ByteData.sublistView(frame, 7);
      final parsed = _parsePpgShoushiWaveform(
        data: waveformPayload,
        nSamples: nSamples,
        waveType: waveType,
        receiveTs: receiveTs,
        baseHeader: {
          ...baseHeader,
          'waveType': waveType,
        },
      );
      if (parsed.isEmpty && nSamples > 0) {
        logger.w(
          'OpenRing PPG SHOUSHI waveform length mismatch '
          '(nSamples=$nSamples, waveType=$waveType, '
          'payloadLen=${waveformPayload.lengthInBytes})',
        );
      } else if (parsed.isNotEmpty && _loggedWaveformByCmd.add(cmd)) {
        logger.d(
          'OpenRing PPG SHOUSHI waveform received: '
          'nSamples=$nSamples waveType=$waveType',
        );
      }
      return parsed;
    }

    logger.d(
      'OpenRing PPG SHOUSHI packet ignored: '
      'type=$type value=$value len=${frame.lengthInBytes}',
    );
    return const [];
  }

  List<Map<String, dynamic>> _parseRealTimePpgFrame(
    ByteData frame,
    int sequenceNum,
    int cmd,
    int receiveTs,
  ) {
    if (frame.lengthInBytes < 4) {
      throw Exception('Realtime PPG frame too short: ${frame.lengthInBytes}');
    }

    final int type = frame.getUint8(3);
    final Map<String, dynamic> baseHeader = {
      'sequenceNum': sequenceNum,
      'cmd': cmd,
      'type': type,
    };

    if (type == 0xFF) {
      if (frame.lengthInBytes >= 5) {
        logger.d('OpenRing realtime PPG progress: ${frame.getUint8(4)}%');
      }
      return const [];
    }

    if (type == 0x01) {
      logger.d('OpenRing realtime PPG time packet received');
      return const [];
    }

    if (type == 0x02) {
      if (frame.lengthInBytes < 14) {
        throw Exception(
          'Realtime PPG waveform frame too short: ${frame.lengthInBytes}',
        );
      }

      final int packetSeq = frame.getUint8(4);
      final int nSamples = frame.getUint8(5);
      final ByteData waveformPayload = ByteData.sublistView(frame, 6);
      final parsed = _parseRealTimePpgWaveform(
        data: waveformPayload,
        nSamples: nSamples,
        receiveTs: receiveTs,
        baseHeader: {
          ...baseHeader,
          'packetSeq': packetSeq,
        },
      );
      if (parsed.isEmpty && nSamples > 0) {
        logger.w(
          'OpenRing realtime PPG waveform length mismatch '
          '(nSamples=$nSamples, payloadLen=${waveformPayload.lengthInBytes})',
        );
      } else if (parsed.isNotEmpty && _loggedWaveformByCmd.add(cmd)) {
        logger.d(
          'OpenRing realtime PPG waveform received: '
          'nSamples=$nSamples packetSeq=$packetSeq',
        );
      }
      return parsed;
    }

    if (type == 0x05) {
      if (frame.lengthInBytes >= 9) {
        logger.d(
          'OpenRing realtime PPG result received: '
          'heart=${frame.getUint8(5)} spo2=${frame.getUint8(6)}',
        );
      }
      return const [];
    }

    logger.d(
      'OpenRing realtime PPG packet ignored: '
      'type=$type len=${frame.lengthInBytes}',
    );
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

  Map<String, dynamic> _parseAccelerometerComp(ByteData data) {
    return {
      'X': data.getInt16(0, Endian.little),
      'Y': data.getInt16(2, Endian.little),
      'Z': data.getInt16(4, Endian.little),
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
        ),
      });
    }

    return parsedData;
  }

  List<Map<String, dynamic>> _parseHeartRotaWaveform({
    required ByteData data,
    required int nSamples,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    if (nSamples == 0) {
      return const [];
    }

    const int sampleSize = 10;
    final int expectedBytes = nSamples * sampleSize;
    if (data.lengthInBytes < expectedBytes) {
      return const [];
    }

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < nSamples; i++) {
      final int offset = i * sampleSize;
      final int ts = receiveTs + (i + 1) * 40;

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'PPG': {'Green': data.getUint32(offset, Endian.little)},
        'Accelerometer': _parseAccelerometerComp(
          ByteData.sublistView(data, offset + 4, offset + 10),
        ),
      });
    }

    return parsedData;
  }

  List<Map<String, dynamic>> _parsePpgShoushiWaveform({
    required ByteData data,
    required int nSamples,
    required int waveType,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    if (nSamples == 0) {
      return const [];
    }

    // The vendor SDK copies nSamples * 4 bytes and decodes waveType 0 as
    // a single little-endian green value per sample.
    const int sampleSize = 4;
    final int expectedBytes = nSamples * sampleSize;
    if (data.lengthInBytes < expectedBytes) {
      return const [];
    }

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < nSamples; i++) {
      final int offset = i * sampleSize;
      final int ts = receiveTs + (i + 1) * 40;

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'PPG': {'Green': data.getUint32(offset, Endian.little)},
      });
    }

    return parsedData;
  }

  List<Map<String, dynamic>> _parseRealTimePpgWaveform({
    required ByteData data,
    required int nSamples,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    // BaseLmAPi.fileContentQingHua parses [8-byte timestamp][n * 30-byte
    // samples]. The first three uint32 values follow the established
    // ired/red/green order used by the vendor helpers.
    const int headerSize = 8;
    const int sampleSize = 30;
    if (nSamples == 0 || data.lengthInBytes <= headerSize) {
      return const [];
    }

    final int availableSamples =
        (data.lengthInBytes - headerSize) ~/ sampleSize;
    final int usableSamples =
        nSamples <= availableSamples ? nSamples : availableSamples;
    if (usableSamples == 0) {
      return const [];
    }

    final ByteData sampleData = ByteData.sublistView(data, headerSize);
    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < usableSamples; i++) {
      final int offset = i * sampleSize;
      final int ts = receiveTs + (i + 1) * 40;

      parsedData.add({
        ...baseHeader,
        'timestamp': ts,
        'PPG': {
          'Infrared': sampleData.getUint32(offset, Endian.little),
          'Red': sampleData.getUint32(offset + 4, Endian.little),
          'Green': sampleData.getUint32(offset + 8, Endian.little),
        },
        'Accelerometer': _parseAccelerometerComp(
          ByteData.sublistView(sampleData, offset + 12, offset + 18),
        ),
        'Gyroscope': {
          'X': sampleData.getInt16(offset + 18, Endian.little),
          'Y': sampleData.getInt16(offset + 20, Endian.little),
          'Z': sampleData.getInt16(offset + 22, Endian.little),
        },
        'Temperature': {
          'Temp0': sampleData.getUint16(offset + 24, Endian.little) /
              _tempRawToCelsiusScale,
          'Temp1': sampleData.getUint16(offset + 26, Endian.little) /
              _tempRawToCelsiusScale,
          'Temp2': sampleData.getUint16(offset + 28, Endian.little) /
              _tempRawToCelsiusScale,
          'units': '°C',
        },
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
    //   0..3   infrared uint32
    //   4..7   red uint32
    //   8..11  green uint32
    //   12..17 accX/accY/accZ int16
    //   18..23 gyroX/gyroY/gyroZ int16
    //   24..29 temp0/temp1/temp2 uint16 (centi-degC)
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
          'Infrared': sampleData.getUint32(offset, Endian.little),
          'Red': sampleData.getUint32(offset + 4, Endian.little),
          'Green': sampleData.getUint32(offset + 8, Endian.little),
        },
        'Accelerometer': _parseAccelerometerComp(
          ByteData.sublistView(sampleData, offset + 12, offset + 18),
        ),
        'Gyroscope': {
          'X': sampleData.getInt16(offset + 18, Endian.little),
          'Y': sampleData.getInt16(offset + 20, Endian.little),
          'Z': sampleData.getInt16(offset + 22, Endian.little),
        },
        'Temperature': {
          'Temp0': sampleData.getUint16(offset + 24, Endian.little) /
              _tempRawToCelsiusScale,
          'Temp1': sampleData.getUint16(offset + 26, Endian.little) /
              _tempRawToCelsiusScale,
          'Temp2': sampleData.getUint16(offset + 28, Endian.little) /
              _tempRawToCelsiusScale,
          'units': '°C',
        },
      });
    }

    return parsedData;
  }
}
