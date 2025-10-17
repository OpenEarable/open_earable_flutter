import 'dart:typed_data';

import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class TauRingValueParser extends SensorValueParser {
  @override
  Map<String, dynamic> parse(ByteData data, List<SensorScheme> sensorSchemes) {
    int baseTs = DateTime.now().millisecondsSinceEpoch;

    int framePrefix = data.getUint8(0);
    if (framePrefix != 0x00) {
      throw Exception("Invalid frame prefix: $framePrefix"); //TODO: use specific exception
    }

    if (data.lengthInBytes < 5) {
      throw Exception("Data too short to parse"); //TODO: use specific exception
    }

    int sequenceNum = data.getUint8(1);
    int cmd = data.getUint8(2);
    int subOpcode = data.getUint8(3);
    int status = data.getUint8(4);
    ByteData payload = ByteData.sublistView(data, 5);

    Map<String, dynamic> dataHeader = {
      "timestamp": baseTs,
      "sequenceNum": sequenceNum,
      "cmd": cmd,
      "subOpcode": subOpcode,
      "status": status,
    };

    final List<Map<String, dynamic>> parsedData;

    switch (cmd) {
      case 0x40: // IMU
        switch (subOpcode) {
          case 0x01: // Accel only
            parsedData = _parseAccel(payload);
            break;
          case 0x06: // Accel + Gyro
            parsedData = _parseAccelGyro(payload);
            break;
          default:
            throw Exception("Unknown sub-opcode for sensor data: $subOpcode");
        }
      default:
        throw Exception("Unknown command: $cmd");
    }

    return parsedData.map((m) => m..addAll(dataHeader)).toList().first; //TODO: return full list
  }

  List<Map<String, dynamic>> _parseAccel(ByteData data) {
    if (data.lengthInBytes % 6 != 0) {
      throw Exception("Invalid data length for Accel: ${data.lengthInBytes}");
    }
    List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < data.lengthInBytes; i += 6) {
      if (i + 6 > data.lengthInBytes) break;
      ByteData sample = ByteData.sublistView(data, i, i + 6);
      Map<String, dynamic> accelData = _parseImuComp(sample);
      parsedData.add({'Accelerometer': accelData});
    }
    return parsedData;
  }

  List<Map<String, dynamic>> _parseAccelGyro(ByteData data) {
    if (data.lengthInBytes % 12 != 0) {
      throw Exception("Invalid data length for Accel+Gyro: ${data.lengthInBytes}");
    }
    List<Map<String, dynamic>> parsedData = [];
    for (int i = 0; i < data.lengthInBytes; i += 12) {
      if (i + 12 > data.lengthInBytes) break;
      ByteData sample = ByteData.sublistView(data, i, i + 12);
      Map<String, dynamic> accelData = _parseImuComp(ByteData.sublistView(sample, 0, 6));
      Map<String, dynamic> gyroData = _parseImuComp(ByteData.sublistView(sample, 6));
      parsedData.add({
        'Accelerometer': accelData,
        'Gyroscope': gyroData,
      });
    }
    return parsedData;
  }

  Map<String, dynamic> _parseImuComp(ByteData data) {
    Map<String, dynamic> parsedComp = {};

    parsedComp['X'] = data.getInt16(0, Endian.little);
    parsedComp['Y'] = data.getInt16(2, Endian.little);
    parsedComp['Z'] = data.getInt16(4, Endian.little);

    return parsedComp;
  }
}
