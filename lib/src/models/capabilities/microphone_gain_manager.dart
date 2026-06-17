abstract class MicrophoneGainManager {
  Future<MicrophoneGain> getMicrophoneGain();

  Future<void> setMicrophoneGain(MicrophoneGain gain);
}

class MicrophoneGain {
  static const int maxGainRegister = 0x00;
  static const int zeroDbRegister = 0x40;
  static const int minGainRegister = 0xFE;
  static const int muteRegister = 0xFF;
  static const int defaultRegister = 0x20;
  static const double stepDb = 0.375;
  static const double maxGainDb = 24.0;
  static const double minGainDb = -71.25;

  final int leftRegister;
  final int rightRegister;

  const MicrophoneGain({
    required this.leftRegister,
    required this.rightRegister,
  })  : assert(leftRegister >= 0 && leftRegister <= muteRegister),
        assert(rightRegister >= 0 && rightRegister <= muteRegister);

  const MicrophoneGain.stereo(int register)
      : this(leftRegister: register, rightRegister: register);

  const MicrophoneGain.muted()
      : this.stereo(muteRegister);

  bool get isMuted =>
      leftRegister == muteRegister && rightRegister == muteRegister;

  double? get leftDb => registerToDb(leftRegister);

  double? get rightDb => registerToDb(rightRegister);

  MicrophoneGain copyWith({
    int? leftRegister,
    int? rightRegister,
  }) {
    return MicrophoneGain(
      leftRegister: leftRegister ?? this.leftRegister,
      rightRegister: rightRegister ?? this.rightRegister,
    );
  }

  static double? registerToDb(int register) {
    _validateRegister(register);
    if (register == muteRegister) {
      return null;
    }
    return maxGainDb - (register * stepDb);
  }

  static int dbToRegister(double db) {
    final clampedDb = db.clamp(minGainDb, maxGainDb).toDouble();
    return ((maxGainDb - clampedDb) / stepDb)
        .round()
        .clamp(maxGainRegister, minGainRegister)
        .toInt();
  }

  static void _validateRegister(int register) {
    if (register < 0 || register > muteRegister) {
      throw RangeError.range(register, 0, muteRegister, 'register');
    }
  }
}
