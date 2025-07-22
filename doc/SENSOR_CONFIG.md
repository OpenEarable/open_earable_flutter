# Configuring Sensors
For most devices, sensors need to be configured before they start sending data. This configuration can include setting the sampling rate, enabling or disabling specific sensors, and other parameters that may vary by device.

## Accessing Sensor Configuration
In order to configure sensors, you first need to access the `SensorConfiguration` you want to configure. This can be done through two approaches:

1. **Using `relatedConfigurations`**:
  If you have a `Sensor` you want to configure, you can access the related sensor configurations directly:
  ```dart
  List<SensorConfiguration> configurations = sensor.relatedConfigurations;
  ```
2. **Using `SensorConfigurationManager`**:
  If you have a `Wearable` that implements `SensorConfigurationManager`, you can access the configurations like this:
  ```dart
  if (wearable is SensorConfigurationManager) {
    List<SensorConfiguration> configurations = wearable.sensorConfigurations;
  }
  ```

## Configuring Sensors
Once you have a `SensorConfiguration` object, you can configure the sensors by setting a specific `SensorConfigurationValue` for the configuration. The available values can be accessed through the `values` property of the `SensorConfiguration`:
```dart
SensorConfiguration configuration;
List<SensorConfigurationValue> values = configuration.values;
SensorConfigurationValue valueToSet = values.firstWhere(...);
configuration.setConfiguration(valueToSet);
```

Every `SensorConfigurationValue` can be identified by its `key` property.

### Turning Sensors Off
If you want to turn off a sensor, you can set the configuration to the `SensorConfigurationValue` in `offValue` of a `SensorConfiguration`.
```dart
SensorConfigurationValue? offValue = configuration.offValue;
if (offValue != null) {
  configuration.setConfiguration(offValue);
}
```

### Different types of Sensor Configurations
Sensor configurations can vary widely depending on the device and the sensors it supports. Every configuration accepts a specific set of Subtypes of `SensorConfigurationValue`.

#### Frequency Configuration
Sensors that support frequency configuration, extend the `SensorFrequencyConfiguration` class. They accept a `SensorFrequencyConfigurationValue`. You can set the frequency by selecting a specific value from the available values or by using either `setFrequencyBestEffort(int targetFrequency)` or `setMaximumFrequency()` methods.

The specific frequency of a `SensorFrequencyConfigurationValue` can be accessed through its `frequencyHz` property.

#### Configurable Sensor Configurations
Some sensors may have configurations that allow you to enable or disable specific features or modes. These configurations extend the `ConfigurableSensorConfiguration` class and accept `ConfigurableSensorConfigurationValue` objects. A list of available options can be accessed through the `availableOptions` property of the configuration. Each `ConfigurableSensorConfigurationValue` has a subset of options that are being set together with the value. You can access the options through the `options` property of the value.

##### Record on Device Option
Some sensors may support a "Record on Device" option, which allows the sensor to record data directly on the device. This is useful for sensors that can store data locally to be retrieved later, rather than streaming data in real-time. You can check if this option is available by checking if a `RecordSensorConfigOption` object is present in the `options` of a `ConfigurableSensorConfigurationValue`.

##### Streaming Data Option
Some sensors may have a "Streaming Data" option, which allows the sensor to stream data in real-time. This is useful for sensors that need to provide continuous data updates. You can check if this option is available by checking if a `StreamSensorConfigOption` object is present in the `options` of a `ConfigurableSensorConfigurationValue`.