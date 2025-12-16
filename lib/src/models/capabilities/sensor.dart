import 'sensor_configuration.dart';

/// A base class for sensors that provides common properties and methods.
/// It is designed to be extended by specific sensor implementations.
/// 
/// This class defines the basic structure of a sensor, including its name,
/// chart title, short chart title, timestamp exponent, and related configurations.
/// It also provides a stream of sensor values and methods to retrieve axis names and units.
abstract class Sensor<SV extends SensorValue> {
  /// The name of the sensor, used for identification and display purposes.
  final String sensorName;
  /// The title of the chart that displays the sensor data.
  final String chartTitle;
  /// A shorter version of the chart title, used for compact displays.
  final String shortChartTitle;
  /// A list of related sensor configurations that are used to modify the sensor's behavior.
  final List<SensorConfiguration> relatedConfigurations;

  /// The exponent of the timestamp value.
  /// 0 for seconds, -3 for milliseconds, -6 for microseconds, etc.
  final int timestampExponent;

  const Sensor({
    required this.sensorName,
    required this.chartTitle,
    required this.shortChartTitle,
    this.timestampExponent = -3,
    this.relatedConfigurations = const [],
  });

  /// The name of the different axes of the sensor.
  List<String> get axisNames;

  /// The units of the different axes of the sensor.
  List<String> get axisUnits;

  /// The number of axes the sensor has.
  int get axisCount => axisNames.length;

  /// A stream of sensor values that emits new values as they are received.
  /// In order to use this stream, the sensor must be started using the
  /// [relatedConfigurations].
  Stream<SV> get sensorStream;
}

/// A base class for sensor values that provides common properties and methods.
/// It is designed to be extended by specific sensor value implementations.
class SensorValue {
  final List<String> _valuesStrings;
  /// The timestamp of the sensor value, represented as an integer.
  /// The unit of the timestamp is determined by the [Sensor.timestampExponent].
  final BigInt timestamp;

  /// The number of dimensions of the sensor value.
  /// This value is equal to the number of axes of the sensor.
  int get dimensions => _valuesStrings.length;

  /// A list of string representations of the sensor values.
  /// This list is used to display the values in a human-readable format.
  List<String> get valueStrings => _valuesStrings;

  const SensorValue({
    required List<String> valueStrings,
    required this.timestamp,
  }) : _valuesStrings = valueStrings;
}

/// A sensor value that contains multiple double values.
class SensorDoubleValue extends SensorValue {
  final List<double> values;

  const SensorDoubleValue({
    required this.values,
    required super.timestamp,
  })  : super(
          valueStrings: const [],
        );

  @override
  int get dimensions => values.length;

  @override
  List<String> get valueStrings => values.map((e) => e.toString()).toList();
}

/// A sensor value that contains multiple integer values.
class SensorIntValue extends SensorValue {
  final List<int> values;

  const SensorIntValue({
    required this.values,
    required super.timestamp,
  })  : super(
    valueStrings: const [],
  );

  @override
  int get dimensions => values.length;

  @override
  List<String> get valueStrings => values.map((e) => e.toString()).toList();
}
