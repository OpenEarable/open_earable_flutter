# Adding Custom Wearable Support

Adding custom Wearable support allows you to extend the functionality of the Open Earable Flutter package to include your own wearable devices. This guide will walk you through the steps necessary to integrate a custom wearable into your Flutter project.

## 1. Create a Custom Wearable Class

Start by creating a new class for your custom wearable device. This class should extend the `Wearable` class provided by the Open Earable Flutter package.

```dart
class MyCustomWearable extends Wearable {
  MyCustomWearable(super.name, super.disconnectNotifier);

  // Implement any custom functionality here
}
```

## 2. Create a factory for your custom wearable

Next, you need to create a factory method that will instantiate your custom wearable class. This method should return an instance of your custom wearable when called.

```dart
class MyCustomWearableFactory extends WearableFactory {
  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    // Implement your matching logic here
    return false;
  }

  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device) async {
    // Implement your device-specific creation logic here
    String name = device.name;
    Notifier disconnectNotifier = Notifier();

    return MyCustomWearable(name, disconnectNotifier);
  }
}
```

## 3. Register the Custom Wearable Factory

To register your custom wearable factory, you need to add it to the `WearableManager` before trying to connect the wearable:
``` dart
WearableManager().addWearableFactory(MyCustomWearableFactory());
```
From now on, every time a device is connected via the `connectToDevice(discoveredDevice)` method of `WearableManager`, your factory is checked on whether or not to the device matches your wearable.

## 4. Adding functionality to your Wearable

Adding functionality to your wearable can be done by implementing capabilities. Learn more about capabilities in the [Functionality of Wearables](doc/CAPABILITIES.md) documentation.

## Conclusion

By following these steps, you can successfully add support for your own wearable devices in the Open Earable Flutter package. For more advanced use cases, consider exploring the package's source code and documentation.