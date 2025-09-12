import 'dart:typed_data';

import '../sensor_scheme_parser/sensor_scheme_reader.dart';

abstract class SensorValueParser {
  /// Parses raw sensor data bytes into a list of [Map]s of sensor values.
  List<Map<String, dynamic>> parse(ByteData data, List<SensorScheme> sensorSchemes);
}
