abstract class SensorHandler<SC extends SensorConfig> {
  /// Subscribes to sensor data for a specific sensor.
  ///
  /// The [sensorId] parameter specifies the ID of the sensor to subscribe to.
  /// Returns a [Stream] of sensor data as a [Map] of sensor values.
  Stream<Map<String, dynamic>> subscribeToSensorData(int sensorId);

  /// Writes the sensor configuration to the OpenEarable device.
  ///
  /// The [sensorConfig] parameter contains the configurations for the sensor.
  Future<void> writeSensorConfig(SC sensorConfig);
}

abstract class SensorConfig {}
