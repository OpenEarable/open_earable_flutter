import 'package:open_earable_protocols/open_earable_protocols.dart';

export 'package:open_earable_protocols/open_earable_protocols.dart'
    show
        WirelessAudioConfigurationAclConnectionPolicy,
        WirelessAudioConfigurationAclRadioPolicy,
        WirelessAudioConfigurationAdaptiveLinearAclPolicy,
        WirelessAudioConfigurationAutomaticAclRadioPolicy,
        WirelessAudioConfigurationCapabilities,
        WirelessAudioConfigurationCommandResult,
        WirelessAudioConfigurationConfiguredAclConnectionPolicy,
        WirelessAudioConfigurationConfiguredAclRadioPolicy,
        WirelessAudioConfigurationConfiguredUnicastServerQosPreferences,
        WirelessAudioConfigurationControllerDefaultAclPolicy,
        WirelessAudioConfigurationFixedAclPolicy,
        WirelessAudioConfigurationPreferredAclRadioPolicy,
        WirelessAudioConfigurationPreferredRangeAclPolicy,
        WirelessAudioConfigurationRuntimeState,
        WirelessAudioConfigurationUnicastServerQosPreferences;

/// A configurable section of the wireless audio policy protocol.
enum WirelessAudioConfigurationSection {
  /// ACL connection interval, latency, and supervision timeout policy.
  aclConnectionPolicy(0),

  /// ACL PHY and data-length policy.
  aclRadioPolicy(1),

  /// Preferences advertised by the Unicast Server during codec setup.
  unicastServerQosPreferences(2);

  /// Creates a section with its stable protocol identifier.
  const WirelessAudioConfigurationSection(this.id);

  /// Stable identifier used by the protocol.
  final int id;

  /// Bit used for this section in protocol masks.
  int get mask => 1 << id;
}

/// Controls OpenEarable's device-owned Bluetooth audio policies.
///
/// Standard LE Audio codec and stream negotiation continues to use PACS and
/// ASCS. This capability configures only the device's local policy and exposes
/// the resulting runtime state.
abstract class WirelessAudioConfigurationManager {
  /// Reads the policy features and ranges supported by the device.
  Future<WirelessAudioConfigurationCapabilities> getCapabilities();

  /// Reads the latest effective Bluetooth audio runtime state.
  Future<WirelessAudioConfigurationRuntimeState> getRuntimeState();

  /// Subscribes to effective Bluetooth audio runtime-state changes.
  ///
  /// Awaiting this method guarantees that the BLE notification subscription is
  /// active before the returned stream is consumed.
  Future<Stream<WirelessAudioConfigurationRuntimeState>>
      subscribeToRuntimeState();

  /// Sets the ACL connection [policy].
  ///
  /// When [persist] is true, the device retains the setting across restarts.
  Future<WirelessAudioConfigurationCommandResult> setAclConnectionPolicy(
    WirelessAudioConfigurationAclConnectionPolicy policy, {
    bool persist = false,
  });

  /// Sets the ACL radio [policy].
  ///
  /// When [persist] is true, the device retains the setting across restarts.
  Future<WirelessAudioConfigurationCommandResult> setAclRadioPolicy(
    WirelessAudioConfigurationAclRadioPolicy policy, {
    bool persist = false,
  });

  /// Sets the Unicast Server QoS [preferences].
  ///
  /// When [persist] is true, the device retains the setting across restarts.
  Future<WirelessAudioConfigurationCommandResult>
      setUnicastServerQosPreferences(
    WirelessAudioConfigurationUnicastServerQosPreferences preferences, {
    bool persist = false,
  });

  /// Reads the configured ACL connection policy.
  Future<WirelessAudioConfigurationConfiguredAclConnectionPolicy>
      getAclConnectionPolicy();

  /// Reads the configured ACL radio policy.
  Future<WirelessAudioConfigurationConfiguredAclRadioPolicy>
      getAclRadioPolicy();

  /// Reads the configured Unicast Server QoS preferences.
  Future<WirelessAudioConfigurationConfiguredUnicastServerQosPreferences>
      getUnicastServerQosPreferences();

  /// Restores compiled defaults for [sections].
  ///
  /// An empty set restores every section supported by the device.
  Future<WirelessAudioConfigurationCommandResult> restoreDefaults({
    Set<WirelessAudioConfigurationSection> sections = const {},
  });
}

/// Indicates that a wireless audio configuration command was rejected.
class WirelessAudioConfigurationException implements Exception {
  /// Creates an exception for the rejected protocol [result].
  const WirelessAudioConfigurationException(this.result);

  /// Rejection details reported by the device.
  final WirelessAudioConfigurationCommandResult result;

  @override
  String toString() =>
      'WirelessAudioConfigurationException(status: ${result.status}, '
      'errorDomain: ${result.error_domain}, errorCode: ${result.error_code})';
}
