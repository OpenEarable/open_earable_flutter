abstract class SensorSchemeParser {
  /// Parses the byte stream and returns a list of [SensorScheme] instances.
  List<SensorScheme> parse(List<int> byteStream);
}

/// Represents a sensor component with its type, group name, component name, and unit name.
class Component {
  int type;
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

enum ParseType { int8, uint8, int16, uint16, int32, uint32, float, double }

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
