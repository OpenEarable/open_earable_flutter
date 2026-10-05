import '../../managers/ble_gatt_manager.dart';
import '../capabilities/led_state_reader.dart';

/// LED readback added in OpenEarable firmware 2.3.0.
class OpenEarableV2LedStateReader implements LedStateReader {
  static const serviceUuid = '81040a2e-4819-11ee-be56-0242ac120002';
  static const colorUuid = '81040e7a-4819-11ee-be56-0242ac120002';
  static const modeUuid = '81040e7b-4819-11ee-be56-0242ac120002';

  final BleGattManager bleManager;
  final String deviceId;

  const OpenEarableV2LedStateReader({
    required this.bleManager,
    required this.deviceId,
  });

  @override
  Future<LedState> readLedState() async {
    final mode = await bleManager.read(
      deviceId: deviceId,
      serviceId: serviceUuid,
      characteristicId: modeUuid,
    );
    final color = await bleManager.read(
      deviceId: deviceId,
      serviceId: serviceUuid,
      characteristicId: colorUuid,
    );
    if (mode.length != 1 || mode[0] > 1 || color.length != 3) {
      throw const FormatException('Invalid LED state');
    }
    return LedState(
      showStatus: mode[0] == 0,
      red: color[0],
      green: color[1],
      blue: color[2],
    );
  }
}
