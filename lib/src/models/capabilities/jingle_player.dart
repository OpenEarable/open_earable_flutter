abstract class JinglePlayer {
  Future<void> playJingle(Jingle jingle);

  List<Jingle> get supportedJingles;
}

class Jingle {
  final String key;

  const Jingle({required this.key});

  @override
  String toString() {
    return key;
  }
}
