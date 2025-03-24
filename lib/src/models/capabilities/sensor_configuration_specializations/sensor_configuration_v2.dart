import 'package:open_earable_flutter/src/models/capabilities/sensor_config_capabilities/recordable_sensor_config.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_config_capabilities/streamable_sensor_configuration.dart';

import '../../../managers/v2_sensor_handler.dart';
import '../sensor_configuration.dart';

class SensorConfigurationV2 extends SensorConfiguration<SensorConfigurationValueV2> implements StreamableSensorConfiguration, RecordableSensorConfig {

  final int maxStreamingFreqIndex;
  final V2SensorHandler _sensorHandler;

  @override
  bool recordData = false;
  
  @override
  bool streamData = false;

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
      sensorId: configuration.sensorId,
      sampleRateIndex: configuration.frequencyIndex,
      streamData: streamData,
      storeData: recordData,
    );
    _sensorHandler.writeSensorConfig(sensorConfig);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is SensorConfigurationV2) {
      return name == other.name &&
          values == other.values &&
          unit == other.unit &&
          maxStreamingFreqIndex == other.maxStreamingFreqIndex;
    }
    return false;
  }
  
  @override
  int get hashCode => name.hashCode ^ values.hashCode ^ unit.hashCode ^ maxStreamingFreqIndex.hashCode;
}

class SensorConfigurationValueV2 extends SensorConfigurationValue {
  final int sensorId;
  final double frequency;
  final int frequencyIndex;

  SensorConfigurationValueV2({
    required this.sensorId,
    required this.frequency,
    required this.frequencyIndex,
  }) : super(key: frequency.toStringAsPrecision(4));

  @override
  String toString() {
    return key;
  }
}
