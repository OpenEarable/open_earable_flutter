import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import '../../managers/esense_sensor_handler.dart';
import '../../managers/sensor_handler.dart';
import '../../utils/sensor_value_parser/esense_sensor_value_parser.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_configuration_specializations/esense/esense_sensor_configuration.dart';
import '../capabilities/sensor_configuration_specializations/streamable_sensor_configuration.dart';
import '../wearable_factory.dart';
import 'discovered_device.dart';
import 'esense.dart';
import 'wearable.dart';

class EsenseFactory extends WearableFactory {
  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device,
      {Set<ConnectionOption> options = const {},}) async {

    EsenseSensorHandler sensorHandler = EsenseSensorHandler(
      bleGattManager: bleManager!,
      discoveredDevice: device,
      sensorValueParser: EsenseSensorValueParser(),
    );

    List<EsenseSensorConfigurationValue> imuConfigValues = [
      EsenseSensorConfigurationValue(frequencyHz: 25.0),
      EsenseSensorConfigurationValue(frequencyHz: 50.0),
      EsenseSensorConfigurationValue(frequencyHz: 100.0),
      EsenseSensorConfigurationValue(frequencyHz: 200.0),
    ].expand((v) => [v, v.copyWith(options: {StreamSensorConfigOption()})]).toList();
    
    final imuConfig = EsenseSensorConfiguration(
        name: "9-axis IMU",
        values: imuConfigValues,
        sensorCommand: 0x53,
        sensorHandler: sensorHandler,
        availableOptions: {
          StreamSensorConfigOption(),
        },
      );

    Esense esense = Esense(
      name: device.name,
      bleManager: bleManager!,
      discoveredDevice: device,
      disconnectNotifier: disconnectNotifier!,
      sensorConfigurations: [imuConfig],
      sensors: [
        EsenseSensor(
          sensorId: 0x55,
          sensorName: "Accelerometer",
          chartTitle: "Accelerometer",
          shortChartTitle: "Accel",
          axisNames: ["X", "Y", "Z"],
          axisUnits: ["g", "g", "g"],
          sensorHandler: sensorHandler,
          relatedConfigurations: [imuConfig],
        ),
        EsenseSensor(
          sensorId: 0x55,
          sensorName: "Gyroscope",
          chartTitle: "Gyroscope",
          shortChartTitle: "Gyro",
          axisNames: ["X", "Y", "Z"],
          axisUnits: ["dps", "dps", "dps"],
          sensorHandler: sensorHandler,
          relatedConfigurations: [imuConfig],
        ),
      ],
    );
    
    return esense;
  }

  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    return RegExp(r'^eSense-\d{4}$').hasMatch(device.name);
  }
}

class EsenseSensor extends Sensor<SensorDoubleValue> {
  final List<String> _axisNames;
  final List<String> _axisUnits;

  final int _sensorId;

  final SensorHandler _sensorHandler;

  EsenseSensor({
    required int sensorId,
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required SensorHandler sensorHandler,
    super.relatedConfigurations,
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits,
        _sensorId = sensorId,
        _sensorHandler = sensorHandler;

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;
  @override
  Stream<SensorDoubleValue> get sensorStream {
    StreamController<SensorDoubleValue> streamController =
        StreamController<SensorDoubleValue>();
    _sensorHandler.subscribeToSensorData(_sensorId).listen(
      (data) {
        BigInt timestamp = data["timestamp"];

        List<double> values = [];
        for (var entry in (data[sensorName] as Map).entries) {
          if (entry.key == 'units') {
            continue;
          }

          if (entry.value is BigInt) {
            values.add((entry.value as BigInt).toDouble());
          } else if (entry.value is double) {
            values.add(entry.value as double);
          } else {
            throw Exception("Unsupported sensor value type: ${entry.value.runtimeType}");
          }
        }

        SensorDoubleValue sensorValue = SensorDoubleValue(
          values: values,
          timestamp: timestamp,
        );

        streamController.add(sensorValue);
      },
    );

    return streamController.stream;
  }
}
