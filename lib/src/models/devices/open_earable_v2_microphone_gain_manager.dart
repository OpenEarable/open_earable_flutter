import '../../managers/ble_gatt_manager.dart';
import '../capabilities/microphone_gain_manager.dart';

/// Microphone gain implementation for OpenEarable V2 devices that expose the
/// optional DMIC gain characteristic.
class OpenEarableV2MicrophoneGainManager implements MicrophoneGainManager {
  /// UUID of the OpenEarable V2 audio configuration service.
  static const String serviceUuid = '1410df95-5f68-4ebb-a7c7-5e0fb9ae7557';

  /// UUID of the optional DMIC gain characteristic.
  static const String characteristicUuid =
      '1410df99-5f68-4ebb-a7c7-5e0fb9ae7557';

  /// Creates a microphone gain manager backed by [bleManager].
  const OpenEarableV2MicrophoneGainManager({
    required this.bleManager,
    required this.deviceId,
  });

  /// BLE manager used to communicate with the device.
  final BleGattManager bleManager;

  /// Identifier of the OpenEarable device.
  final String deviceId;

  @override
  Future<MicrophoneGain> getMicrophoneGain() async {
    final gainBytes = await bleManager.read(
      deviceId: deviceId,
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
    );

    if (gainBytes.length != 2) {
      throw StateError(
        'Microphone gain characteristic expected 2 values, but got ${gainBytes.length}',
      );
    }

    return MicrophoneGain(
      outerRegister: gainBytes[0],
      innerRegister: gainBytes[1],
    );
  }

  @override
  Future<void> setMicrophoneGain(MicrophoneGain gain) {
    return bleManager.write(
      deviceId: deviceId,
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      byteData: [gain.outerRegister, gain.innerRegister],
    );
  }
}
