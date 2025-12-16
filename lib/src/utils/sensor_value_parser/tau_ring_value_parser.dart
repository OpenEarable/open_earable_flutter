import 'dart:typed_data';

import '../../../open_earable_flutter.dart' show logger;
import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class TauRingValueParser extends SensorValueParser {
  // 100 Hz → 10 ms per sample
  static const int _samplePeriodMs = 10;

  int _lastSeq = -1;
  int _lastTs = 0;

  @override
  List<Map<String, dynamic>> parse(
    ByteData data,
    List<SensorScheme> sensorSchemes,
  ) {
    

    logger.t("Received Tau Ring sensor data: size: ${data.lengthInBytes} ${data.buffer.asUint8List()}");


    final int framePrefix = data.getUint8(0);
    if (framePrefix != 0x00) {
      throw FormatException("Invalid frame prefix: $framePrefix"); 
    }

    if (data.lengthInBytes < 5) {
      throw FormatException("Data too short to parse"); 
    }

    final int sequenceNum = data.getUint8(1);
    final int cmd = data.getUint8(2);
    final int subOpcode = data.getUint8(3);
    final int status = data.getUint8(4);
    final ByteData payload = ByteData.sublistView(data, 5);

    logger.t("last sequenceNum: $_lastSeq, current sequenceNum: $sequenceNum");
    if (sequenceNum != _lastSeq) {
      _lastSeq = sequenceNum;
      _lastTs = 0;
      logger.d("Sequence number changed. Resetting last timestamp.");
    }

    // These header fields should go into every sample map
    final Map<String, dynamic> baseHeader = {
      "sequenceNum": sequenceNum,
      "cmd": cmd,
      "subOpcode": subOpcode,
      "status": status,
    };
  
    List<Map<String, dynamic>> result;
    switch (cmd) {
      case 0x40: // IMU
        switch (subOpcode) {
          case 0x01: // Accel only (6 bytes per sample)
            result = _parseAccel(
              data: payload,
              receiveTs: _lastTs,
              baseHeader: baseHeader,
            );
          case 0x06: // Accel + Gyro (12 bytes per sample)
            result = _parseAccelGyro(
              data: payload,
              receiveTs: _lastTs,
              baseHeader: baseHeader,
            );
          default:
            throw Exception("Unknown sub-opcode for sensor data: $subOpcode");
        }

      default:
        throw Exception("Unknown command: $cmd");
    }
    if (result.isNotEmpty) {
      _lastTs = result.last["timestamp"] as int;
      logger.t("Updated last timestamp to $_lastTs");
    }
    return result;
  }

  List<Map<String, dynamic>> _parseAccel({
    required ByteData data,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    if (data.lengthInBytes % 6 != 0) {
      throw Exception("Invalid data length for Accel: ${data.lengthInBytes}");
    }

    final int nSamples = data.lengthInBytes ~/ 6;
    if (nSamples == 0) return const [];

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < data.lengthInBytes; i += 6) {
      final int sampleIndex = i ~/ 6;
      final int ts = receiveTs + sampleIndex * _samplePeriodMs;

      final ByteData sample = ByteData.sublistView(data, i, i + 6);
      final Map<String, dynamic> accelData = _parseImuComp(sample);

      parsedData.add({
        ...baseHeader,
        "timestamp": ts,
        "Accelerometer": accelData,
      });
    }
    return parsedData;
  }

  List<Map<String, dynamic>> _parseAccelGyro({
    required ByteData data,
    required int receiveTs,
    required Map<String, dynamic> baseHeader,
  }) {
    if (data.lengthInBytes % 12 != 0) {
      throw Exception("Invalid data length for Accel+Gyro: ${data.lengthInBytes}");
    }

    final int nSamples = data.lengthInBytes ~/ 12;
    if (nSamples == 0) return const [];

    final List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < data.lengthInBytes; i += 12) {
      final int sampleIndex = i ~/ 12;
      final int ts = receiveTs + sampleIndex * _samplePeriodMs;

      final ByteData sample = ByteData.sublistView(data, i, i + 12);
      final ByteData accBytes = ByteData.sublistView(sample, 0, 6);
      final ByteData gyroBytes = ByteData.sublistView(sample, 6);

      final Map<String, dynamic> accelData = _parseImuComp(accBytes);
      final Map<String, dynamic> gyroData = _parseImuComp(gyroBytes);

      parsedData.add({
        ...baseHeader,
        "timestamp": ts,
        "Accelerometer": accelData,
        "Gyroscope": gyroData,
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
}
