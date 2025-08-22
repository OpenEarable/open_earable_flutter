import '../../capabilities/stereo_device.dart';

/// Abstract class that defines a pairing rule for stereo devices.
abstract class PairingRule<D extends StereoDevice> {
  /// Checks if the given pair of devices is valid according to the pairing rule.
  Future<bool> isValidPair(D left, D right);
}
