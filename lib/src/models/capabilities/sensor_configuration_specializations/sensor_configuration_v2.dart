import 'dart:ffi';

import '../../../managers/v2_sensor_handler.dart';
import '../sensor_configuration.dart';

class SensorConfigurationV2 extends SensorConfiguration<SensorConfigurationValueV2> {
  // TODO: Add capabilities to sensor configuration
  final int maxStreamingFreqIndex;
  final V2SensorHandler _sensorHandler;

  bool streamData = false;
  bool storeData = false;

  SensorConfigurationV2({
    required String name,
    required List<SensorConfigurationValueV2> values,
    required this.maxStreamingFreqIndex,
    required V2SensorHandler sensorHandler,
    String? unit,
  }) : _sensorHandler = sensorHandler, super(name: name, values: values, unit: unit);

  @override
  String toString() {
    return 'SensorConfigurationV2(name: $name, values: $values, unit: $unit, maxStreamingFreqIndex: $maxStreamingFreqIndex)';
  }
  
  @override
  void setConfiguration(SensorConfigurationValueV2 configuration) {
    V2SensorConfig sensorConfig = V2SensorConfig(
      sensorId: configuration.sensorId as Uint8,
      sampleRateIndex: configuration.frequencyIndex as Uint8,
      streamData: streamData,
      storeData: storeData,
    );
    _sensorHandler.writeSensorConfig(sensorConfig);
  }
}

class SensorConfigurationValueV2 extends SensorConfigurationValue {
  final int sensorId;
  final double frequency;
  final int frequencyIndex;

  SensorConfigurationValueV2({
    required this.sensorId,
    required this.frequency,
    required this.frequencyIndex,
  }) : super(key: frequency.toString());

  @override
  String toString() {
    return key;
  }
}
