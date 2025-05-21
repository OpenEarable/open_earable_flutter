abstract class AudioModeManager {
  final Set<AudioMode> availableAudioModes;

  AudioModeManager({
    required this.availableAudioModes,
  });

  void setAudioMode(AudioMode audioMode);
  Future<AudioMode> getAudioMode();
}

abstract class AudioMode {
  final int id;
  final String key;

  const AudioMode({
    required this.id,
    required this.key,
  });
}

class NormalMode extends AudioMode {
  const NormalMode() : super(id: 0, key: "Normal");
}

class TransparencyMode extends AudioMode {
  const TransparencyMode() : super(id: 1, key: "Transparency");
}

class NoiseCancellationMode extends AudioMode {
  const NoiseCancellationMode() : super(id: 2, key: "Noise Cancellation");
}
