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
  final List<double> values;
  final int timestamp;

  int get dimensions => values.length;

  const SensorValue({
    required this.values,
    required this.timestamp,
  });
}
