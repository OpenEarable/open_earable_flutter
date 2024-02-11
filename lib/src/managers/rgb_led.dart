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
  /// Parameters:
  /// - `r`: The red color component value (0-255) for the LED.
  /// - `g`: The green color component value (0-255) for the LED.
  /// - `b`: The blue color component value (0-255) for the LED.
  ///
  /// Use this method to easily set the color of the in-built RGB LED on the OpenEarable device.
  Future<void> writeLedColor(
      {required int r, required int g, required int b}) async {
    if (!_bleManager.connected) {
      Exception("Can't write sensor config. Earable not connected");
    }
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      throw ArgumentError('The color values must be in range 0-255');
    }
    ByteData data = ByteData(3);
    data.setUint8(0, r);
    data.setUint8(1, g);
    data.setUint8(2, b);
    await _bleManager.write(
        serviceId: ledServiceUuid,
        characteristicId: ledSetStateCharacteristic,
        byteData: data.buffer.asUint8List());
  }
}

/// Enum representing the LED state for an RGB LED.
enum LedState { off, green, blue, red, cyan, yellow, magenta, white }
