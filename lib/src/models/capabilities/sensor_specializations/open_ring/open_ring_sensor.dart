import 'dart:async';

import '../../../../managers/sensor_handler.dart';
import '../../sensor.dart';

class OpenRingSensor extends Sensor<SensorDoubleValue> {
  OpenRingSensor({
    required this.sensorId,
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required this.sensorHandler,
    super.relatedConfigurations = const [],
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits;

  final int sensorId;
  final List<String> _axisNames;
  final List<String> _axisUnits;

  final SensorHandler sensorHandler;

  // ignore: cancel_subscriptions
  StreamSubscription<Map<String, dynamic>>? _sensorSubscription;
  late final StreamController<SensorDoubleValue> _sensorStreamController =
      StreamController<SensorDoubleValue>.broadcast(
    onListen: _handleListen,
    onCancel: _handleCancel,
  );

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  @override
  int get axisCount => _axisNames.length;

  @override
  Stream<SensorDoubleValue> get sensorStream => _sensorStreamController.stream;

  void _handleListen() {
    _sensorSubscription ??=
        sensorHandler.subscribeToSensorData(sensorId).listen(
      (data) {
        final SensorDoubleValue? sensorValue = _toSensorValue(data);
        if (sensorValue != null && !_sensorStreamController.isClosed) {
          _sensorStreamController.add(sensorValue);
        }
      },
      onError: (error, stack) {
        if (!_sensorStreamController.isClosed) {
          _sensorStreamController.addError(error, stack);
        }
      },
    );
  }

  Future<void> _handleCancel() async {
    if (_sensorStreamController.hasListener) {
      return;
    }

    final subscription = _sensorSubscription;
    _sensorSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
  }

  SensorDoubleValue? _toSensorValue(Map<String, dynamic> data) {
    if (!data.containsKey(sensorName)) {
      return null;
    }

    final sensorData = data[sensorName];
    final timestamp = data['timestamp'];
    if (sensorData is! Map || timestamp is! int) {
      return null;
    }

    final Map sensorDataMap = sensorData;
    final List<double> values = [];
    for (final axisName in _axisNames) {
      final dynamic axisValue = sensorDataMap[axisName];
      if (axisValue is int) {
        values.add(axisValue.toDouble());
      } else if (axisValue is double) {
        values.add(axisValue);
      }
    }

    if (values.isEmpty) {
      for (final entry in sensorDataMap.entries) {
        if (entry.key == 'units') {
          continue;
        }
        if (entry.value is int) {
          values.add((entry.value as int).toDouble());
        } else if (entry.value is double) {
          values.add(entry.value as double);
        }
      }
    }

    if (values.isEmpty) {
      return null;
    }

    return SensorDoubleValue(values: values, timestamp: timestamp);
  }
}
