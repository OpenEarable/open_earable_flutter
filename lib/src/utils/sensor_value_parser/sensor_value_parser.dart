import 'dart:typed_data';

import '../sensor_scheme_parser/sensor_scheme_parser.dart';

abstract class SensorValueParser {
  Map<String, dynamic> parse(ByteData data, List<SensorScheme> sensorSchemes);
}
