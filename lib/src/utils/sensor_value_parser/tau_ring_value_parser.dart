import 'dart:typed_data';

import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class TauRingValueParser extends SensorValueParser {
  @override
  Map<String, dynamic> parse(ByteData data, List<SensorScheme> sensorSchemes) {
    int framePrefix = data.getUint8(0);
    if (framePrefix != 0x00) {
      throw Exception("Invalid frame prefix: $framePrefix"); //TODO: use specific exception
    }

    int sequenceNum = data.getUint8(1);
    int cmd = data.getUint8(2);
    int subOpcode = data.getUint8(3);
    int status = data.getUint8(4);
    ByteData payload = ByteData.sublistView(data, 5);

    Map<String, dynamic> parsedData = {
      "sequenceNum": sequenceNum,
      "cmd": cmd,
      "subOpcode": subOpcode,
      "status": status,
    };

    switch (cmd) {
      case 0x40: // IMU
        switch (subOpcode) {
          case 0x01: // Accel only
            Map<String, dynamic> accelData = _parseImuComp(payload);
            parsedData['ACC'] = accelData;
            break;
          case 0x06: // Accel + Gyro
            Map<String, dynamic> accelData = _parseImuComp(ByteData.sublistView(payload, 0, 5));
            Map<String, dynamic> gyroData = _parseImuComp(ByteData.sublistView(payload, 6));
            parsedData['ACC'] = accelData;
            parsedData['GYRO'] = gyroData;
            break;
          default:
            throw Exception("Unknown sub-opcode for sensor data: $subOpcode");
        }
      default:
        throw Exception("Unknown command: $cmd");
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
