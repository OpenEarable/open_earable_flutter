import 'sensor_configuration.dart';

abstract class Sensor {
  final String sensorName;
  final String chartTitle;
  final String shortChartTitle;
  final List<SensorConfiguration> relatedConfigurations;

  /// The exponent of the timestamp value.
  /// 0 for seconds, -3 for milliseconds, -6 for microseconds, etc.
  final int timestampExponent;

  const Sensor({
    required this.sensorName,
    required this.chartTitle,
    required this.shortChartTitle,
    this.timestampExponent = -3,
    this.relatedConfigurations = const [],
  });

  List<String> get axisNames;

  List<String> get axisUnits;

  int get axisCount => axisNames.length;

  Stream<SensorValue> get sensorStream;
}

class SensorValue {
  final List<String> _valuesStrings;
  //TODO: adjust for v2 that uses uint64 timestamp
  final int timestamp;

  int get dimensions => _valuesStrings.length;

  List<String> get valueStrings => _valuesStrings;

  const SensorValue({
    required List<String> valueStrings,
    required this.timestamp,
  }) : _valuesStrings = valueStrings;
}

class SensorDoubleValue extends SensorValue {
  final List<double> values;

  const SensorDoubleValue({
    required this.values,
    required int timestamp,
  })  : super(
          valueStrings: const [],
          timestamp: timestamp,
        );

  @override
  int get dimensions => values.length;

  @override
  List<String> get valueStrings => values.map((e) => e.toString()).toList();
}

class SensorIntValue extends SensorValue {
  final List<int> values;

  const SensorIntValue({
    required this.values,
    required int timestamp,
  })  : super(
    valueStrings: const [],
    timestamp: timestamp,
  );

  @override
  int get dimensions => values.length;

  @override
  List<String> get valueStrings => values.map((e) => e.toString()).toList();
}
