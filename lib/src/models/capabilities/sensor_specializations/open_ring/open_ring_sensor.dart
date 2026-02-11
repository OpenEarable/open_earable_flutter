import 'dart:async';

import '../../../../managers/sensor_handler.dart';
import '../../sensor.dart';

class OpenRingSensor extends Sensor<SensorIntValue> {
  OpenRingSensor({
    required this.sensorId,
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required this.sensorHandler,
    super.relatedConfigurations = const [],
  }) : _axisNames = axisNames,
       _axisUnits = axisUnits;

  final int sensorId;
  final List<String> _axisNames;
  final List<String> _axisUnits;

  final SensorHandler sensorHandler;

  late final Stream<SensorIntValue> _cachedSensorStream = _createSensorStream();

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  @override
  int get axisCount => _axisNames.length;

  @override
  Stream<SensorIntValue> get sensorStream => _cachedSensorStream;

  Stream<SensorIntValue> _createSensorStream() {
    final streamController = StreamController<SensorIntValue>();
    final subscription = sensorHandler.subscribeToSensorData(sensorId).listen((
      data,
    ) {
      if (!data.containsKey(sensorName)) {
        return;
      }

      final sensorData = data[sensorName];
      final timestamp = data["timestamp"];
      if (sensorData is! Map || timestamp is! int) {
        return;
      }

      final Map sensorDataMap = sensorData;
      List<int> values = [];
      for (final axisName in _axisNames) {
        final dynamic axisValue = sensorDataMap[axisName];
        if (axisValue is int) {
          values.add(axisValue);
        }
      }

      if (values.isEmpty) {
        for (var entry in sensorDataMap.entries) {
          if (entry.key == 'units') {
            continue;
          }
          if (entry.value is int) {
            values.add(entry.value as int);
          }
        }
      }

      if (values.isEmpty) {
        return;
      }

      SensorIntValue sensorValue = SensorIntValue(
        values: values,
        timestamp: timestamp,
      );

      streamController.add(sensorValue);
    });

    streamController.onCancel = () {
      unawaited(subscription.cancel());
    };

    return streamController.stream;
  }
}
