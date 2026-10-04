import 'dart:async';
import 'dart:typed_data';

import 'package:open_earable_protocols/open_earable_protocols.dart';

import '../../managers/ble_gatt_manager.dart';
import '../capabilities/wireless_audio_configuration_manager.dart';

/// Wireless audio configuration implementation for OpenEarable V2 devices.
class OpenEarableV2WirelessAudioConfigurationManager
    implements WirelessAudioConfigurationManager {
  /// Creates a manager backed by [bleManager].
  OpenEarableV2WirelessAudioConfigurationManager({
    required this.bleManager,
    required this.deviceId,
    this.responseTimeout = const Duration(seconds: 10),
  });

  /// BLE manager used to communicate with the device.
  final BleGattManager bleManager;

  /// Identifier of the OpenEarable device.
  final String deviceId;

  /// Maximum time to wait for a response indication.
  final Duration responseTimeout;

  Future<void> _operationQueue = Future<void>.value();
  int _nextRequestId = 0;

  @override
  Future<WirelessAudioConfigurationCapabilities> getCapabilities() async {
    final bytes = await _read(
      WirelessAudioConfigurationBleUuids.capabilitiesCharacteristicUuid,
    );
    return WirelessAudioConfigurationCapabilities.fromBytes(
      Uint8List.fromList(bytes),
    );
  }

  @override
  Future<WirelessAudioConfigurationRuntimeState> getRuntimeState() async {
    final bytes = await _read(
      WirelessAudioConfigurationBleUuids.runtimeStateCharacteristicUuid,
    );
    return WirelessAudioConfigurationRuntimeState.fromBytes(
      Uint8List.fromList(bytes),
    );
  }

  @override
  Future<Stream<WirelessAudioConfigurationRuntimeState>>
      subscribeToRuntimeState() async {
    final stream = await bleManager.subscribe(
      deviceId: deviceId,
      serviceId: WirelessAudioConfigurationBleUuids.serviceUuid,
      characteristicId:
          WirelessAudioConfigurationBleUuids.runtimeStateCharacteristicUuid,
    );
    return stream.map(
      (bytes) => WirelessAudioConfigurationRuntimeState.fromBytes(
        Uint8List.fromList(bytes),
      ),
    );
  }

  @override
  Future<WirelessAudioConfigurationCommandResult> setAclConnectionPolicy(
    WirelessAudioConfigurationAclConnectionPolicy policy, {
    bool persist = false,
  }) {
    return _execute<WirelessAudioConfigurationCommandResult>(
      WirelessAudioConfigurationSetAclConnectionPolicy(
        persist: persist ? 1 : 0,
        policy: policy,
      ),
    );
  }

  @override
  Future<WirelessAudioConfigurationCommandResult> setAclRadioPolicy(
    WirelessAudioConfigurationAclRadioPolicy policy, {
    bool persist = false,
  }) {
    return _execute<WirelessAudioConfigurationCommandResult>(
      WirelessAudioConfigurationSetAclRadioPolicy(
        persist: persist ? 1 : 0,
        policy: policy,
      ),
    );
  }

  @override
  Future<WirelessAudioConfigurationCommandResult>
      setUnicastServerQosPreferences(
    WirelessAudioConfigurationUnicastServerQosPreferences preferences, {
    bool persist = false,
  }) {
    return _execute<WirelessAudioConfigurationCommandResult>(
      WirelessAudioConfigurationSetUnicastServerQosPreferences(
        persist: persist ? 1 : 0,
        preferences: preferences,
      ),
    );
  }

  @override
  Future<WirelessAudioConfigurationConfiguredAclConnectionPolicy>
      getAclConnectionPolicy() {
    return _getConfiguration<
        WirelessAudioConfigurationConfiguredAclConnectionPolicy>(
      WirelessAudioConfigurationSection.aclConnectionPolicy,
    );
  }

  @override
  Future<WirelessAudioConfigurationConfiguredAclRadioPolicy>
      getAclRadioPolicy() {
    return _getConfiguration<
        WirelessAudioConfigurationConfiguredAclRadioPolicy>(
      WirelessAudioConfigurationSection.aclRadioPolicy,
    );
  }

  @override
  Future<WirelessAudioConfigurationConfiguredUnicastServerQosPreferences>
      getUnicastServerQosPreferences() {
    return _getConfiguration<
        WirelessAudioConfigurationConfiguredUnicastServerQosPreferences>(
      WirelessAudioConfigurationSection.unicastServerQosPreferences,
    );
  }

  @override
  Future<WirelessAudioConfigurationCommandResult> restoreDefaults({
    Set<WirelessAudioConfigurationSection> sections = const {},
  }) {
    final sectionMask = sections.fold<int>(
      0,
      (mask, section) => mask | section.mask,
    );
    return _execute<WirelessAudioConfigurationCommandResult>(
      WirelessAudioConfigurationRestoreDefaults(section_mask: sectionMask),
    );
  }

  Future<T> _getConfiguration<T>(
    WirelessAudioConfigurationSection section,
  ) {
    return _execute<T>(
      WirelessAudioConfigurationGetConfiguration(section: section.id),
    );
  }

  Future<T> _execute<T>(
    WirelessAudioConfigurationConfigurationCommandOperation operation,
  ) {
    return _runExclusive(() async {
      final requestId = _allocateRequestId();
      final responseIterator = StreamIterator<List<int>>(
        await bleManager.subscribe(
          deviceId: deviceId,
          serviceId: WirelessAudioConfigurationBleUuids.serviceUuid,
          characteristicId:
              WirelessAudioConfigurationBleUuids.responseCharacteristicUuid,
          indications: true,
        ),
      );

      try {
        final responseFuture = _nextResponse(responseIterator, requestId);
        responseFuture.ignore();
        await bleManager.write(
          deviceId: deviceId,
          serviceId: WirelessAudioConfigurationBleUuids.serviceUuid,
          characteristicId:
              WirelessAudioConfigurationBleUuids.commandCharacteristicUuid,
          byteData: WirelessAudioConfigurationConfigurationCommand(
            request_id: requestId,
            operation: operation,
          ).toBytes(),
        );

        final payload = (await responseFuture).payload;
        if (payload is WirelessAudioConfigurationCommandResult &&
            payload.status >= 4) {
          throw WirelessAudioConfigurationException(payload);
        }
        if (payload is! T) {
          throw StateError(
            'Expected wireless audio response $T, but received '
            '${payload.runtimeType}',
          );
        }
        return payload as T;
      } finally {
        await responseIterator.cancel();
      }
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  int _allocateRequestId() {
    final requestId = _nextRequestId;
    _nextRequestId = (_nextRequestId + 1) & 0xffff;
    return requestId;
  }

  Future<WirelessAudioConfigurationConfigurationResponse> _nextResponse(
    StreamIterator<List<int>> iterator,
    int requestId,
  ) async {
    while (await iterator.moveNext().timeout(responseTimeout)) {
      final response =
          WirelessAudioConfigurationConfigurationResponse.fromBytes(
        Uint8List.fromList(iterator.current),
      );
      if (response.request_id == requestId) {
        return response;
      }
    }
    throw StateError('Wireless audio configuration response stream closed');
  }

  Future<List<int>> _read(String characteristicId) {
    return bleManager.read(
      deviceId: deviceId,
      serviceId: WirelessAudioConfigurationBleUuids.serviceUuid,
      characteristicId: characteristicId,
    );
  }
}
