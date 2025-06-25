import 'sensor_configuration.dart';

/// A base class for managing sensor configurations.
/// It provides a list of sensor configurations and a stream of configuration values.
/// This class is designed to be extended by specific sensor configuration managers.
abstract class SensorConfigurationManager {
  /// A list of sensor configurations managed by this manager.
  /// This list is read-only and provides access to the available sensor configurations.
  /// Each configuration can be used to set specific behaviors for sensors.
  /// The configurations are expected to be of type [SensorConfiguration].
  List<SensorConfiguration> get sensorConfigurations;

  /// A stream of sensor configuration values.
  /// This stream emits a map of sensor configurations and their corresponding values.
  Stream<Map<SensorConfiguration, SensorConfigurationValue>> get sensorConfigurationStream
    => const Stream.empty();
}
