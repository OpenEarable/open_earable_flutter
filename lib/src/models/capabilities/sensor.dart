abstract class Sensor {
  final String sensorName;
  final String chartTitle;
  final String shortChartTitle;

  const Sensor({
    required this.sensorName,
    required this.chartTitle,
    required this.shortChartTitle,
  });

  List<String> get axisNames;

  List<String> get axisUnits;

  int get axisCount => axisNames.length;

  Stream<SensorValue> get sensorStream;
}

class SensorValue {
  final List<String> _valuesStrings;
  final int timestamp;

  int get dimensions => _valuesStrings.length;

  List<String> get valueStrings => _valuesStrings;

  const SensorValue({
    required List<String> valueStrings,
    required this.timestamp,
  }) : _valuesStrings = valueStrings;

  @override
  String toString() {
    return 'SensorValue(valueStrings: $valueStrings, timestamp: $timestamp)';
  }
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
