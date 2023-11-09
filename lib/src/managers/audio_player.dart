part of open_earable_flutter;

/// A class that manages the playback of audio on the OpenEarable device from
/// an audio file on the SD card.
///
/// This class provides functionality for controlling and interacting with an
/// audio player via Bluetooth Low Energy (BLE) communication. It allows you
/// to send commands to the audio player.
class AudioPlayer {
  /// The BleManager instance used for Bluetooth communication.
  final BleManager _bleManager;

  /// Creates an [AudioPlayer] instance with the provided [bleManager].
  ///
  /// The [bleManager] is required for handling BLE communication.
  AudioPlayer({required BleManager bleManager}) : _bleManager = bleManager;

  /// Plays a WAV file with the specified [fileName].
  ///
  /// Example usage:
  /// ```dart
  /// setWavState('mySound.wav');
  /// ```
  void wavFile(String fileName) {
    int type = 1; // 1 indicates it's a WAV file
    Uint8List data = prepareData(type, fileName);
    _bleManager.write(
      serviceId: audioPlayerServiceUuid,
      characteristicId: audioSourceCharacteristic,
      byteData: data,
    );
  }

  /// Plays a sound with a specified frequency and waveform.
  ///
  /// This method is used to generate and play sounds with a specific [waveType], [frequency] and [loudness]
  /// Possible waveforms are:
  ///
  /// - 0: Sine.
  /// - 1: Triangle.
  /// - 2: Square.
  /// - 3: Sawtooth.
  ///
  /// loudness must be between 0.0 - 1.0
  /// 
  /// Example usage:
  /// ```dart
  /// setFrequencyState(1, 440.0, 1.0);
  /// ```
  void frequency(int waveType, double frequency, double loudness) {
    int type = 2; // 2 indicates it's a frequency
    Uint8List data = Uint8List(10);
    data[0] = type;
    data[1] = waveType;

    ByteData freqBytes = ByteData(4);
    freqBytes.setFloat32(0, frequency);
    data.setRange(2, 6, freqBytes.buffer.asUint8List());

    ByteData loudnessBytes = ByteData(4);
    loudnessBytes.setFloat32(0, loudness);
    data.setRange(6, 10, loudnessBytes.buffer.asUint8List());

    _bleManager.write(
      serviceId: audioPlayerServiceUuid,
      characteristicId: audioSourceCharacteristic,
      byteData: data,
    );
  }

  /// Plays a jingle or short musical sound with [jingleId].
  ///
  /// following jingles are supported:
  ///
  /// 0: 'IDLE'
  /// 1: 'NOTIFICATION'
  /// 2: 'SUCCESS'
  /// 3: 'ERROR'
  /// 4: 'ALARM'
  /// 5: 'PING'
  /// 6: 'OPEN'
  /// 7: 'CLOSE'
  /// 8: 'CLICK'
  ///
  void jingle(int jingleId) {
    int type = 3; // 3 indicates it's a jingle
    Uint8List data = Uint8List(2);
    data[0] = type;
    data[1] = jingleId;
    _bleManager.write(
      serviceId: audioPlayerServiceUuid,
      characteristicId: audioSourceCharacteristic,
      byteData: data,
    );
  }

  Uint8List prepareData(int type, String name) {
    List<int> nameBytes = utf8.encode(name);
    Uint8List data = Uint8List(2 + nameBytes.length);
    data[0] = type;
    data[1] = nameBytes.length;
    data.setRange(2, 2 + nameBytes.length, nameBytes);
    return data;
  }

  /// Writes the audio state to the OpenEarable.
  ///
  /// The [state] parameter represents the playback state and should be one of
  /// the following values from the [AudioPlayerState] enum:
  ///
  /// - [WavPlayerState.stop]: Stops audio playback.
  /// - [WavPlayerState.start]: Starts audio playback.
  /// - [WavPlayerState.pause]: Pauses audio playback.
  /// - [WavPlayerState.unpause]: unpauses audio playback.
  /// 
  void setState(AudioPlayerState state) async {
    Uint8List data = Uint8List(1);
    data[0] = getAudioPlayerStateValue(state);
    await _bleManager.write(
      serviceId: audioPlayerServiceUuid,
      characteristicId: audioStateCharacteristic,
      byteData: data,
    );
  }

  /// Sets the audio player to the idle state.
  ///
  /// The audio player transitions to the idle state,
  /// indicating that it is not currently playing any sound.
  void setIdle() {
    //_writeAudioPlayerState(SoundType.idle, AudioPlayerState.idle, ""); //TODO
  }
}

int getAudioPlayerStateValue(AudioPlayerState state) {
  switch(state) {
    case AudioPlayerState.idle: return 0;
    case AudioPlayerState.start: return 1;
    case AudioPlayerState.pause: return 2;
    case AudioPlayerState.stop: return 3;
  }
}

/// An enumeration representing the possible states of the audio player.
enum AudioPlayerState {
  /// Idle state.
  idle,

  /// Play the audio file.
  start,

  /// Pause the audio file.
  pause,

  /// Stop the audio file.
  stop,
}
