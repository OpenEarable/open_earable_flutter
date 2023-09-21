part of open_earable_flutter;

/// The `RgbLed` class provides methods to control the RGB LED on an OpenEarable device.
///
/// You can use this class to set the LED state to control its color and behavior.
class RgbLed {
  final BleManager _bleManager;

  /// Creates an instance of the `RgbLed` class with the provided `BleManager` instance.
  ///
  /// The `BleManager` is used for communication with the OpenEarable device.
  RgbLed({required BleManager bleManager}) : _bleManager = bleManager;

  /// Writes the state of the RGB LED on the OpenEarable device.
  ///
  /// The [state] parameter represents the desired LED state. You can choose from the following states:
  /// - [LedState.off]: Turns off the LED.
  /// - [LedState.green]: Sets the LED to green.
  /// - [LedState.blue]: Sets the LED to blue.
  /// - [LedState.red]: Sets the LED to red.
  /// - [LedState.cyan]: Sets the LED to cyan.
  /// - [LedState.yellow]: Sets the LED to yellow.
  /// - [LedState.magenta]: Sets the LED to magenta.
  /// - [LedState.white]: Sets the LED to white.
  ///
  /// Use this method to easily write the state of the RGB LED on the OpenEarable device.
  Future<void> writeLedState(LedState state) async {
    ByteData data = ByteData(1);
    data.setUint8(0, state.index);
    await _bleManager.write(
        serviceId: ledServiceUuid,
        characteristicId: ledSetStateCharacteristic,
        byteData: data.buffer.asInt8List());
  }
}

/// Enum representing the LED state for an RGB LED.
enum LedState { off, green, blue, red, cyan, yellow, magenta, white }
