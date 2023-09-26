part of open_earable_flutter;

/// A class that manages the playback of audio on the OpenEarable device from
/// an audio file on the SD card.
///
/// This class provides functionality for controlling and interacting with an
/// audio player via Bluetooth Low Energy (BLE) communication. It allows you
/// to send commands to the audio player.
class WavAudioPlayer {
  /// The BleManager instance used for Bluetooth communication.
  final BleManager _bleManager;

  /// Creates an [WavAudioPlayer] instance with the provided [bleManager].
  ///
  /// The [bleManager] is required for handling BLE communication.
  WavAudioPlayer({required BleManager bleManager}) : _bleManager = bleManager;

  /// Writes the state and name of the WAV audio file to the OpenEarable.
  ///
  /// The [state] parameter represents the playback state and should be one of
  /// the following values from the [WavAudioPlayerState] enum:
  ///
  /// - [WavPlayerState.stop]: Stops audio playback.
  /// - [WavPlayerState.start]: Starts audio playback.
  /// - [WavPlayerState.pause]: Pauses audio playback.
  /// - [WavPlayerState.unpause]: unpauses audio playback.
  ///
  /// [name] is the name of the audio file that is stored on the SD card of the OpenEarable.
  ///
  /// The method assembles the command data and writes it to the appropriate
  /// service and characteristic using BLE communication.
  ///
  /// - [state]: The playback state to be written.
  /// - [name]: The name of the audio file. This parameter is optional.
  void writeWAVState(WavAudioPlayerState state, {String name = ""}) {
    ByteData data = ByteData(2 + name.length);
    data.setUint8(0, state.index);
    data.setUint8(1, name.length);

    List<int> nameBytes = utf8.encode(name);
    for (var i = 0; i < nameBytes.length; i++) {
      data.setUint8(2 + i, nameBytes[i]);
    }

    _bleManager.write(
        serviceId: wavPlayServiceUuid,
        characteristicId: wavPlayCharacteristic,
        byteData: data.buffer.asUint8List());
  }
}

enum WavAudioPlayerState { stop, start, pause, unpause }
