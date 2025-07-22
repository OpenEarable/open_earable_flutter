# Configuring Sensors

For most devices, sensors need to be configured before they start sending data. This configuration can include setting the sampling rate, enabling or disabling specific sensors, and other parameters that may vary by device.

## Accessing Sensor Configuration

To configure sensors, you first need to access the `SensorConfiguration` you want to configure. This can be done in two ways:

1. **Using `relatedConfigurations`**  
   If you have a `Sensor` you want to configure, you can access its related sensor configurations directly:

   ```dart
   List<SensorConfiguration> configurations = sensor.relatedConfigurations;
   ```

2. **Using `SensorConfigurationManager`**  
   If you have a `Wearable` that implements `SensorConfigurationManager`, you can access the configurations like this:

   ```dart
   if (wearable is SensorConfigurationManager) {
     List<SensorConfiguration> configurations = wearable.sensorConfigurations;
   }
   ```

## Applying a Sensor Configuration

Once you have a `SensorConfiguration` object, you can configure the sensor by applying a specific `SensorConfigurationValue`. The available values are accessible via the `values` property:

```dart
SensorConfiguration configuration;
List<SensorConfigurationValue> values = configuration.values;
SensorConfigurationValue valueToSet = values.firstWhere(...);
configuration.setConfiguration(valueToSet);
```

Each `SensorConfigurationValue` can be identified by its `key` property.

### Turning Sensors Off

To disable a sensor (e.g., to conserve power), set its configuration to the `SensorConfigurationValue` found in the `offValue` property of the `SensorConfiguration`:

```dart
SensorConfigurationValue? offValue = configuration.offValue;
if (offValue != null) {
  configuration.setConfiguration(offValue);
}
```

## Types of Sensor Configurations

Sensor configurations can vary depending on the device and the supported sensors. Each configuration accepts a specific subtype of `SensorConfigurationValue`.

### Frequency Configuration

Sensors that support frequency control extend the `SensorFrequencyConfiguration` class and accept `SensorFrequencyConfigurationValue` instances. You can set the frequency either by choosing a value from `values`, or by using the convenience methods:

- `setFrequencyBestEffort(int targetFrequency)`
- `setMaximumFrequency()`

The actual frequency of a `SensorFrequencyConfigurationValue` is available via its `frequencyHz` property.

### Configurable Sensor Configurations

Some sensors support configurable modes or features. These configurations extend the `ConfigurableSensorConfiguration` class and accept `ConfigurableSensorConfigurationValue` objects. The list of all available options for the configuration can be accessed through its `availableOptions` property.

Each `ConfigurableSensorConfigurationValue` sets a specific subset of options, which can be accessed via the `options` property.

#### Record on Device Option

Some sensors support a "Record on Device" option, allowing them to store data locally instead of streaming it. You can check for this feature by verifying whether a `RecordSensorConfigOption` is present in the `options` list of a `ConfigurableSensorConfigurationValue`.

#### Streaming Data Option

Sensors that support real-time data streaming may offer a "Streaming Data" option. To check if it's available, look for a `StreamSensorConfigOption` in the `options` of a `ConfigurableSensorConfigurationValue`.
