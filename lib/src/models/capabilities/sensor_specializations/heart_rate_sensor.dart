import '../sensor.dart';

abstract class HeartRateSensor extends Sensor {
  const HeartRateSensor({
    super.relatedConfigurations = const [],
  }) : super(
          sensorName: 'HR',
          chartTitle: 'Heart Rate',
          shortChartTitle: 'HR',
        );

  @override
  List<String> get axisNames => ['Heart Rate'];

  @override
  List<String> get axisUnits => ['BPM'];

  @override
  int get axisCount => 1;

  @override
  Stream<HeartRateSensorValue> get sensorStream;
}

class HeartRateSensorValue extends SensorIntValue {
  HeartRateSensorValue({
    required int heartRateBpm,
    required int timestamp,
  }) : super(
          values: [heartRateBpm],
          timestamp: timestamp,
        );
}
