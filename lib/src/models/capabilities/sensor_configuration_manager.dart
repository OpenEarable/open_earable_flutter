import 'sensor_configuration.dart';

abstract class SensorConfigurationManager {
  List<SensorConfiguration> get sensorConfigurations;

  Stream<Map<SensorConfiguration, SensorConfigurationValue>> get sensorConfigurationStream
    => const Stream.empty();
}
