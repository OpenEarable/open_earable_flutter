import '../../../open_earable_flutter.dart';


/// τ-Ring integration for OpenEarable.
/// Implements Wearable (mandatory) + SensorManager (exposes sensors).
class TauRing extends Wearable implements SensorManager, SensorConfigurationManager {
  TauRing({
    required DiscoveredDevice discoveredDevice,
    required this.deviceId,
    required super.name,
    List<Sensor> sensors = const [],
    List<SensorConfiguration> sensorConfigs = const [],
    required BleGattManager bleManager,
    required super.disconnectNotifier,
  }) : _sensors = sensors,
      _sensorConfigs = sensorConfigs,
      _bleManager = bleManager,
      _discoveredDevice = discoveredDevice;

  final DiscoveredDevice _discoveredDevice;

  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigs;
  final BleGattManager _bleManager;

  @override
  final String deviceId;
  
  @override
  List<SensorConfiguration<SensorConfigurationValue>> get sensorConfigurations => _sensorConfigs;
  @override
  List<Sensor<SensorValue>> get sensors => _sensors;
  
  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }
  
  @override
  Stream<Map<SensorConfiguration<SensorConfigurationValue>, SensorConfigurationValue>> get sensorConfigurationStream => const Stream.empty();
}

// τ-Ring GATT constants (from the vendor AAR)
class TauRingGatt {
  static const String service = 'bae80001-4f05-4503-8e65-3af1f7329d1f';
  static const String txChar  = 'bae80010-4f05-4503-8e65-3af1f7329d1f'; // write
  static const String rxChar  = 'bae80011-4f05-4503-8e65-3af1f7329d1f'; // notify

  // opcodes (subset)
  static const int cmdApp   = 0xA0; // APP_* handshake
  static const int cmdVers  = 0x11; // version
  static const int cmdBatt  = 0x12; // battery
  static const int cmdSys   = 0x37; // system (reset etc.)
  static const int cmdPPGQ2 = 0x32; // start/stop PPG Q2

  // build a framed command: [0x00, rnd, cmdId, payload...]
  static List<int> frame(int cmd, {List<int> payload = const [], int? rnd}) {
    final r = rnd ?? DateTime.now().microsecondsSinceEpoch & 0xFF;
    return [0x00, r & 0xFF, cmd, ...payload];
  }

  static List<int> le64(int ms) {
    final b = List<int>.filled(8, 0);
    var v = ms;
    for (var i = 0; i < 8; i++) { b[i] = v & 0xFF; v >>= 8; }
    return b;
  }
}
