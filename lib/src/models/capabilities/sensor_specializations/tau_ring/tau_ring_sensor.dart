import 'dart:async';

import '../../../../managers/sensor_handler.dart';
import '../../sensor.dart';

class TauRingSensor extends Sensor<SensorIntValue> {
  const TauRingSensor({
    required this.sensorId,
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required this.sensorHandler,
    super.relatedConfigurations = const [],
  }) : _axisNames = axisNames, _axisUnits = axisUnits;

  final int sensorId;
  final List<String> _axisNames;
  final List<String> _axisUnits;

  final SensorHandler sensorHandler;

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  @override
  int get axisCount => _axisNames.length;

  @override
  Stream<SensorIntValue> get sensorStream {
    StreamController<SensorIntValue> streamController = StreamController();
    sensorHandler.subscribeToSensorData(sensorId).listen(
      (data) {
        BigInt timestamp = BigInt.from(data["timestamp"]);

        List<int> values = [];
        for (var entry in (data[sensorName] as Map).entries) {
          if (entry.key == 'units') {
            continue;
          }

          values.add(entry.value);
        }

        SensorIntValue sensorValue = SensorIntValue(
          values: values,
          timestamp: timestamp,
        );

        streamController.add(sensorValue);
      },
    );
    return streamController.stream;
  }
}
