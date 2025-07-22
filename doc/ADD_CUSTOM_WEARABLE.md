# Adding Custom Wearable Support

Integrating your own wearable devices into the Open Earable Flutter package is straightforward. This guide walks you through how to create a custom wearable, register it, and extend its functionality using capabilities.

---

## 1. Define Your Custom Wearable

Begin by creating a class that extends the `Wearable` base class. This will represent your custom device.

```dart
class MyCustomWearable extends Wearable {
  MyCustomWearable(super.name, super.disconnectNotifier);

  // Add your device-specific logic and overrides here
}
```

---

## 2. Implement a Custom Wearable Factory

Create a factory that determines when your custom wearable should be used. This factory is responsible for recognizing a device and constructing the corresponding wearable object. If you need to perform ble gatt operations, you can use the `BleGattManager` in `bleManager` of the `WearableFactory` class. The `BleGattManager` provides methods for interacting with BLE devices, such as reading and writing characteristics. It is provided by the `WearableManager` and should not be set manually.

```dart
class MyCustomWearableFactory extends WearableFactory {
  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    // Define logic to check if the device matches your custom wearable
    return false; // Change this condition based on your criteria
  }

  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device) async {
    if (bleManager == null) {
      throw Exception("BleGattManager is not initialized");
    }

    // Create and return an instance of your custom wearable
    String name = device.name;
    Notifier disconnectNotifier = Notifier();

    return MyCustomWearable(name, disconnectNotifier);
  }
}
```

---

## 3. Register the Custom Factory

Before connecting to devices, register your factory with the `WearableManager`. This ensures your factory is used when scanning for and connecting to devices.

```dart
WearableManager().addWearableFactory(MyCustomWearableFactory());
```

When `connectToDevice(discoveredDevice)` is called, the manager will use your factory’s `matches()` method to check if the discovered device should be handled by your custom class.

---

## 4. Add Functionality via Capabilities

Extend your custom wearable by implementing capabilities (e.g., sensor access, configuration, storage). Capabilities are modular and reusable components that define what a wearable can do.

For more details, refer to the [Functionality of Wearables](CAPABILITIES.md) guide.

---

## Example Use

Once your factory is registered and your wearable is defined, connecting to and interacting with your custom wearable is as simple as:

```dart
WearableManager manager = WearableManager();
manager.addWearableFactory(MyCustomWearableFactory());
try {
  Wearable wearable = await manager.connectToDevice(discoveredDevice);
} catch {
  // handle cases where device is no supported wearable
}
```

## Conclusion

With these steps, you can easily add support for custom wearable devices to the Open Earable Flutter package. For more advanced integrations, explore how built-in wearables use capabilities to expose features such as sensor data, configuration, and on-device storage.
