import 'dart:typed_data';

import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class V2SensorValueParser extends SensorValueParser {
  @override
  Map<String, dynamic> parse(ByteData data, List<SensorScheme> sensorSchemes) {
    var byteIndex = 0;
    final sensorId = data.getUint8(byteIndex);
    byteIndex += 2;
    final timestamp = data.getUint64(byteIndex, Endian.little);
    byteIndex += 8;
    Map<String, dynamic> parsedData = {};
    SensorScheme foundScheme = sensorSchemes.firstWhere(
      (scheme) => scheme.sensorId == sensorId,
    );
    parsedData["sensorId"] = sensorId;
    parsedData["timestamp"] = timestamp;
    parsedData["sensorName"] = foundScheme.sensorName;
    for (Component component in foundScheme.components) {
      if (parsedData[component.groupName] == null) {
        parsedData[component.groupName] = {};
      }
      if (parsedData[component.groupName]["units"] == null) {
        parsedData[component.groupName]["units"] = {};
      }
      final dynamic parsedValue;
      switch (ParseType.values[component.type]) {
        case ParseType.int8:
          parsedValue = data.getInt8(byteIndex);
          byteIndex += 1;
          break;
        case ParseType.uint8:
          parsedValue = data.getUint8(byteIndex);
          byteIndex += 1;
          break;
        case ParseType.int16:
          parsedValue = data.getInt16(byteIndex, Endian.little);
          byteIndex += 2;
          break;
        case ParseType.uint16:
          parsedValue = data.getUint16(byteIndex, Endian.little);
          byteIndex += 2;
          break;
        case ParseType.int32:
          parsedValue = data.getInt32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.uint32:
          parsedValue = data.getUint32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.float:
          parsedValue = data.getFloat32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.double:
          parsedValue = data.getFloat64(byteIndex, Endian.little);
          byteIndex += 8;
          break;
      }
      parsedData[component.groupName][component.componentName] = parsedValue;
      parsedData[component.groupName]["units"][component.componentName] =
          component.unitName;
    }
    return parsedData;
  }
}
