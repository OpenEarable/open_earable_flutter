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

  /// Writes the state and name of the WAV audio file to the OpenEarable.
  ///
  /// The [state] parameter represents the playback state and should be one of
  /// the following values from the [AudioPlayerState] enum:
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
  void _writeAudioPlayerState(
      SoundType soundType, AudioPlayerState state, String name,
      {int waveForm = 0, double frequency = 0, double amplitude = 1.0}) {
    int byteDataLength = 3 + // 3 bytes fo soundtype, state, length
        ((soundType == SoundType.frequency)
            ? 8
            : name.length); // 8 bytes for 2x float32 (frequency, amplitude)
    ByteData data = ByteData(byteDataLength);
    data.setUint8(0, soundType.index);
    data.setUint8(1, state.index);
    if (soundType == SoundType.jingle) {
      data.setUint8(2, waveForm);
    } else {
      data.setUint8(2, name.length);
    }

    if (soundType == SoundType.frequency) {
      data.setFloat32(3, frequency);
      data.setFloat32(7, amplitude);
    } else {
      List<int> nameBytes = utf8.encode(name);
      for (var i = 0; i < nameBytes.length; i++) {
        data.setUint8(3 + i, nameBytes[i]);
      }
    }

    _bleManager.write(
        serviceId: audioPlayerServiceUuid,
        characteristicId: audioPlayerCharacteristic,
        byteData: data.buffer.asUint8List());
  }

  /// Plays a WAV file with the specified [state] and optional [name].
  ///
  /// This method is used to play WAV audio files. It takes an [AudioPlayerState]
  /// to set the player's state and an optional [name] parameter to specify
  /// the name of the audio file.
  ///
  /// Example usage:
  /// ```dart
  /// setWavState(AudioPlayerState.play, name: 'mySound.wav');
  /// ```
  void setWavState(AudioPlayerState state, {String name = ""}) {
    _writeAudioPlayerState(SoundType.wav, state, name);
  }

  /// Plays a sound with a specified frequency and waveform.
  ///
  /// This method is used to generate and play sounds with a specific [frequency]
  /// and [waveForm]. It takes an [AudioPlayerState] to set the player's state.
  /// Possible waveforms are:
  ///
  /// - 0: Sine.
  /// - 1: Triangle.
  /// - 2: Square.
  /// - 3: Sawtooth.
  ///
  /// Example usage:
  /// ```dart
  /// setFrequencyState(AudioPlayerState.play, 440.0, 0);
  /// ```
  void setFrequencyState(AudioPlayerState state,
      {double frequency = 0, int waveForm = 0, double amplitude = 1.0}) {
    _writeAudioPlayerState(SoundType.frequency, state, "",
        waveForm: waveForm, frequency: frequency, amplitude: amplitude);
  }

  /// Plays a jingle or short musical sound with the specified [state] and optional [name].
  ///
  /// This method is used to play jingles or short musical sounds. It takes an
  /// [AudioPlayerState] to set the player's state and an optional [name]
  /// parameter to specify the name of the jingle.
  ///
  /// Example usage:
  /// ```dart
  /// setJingleState(AudioPlayerState.play, name: 'jingle.wav');
  /// ```
  void setJingleState(AudioPlayerState state, {String name = ""}) {
    _writeAudioPlayerState(SoundType.jingle, state, name);
  }

  /// Sets the audio player to the idle state.
  ///
  /// The audio player transitions to the idle state,
  /// indicating that it is not currently playing any sound.
  void setIdle() {
    _writeAudioPlayerState(SoundType.idle, AudioPlayerState.idle, "");
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

/// An enumeration representing the different types of sounds that can be played.
enum SoundType {
  /// Represents the idle state.
  idle,

  /// Represents an audio file in WAV format.
  wav,

  /// Represents a sound generated with a specific frequency and waveform.
  frequency,

  /// Represents a jingle or short musical sound.
  jingle,
}
