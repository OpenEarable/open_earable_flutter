import '../models/capabilities/stereo_device.dart';
import '../models/devices/stereo_pairing/pairing_rule.dart';

class PairingManager {
  final List<PairingRule> _rules;

  PairingManager({List<PairingRule> rules = const []}) : _rules = rules;

  /// Adds a pairing rule to the manager.
  void addRule(PairingRule rule) {
    _rules.add(rule);
  }

  Future<List<StereoDevice>> findValidPairsFor(StereoDevice device, List<StereoDevice> devices) async {
    final List<StereoDevice> validPairs = [];

    for (var candidate in devices) {
      if (await isValidPair(device, candidate)) {
        validPairs.add(candidate);
      }
    }

    return validPairs;
  }

  Future<Map<StereoDevice, List<StereoDevice>>> findValidPairs(List<StereoDevice> devices) async {
    final Map<StereoDevice, List<StereoDevice>> validPairs = {};

    for (int i = 0; i < devices.length; i++) {
      for (int j = i + 1; j < devices.length; j++) {
        final left = devices[i];
        final right = devices[j];

        for (var rule in _rules) {
          if (await rule.isValidPair(left, right)) {
            validPairs[left] ??= [];
            validPairs[left]!.add(right);
            break;
          }
        }
      }
    }

    return validPairs;
  }

  Future<bool> isValidPair(StereoDevice left, StereoDevice right) async {
    for (var rule in _rules) {
      if (await rule.isValidPair(left, right)) {
        return true;
      }
    }
    return false;
  }
}
