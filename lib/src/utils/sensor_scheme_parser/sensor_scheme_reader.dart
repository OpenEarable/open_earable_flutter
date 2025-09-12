abstract class SensorSchemeReader {
  Future<SensorScheme> getSchemeForSensor(int sensorId);

  Future<List<SensorScheme>> readSensorSchemes({bool forceRead = false});
}

/// Represents a sensor component with its type, group name, component name, and unit name.
class Component {
  ParseType type;
  String groupName;
  String componentName;
  String unitName;

  /// Creates a [Component] instance with the specified parameters.
  Component(this.type, this.groupName, this.componentName, this.unitName);

  @override
  String toString() {
    return 'Component(type: $type, groupName: $groupName, componentName: $componentName, unitName: $unitName)';
  }
}

/// Represents a sensor scheme that contains the components for a sensor.
class SensorScheme {
  int sensorId;
  String sensorName;
  int componentCount;
  List<Component> components = [];
  SensorConfigOptions? options;

  SensorScheme(this.sensorId, this.sensorName, this.componentCount, this.options);

  @override
  String toString() {
    return 'Sensorscheme(sensorId: $sensorId, sensorName: $sensorName, components: ${components.map((component) => component.toString()).toList()})';
  }
}

enum ParseType {
  int8,
  uint8,
  int16,
  uint16,
  int32,
  uint32,
  float,
  double;

  /// Constructs a [ParseType] from an integer value.
  static ParseType fromInt(int value) {
    if (value < 0 || value >= ParseType.values.length) {
      throw ArgumentError('Invalid ParseType value: $value');
    }
    return ParseType.values[value];
  }

  int size() {
    switch (this) {
      case ParseType.int8:
      case ParseType.uint8:
        return 1;
      case ParseType.int16:
      case ParseType.uint16:
        return 2;
      case ParseType.int32:
      case ParseType.uint32:
      case ParseType.float:
        return 4;
      case ParseType.double:
        return 8;
    }
  }
}

enum SensorConfigFeatures {
  streaming(0x01),
  recording(0x02),
  frequencyDefinition(0x10);

  final int value;
  const SensorConfigFeatures(this.value);
}

class SensorConfigOptions {
  List<SensorConfigFeatures> features;
  SensorConfigFrequencies? frequencies;

  SensorConfigOptions(this.features, this.frequencies);
}

class SensorConfigFrequencies {
  int maxStreamingFreqIndex;
  int defaultFreqIndex;
  List<double> frequencies;

  SensorConfigFrequencies(this.maxStreamingFreqIndex, this.defaultFreqIndex, this.frequencies);
}
