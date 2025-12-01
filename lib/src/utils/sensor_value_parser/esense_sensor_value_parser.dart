import 'dart:typed_data';

import '../../../open_earable_flutter.dart' show logger;
import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class EsenseSensorValueParser extends SensorValueParser {
  // Maps to keep track of previous timestamps for sensors
  // key: sensorId, value: lastTimestamp
  final Map<int, int> _timestampMap = {};

  @override
  List<Map<String, dynamic>> parse(
    ByteData data,
    List<SensorScheme> sensorSchemes,
  ) {
    int cmdHead = data.getUint8(0);
    int packetIndex = data.getUint8(1);
    int checkSum = data.getUint8(2);
    int dataSize = data.getUint8(3);

    Uint8List payload = data.buffer.asUint8List(4);

    logger.t(
      "Esense Sensor Data Received: cmdHead: $cmdHead, packetIndex: $packetIndex, checkSum: $checkSum, dataSize: $dataSize, payload: $payload",
    );

    if (payload.length != dataSize) {
      throw Exception(
        "Data size mismatch. Expected $dataSize, got ${payload.length}",
      );
    }

    final ByteData payloadData =
        payload.buffer.asByteData(payload.offsetInBytes, dataSize);
    if (!_verifyChecksum(payloadData, checkSum)) {
      throw Exception("Checksum verification failed.");
    }

    switch (cmdHead) {
      case 0x55:
        if (dataSize != 12) {
          throw Exception(
            "Invalid data size for sensor data packet. Expected 12, got $dataSize",
          );
        }

        SensorScheme scheme = sensorSchemes.firstWhere(
          (s) => s.sensorId == cmdHead,
          orElse: () => throw Exception("Unknown sensorId: ${cmdHead.toRadixString(16)}, only got ${sensorSchemes.map((s) => s.sensorId.toRadixString(16)).toList()}"),
        );
        SensorConfigFrequencies? frequencies = scheme.options?.frequencies;

        if (frequencies == null) {
          throw Exception(
            "Frequencies not defined for sensorId: $cmdHead",
          );
        }

        double freq = frequencies.frequencies[frequencies.defaultFreqIndex];
        int tsIncrement = (1000 / freq).round();
        int lastTs = _timestampMap.putIfAbsent(
          cmdHead,
          () => 0,
        );
        int ts = lastTs + tsIncrement;
        _timestampMap[cmdHead] = ts;
        int rawGyroX = payloadData.getInt16(0, Endian.big);
        int rawGyroY = payloadData.getInt16(2, Endian.big);
        int rawGyroZ = payloadData.getInt16(4, Endian.big);
        int rawAccelX = payloadData.getInt16(6, Endian.big);
        int rawAccelY = payloadData.getInt16(8, Endian.big);
        int rawAccelZ = payloadData.getInt16(10, Endian.big);

        Map<String, dynamic> output = {
          "timestamp": ts,
          "Accelerometer": {
            "x": rawAccelX,
            "y": rawAccelY,
            "z": rawAccelZ,
          },
          "Gyroscope": {
            "x": rawGyroX,
            "y": rawGyroY,
            "z": rawGyroZ,
          },
        };

        return [output];

      default:
        throw Exception("Unknown sensor ID: ${cmdHead.toRadixString(16)}");
    }
  }

  bool _verifyChecksum(ByteData data, int expectedChecksum) {
    int calculatedChecksum = data.lengthInBytes;
    for (int i = 0; i < data.lengthInBytes; i++) {
      calculatedChecksum = (calculatedChecksum + data.getUint8(i));
    }
    calculatedChecksum = calculatedChecksum & 0xFF;
    return calculatedChecksum == expectedChecksum;
  }
}
