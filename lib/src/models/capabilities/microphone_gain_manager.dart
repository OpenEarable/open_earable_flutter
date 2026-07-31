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

  final int outerRegister;
  final int innerRegister;

  const MicrophoneGain({
    required this.outerRegister,
    required this.innerRegister,
  })  : assert(outerRegister >= 0 && outerRegister <= muteRegister),
        assert(innerRegister >= 0 && innerRegister <= muteRegister);

  const MicrophoneGain.stereo(int register)
      : this(outerRegister: register, innerRegister: register);

  const MicrophoneGain.muted()
      : this.stereo(muteRegister);

  bool get isMuted =>
      outerRegister == muteRegister && innerRegister == muteRegister;

  double? get outerDb => registerToDb(outerRegister);

  double? get innerDb => registerToDb(innerRegister);

  MicrophoneGain copyWith({
    int? outerRegister,
    int? innerRegister,
  }) {
    return MicrophoneGain(
      outerRegister: outerRegister ?? this.outerRegister,
      innerRegister: innerRegister ?? this.innerRegister,
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
