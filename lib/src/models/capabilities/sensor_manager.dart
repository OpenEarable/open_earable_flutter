import 'sensor.dart';

/// A device that manages a collection of sensors.
abstract class SensorManager {
  /// The sensors managed by this device.
  /// This is a read-only list of sensors.
  List<Sensor> get sensors;
}
