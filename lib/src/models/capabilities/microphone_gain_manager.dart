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

  final int externalRegister;
  final int internalRegister;

  const MicrophoneGain({
    required this.externalRegister,
    required this.internalRegister,
  })  : assert(externalRegister >= 0 && externalRegister <= muteRegister),
        assert(internalRegister >= 0 && internalRegister <= muteRegister);

  const MicrophoneGain.stereo(int register)
      : this(externalRegister: register, internalRegister: register);

  const MicrophoneGain.muted()
      : this.stereo(muteRegister);

  bool get isMuted =>
      externalRegister == muteRegister && internalRegister == muteRegister;

  double? get externalDb => registerToDb(externalRegister);

  double? get internalDb => registerToDb(internalRegister);

  MicrophoneGain copyWith({
    int? externalRegister,
    int? internalRegister,
  }) {
    return MicrophoneGain(
      externalRegister: externalRegister ?? this.externalRegister,
      internalRegister: internalRegister ?? this.internalRegister,
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
