abstract class MicrophoneManager<MC extends Microphone> {
  final Set<MC> availableMicrophones;

  MicrophoneManager({
    required this.availableMicrophones,
  });

  void setMicrophone(MC microphone);
  Future<MC> getMicrophone();
}

abstract class Microphone {
  final String key;

  const Microphone({
    required this.key,
  });
}
