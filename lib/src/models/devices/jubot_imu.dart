import 'package:open_earable_flutter/src/models/capabilities/sensor.dart';

import '../capabilities/sensor_manager.dart';
import 'wearable.dart';

class JuBotIMU extends Wearable implements SensorManager {

  JuBotIMU({required super.name, required super.disconnectNotifier});

  @override
  // TODO: implement deviceId
  String get deviceId => throw UnimplementedError();

  @override
  Future<void> disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  final List<Sensor<SensorValue>> _sensors = [
    JuBotAccSensor(),
    JuBotGyroSensor(),
  ];

  @override
  List<Sensor<SensorValue>> get sensors => _sensors;

}

class JuBotAccSensor extends Sensor<JuBotAccSensorValue> {
  JuBotAccSensor() : super(
    sensorName: 'JuBot Acc Sensor',
    chartTitle: 'JuBot Accelerometer',
    shortChartTitle: 'JuBot Acc',
  );
  
  @override
  List<String> get axisNames => ['X', 'Y', 'Z'];

  @override
  List<String> get axisUnits => ['m/s²', 'm/s²', 'm/s²'];
  
  @override
  // TODO: implement sensorStream
  Stream<JuBotAccSensorValue> get sensorStream => throw UnimplementedError();
}

class JuBotAccSensorValue extends SensorValue {
  final double x;
  final double y;
  final double z;

  JuBotAccSensorValue({
    required this.x,
    required this.y,
    required this.z,
    required super.timestamp,
  }) : super(valueStrings: ['$x', '$y', '$z']);

  @override
  List<String> get valueStrings => ['$x', '$y', '$z'];

  @override
  String toString() {
    return 'JuBotAccSensorValue(x: $x, y: $y, z: $z, timestamp: $timestamp)';
  }
}

class JuBotGyroSensor extends Sensor<JuBotGyroSensorValue> {
  JuBotGyroSensor() : super(
    sensorName: 'JuBot Gyro Sensor',
    chartTitle: 'JuBot Gyroscope',
    shortChartTitle: 'JuBot Gyro',
  );

  @override
  List<String> get axisNames => ['X', 'Y', 'Z'];

  @override
  List<String> get axisUnits => ['rad/s', 'rad/s', 'rad/s'];

  @override
  // TODO: implement sensorStream
  Stream<JuBotGyroSensorValue> get sensorStream => throw UnimplementedError();
}

class JuBotGyroSensorValue extends SensorValue {
  final double x;
  final double y;
  final double z;

  JuBotGyroSensorValue({
    required this.x,
    required this.y,
    required this.z,
    required super.timestamp,
  }) : super(valueStrings: ['$x', '$y', '$z']);

  @override
  List<String> get valueStrings => ['$x', '$y', '$z'];

  @override
  String toString() {
    return 'JuBotGyroSensorValue(x: $x, y: $y, z: $z, timestamp: $timestamp)';
  }
}
