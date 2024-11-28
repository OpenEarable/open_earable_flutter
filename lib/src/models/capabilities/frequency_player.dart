abstract class FrequencyPlayer {
  /// [waveType] The type of waveform to play.
  /// [frequency] The frequency of the sound in Hz.
  /// [loudness] The loudness of the sound, should be a value between 0 and 1.
  Future<void> playFrequency(
    WaveType waveType, {
    double frequency = 440.0,
    double loudness = 1,
  });

  List<WaveType> get supportedFrequencyPlayerWaveTypes;
}

class WaveType {
  final String key;

  const WaveType({required this.key});

  @override
  String toString() {
    return key;
  }
}
