import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/managers/ble_gatt_manager.dart';
import 'package:open_earable_flutter/src/models/capabilities/wireless_audio_configuration_manager.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2_wireless_audio_configuration_manager.dart';
import 'package:open_earable_protocols/open_earable_protocols.dart';

void main() {
  group('OpenEarableV2WirelessAudioConfigurationManager', () {
    test('reads capabilities and runtime state', () async {
      final bleManager = _FakeBleGattManager();
      final capabilities = _capabilities();
      final runtimeState = _runtimeState(sequence: 7);
      bleManager.readValues[WirelessAudioConfigurationBleUuids
          .capabilitiesCharacteristicUuid] = capabilities.toBytes();
      bleManager.readValues[WirelessAudioConfigurationBleUuids
          .runtimeStateCharacteristicUuid] = runtimeState.toBytes();
      final manager = _manager(bleManager);

      final decodedCapabilities = await manager.getCapabilities();
      final decodedRuntimeState = await manager.getRuntimeState();

      expect(decodedCapabilities.protocol_version, 1);
      expect(decodedCapabilities.supported_section_mask, 0x7);
      expect(decodedRuntimeState.sequence, 7);
      expect(decodedRuntimeState.acl_interval_us, 15000);
    });

    test('decodes runtime state notifications', () async {
      final bleManager = _FakeBleGattManager();
      final manager = _manager(bleManager);
      final stream = await manager.subscribeToRuntimeState();
      final nextState = stream.first;

      bleManager.emit(
        WirelessAudioConfigurationBleUuids.runtimeStateCharacteristicUuid,
        _runtimeState(sequence: 8).toBytes(),
      );

      expect((await nextState).sequence, 8);
      expect(
        bleManager.subscriptions,
        [WirelessAudioConfigurationBleUuids.runtimeStateCharacteristicUuid],
      );
    });

    test('encodes all mutating commands and returns command results', () async {
      final bleManager = _FakeBleGattManager();
      final manager = _manager(bleManager);
      final operations =
          <WirelessAudioConfigurationConfigurationCommandOperation>[];

      bleManager.onWrite = (write) {
        final command =
            WirelessAudioConfigurationConfigurationCommand.fromBytes(
          write.bytes,
        );
        operations.add(command.operation);
        bleManager.emitResponse(
          WirelessAudioConfigurationConfigurationResponse(
            request_id: command.request_id,
            payload: _successfulResult(),
          ),
        );
      };

      await manager.setAclConnectionPolicy(
        WirelessAudioConfigurationAclConnectionPolicy.fixedAclPolicy(
          WirelessAudioConfigurationFixedAclPolicy(
            interval_us: 15000,
            peripheral_latency: 0,
            supervision_timeout_ms: 4000,
          ),
        ),
        persist: true,
      );
      await manager.setAclRadioPolicy(
        WirelessAudioConfigurationAclRadioPolicy.preferredAclRadioPolicy(
          WirelessAudioConfigurationPreferredAclRadioPolicy(
            transmit_phy_mask: 2,
            receive_phy_mask: 2,
            transmit_max_data_octets: 251,
            transmit_max_time_us: 2120,
          ),
        ),
      );
      await manager.setUnicastServerQosPreferences(
        _qosPreferences(),
        persist: true,
      );
      await manager.restoreDefaults(
        sections: {
          WirelessAudioConfigurationSection.aclConnectionPolicy,
          WirelessAudioConfigurationSection.unicastServerQosPreferences,
        },
      );

      final connection =
          operations[0] as WirelessAudioConfigurationSetAclConnectionPolicy;
      final radio =
          operations[1] as WirelessAudioConfigurationSetAclRadioPolicy;
      final qos = operations[2]
          as WirelessAudioConfigurationSetUnicastServerQosPreferences;
      final restore =
          operations[3] as WirelessAudioConfigurationRestoreDefaults;
      expect(connection.persist, 1);
      expect(
        connection.policy.policy,
        isA<WirelessAudioConfigurationFixedAclPolicy>(),
      );
      expect(radio.persist, 0);
      expect(
        radio.policy.policy,
        isA<WirelessAudioConfigurationPreferredAclRadioPolicy>(),
      );
      expect(qos.persist, 1);
      expect(qos.preferences.maximum_transport_latency_ms, 20);
      expect(restore.section_mask, 0x5);
      expect(
        bleManager.writes.map((write) => write.requestId),
        [0, 1, 2, 3],
      );
      expect(
        bleManager.indicationSubscriptions,
        List.filled(
          4,
          WirelessAudioConfigurationBleUuids.responseCharacteristicUuid,
        ),
      );
    });

    test('gets each configured policy section with its stable id', () async {
      final bleManager = _FakeBleGattManager();
      final manager = _manager(bleManager);
      final requestedSections = <int>[];

      bleManager.onWrite = (write) {
        final command =
            WirelessAudioConfigurationConfigurationCommand.fromBytes(
          write.bytes,
        );
        final operation =
            command.operation as WirelessAudioConfigurationGetConfiguration;
        requestedSections.add(operation.section);
        final WirelessAudioConfigurationConfigurationResponsePayload payload;
        switch (operation.section) {
          case 0:
            payload = WirelessAudioConfigurationConfiguredAclConnectionPolicy(
              persisted: 1,
              policy: WirelessAudioConfigurationAclConnectionPolicy
                  .controllerDefaultAclPolicy(
                WirelessAudioConfigurationControllerDefaultAclPolicy(
                  reserved: 0,
                ),
              ),
            );
          case 1:
            payload = WirelessAudioConfigurationConfiguredAclRadioPolicy(
              persisted: 0,
              policy: WirelessAudioConfigurationAclRadioPolicy
                  .automaticAclRadioPolicy(
                WirelessAudioConfigurationAutomaticAclRadioPolicy(reserved: 0),
              ),
            );
          case 2:
            payload =
                WirelessAudioConfigurationConfiguredUnicastServerQosPreferences(
              persisted: 1,
              preferences: _qosPreferences(),
            );
          default:
            throw StateError('Unexpected section ${operation.section}');
        }
        bleManager.emitResponse(
          WirelessAudioConfigurationConfigurationResponse(
            request_id: command.request_id,
            payload: payload,
          ),
        );
      };

      final connection = await manager.getAclConnectionPolicy();
      final radio = await manager.getAclRadioPolicy();
      final qos = await manager.getUnicastServerQosPreferences();

      expect(requestedSections, [0, 1, 2]);
      expect(connection.persisted, 1);
      expect(radio.persisted, 0);
      expect(qos.preferences.preferred_retransmission_number, 2);
    });

    test('throws a typed exception when the device rejects a command',
        () async {
      final bleManager = _FakeBleGattManager();
      final manager = _manager(bleManager);
      bleManager.onWrite = (write) {
        bleManager.emitResponse(
          WirelessAudioConfigurationConfigurationResponse(
            request_id: write.requestId,
            payload: WirelessAudioConfigurationCommandResult(
              status: 5,
              error_domain: 1,
              error_code: -2,
              restart_required_mask: 0,
            ),
          ),
        );
      };

      await expectLater(
        manager.restoreDefaults(),
        throwsA(
          isA<WirelessAudioConfigurationException>()
              .having((error) => error.result.status, 'status', 5)
              .having((error) => error.result.error_code, 'error code', -2),
        ),
      );
    });

    test('serializes commands so response subscriptions cannot race', () async {
      final bleManager = _FakeBleGattManager();
      final manager = _manager(bleManager);
      final firstWrite = Completer<void>();
      final requestIds = <int>[];
      bleManager.onWrite = (write) {
        requestIds.add(write.requestId);
        if (requestIds.length == 1) {
          firstWrite.complete();
          return;
        }
        bleManager.emitResponse(
          WirelessAudioConfigurationConfigurationResponse(
            request_id: write.requestId,
            payload: _successfulResult(),
          ),
        );
      };

      final first = manager.restoreDefaults();
      await firstWrite.future;
      final second = manager.restoreDefaults();
      await Future<void>.delayed(Duration.zero);
      expect(requestIds, [0]);

      bleManager.emitResponse(
        WirelessAudioConfigurationConfigurationResponse(
          request_id: 0,
          payload: _successfulResult(),
        ),
      );
      await first;
      await second;

      expect(requestIds, [0, 1]);
    });
  });
}

OpenEarableV2WirelessAudioConfigurationManager _manager(
  BleGattManager bleManager,
) {
  return OpenEarableV2WirelessAudioConfigurationManager(
    bleManager: bleManager,
    deviceId: 'device',
  );
}

WirelessAudioConfigurationCommandResult _successfulResult() {
  return WirelessAudioConfigurationCommandResult(
    status: 0,
    error_domain: 0,
    error_code: 0,
    restart_required_mask: 0,
  );
}

WirelessAudioConfigurationUnicastServerQosPreferences _qosPreferences() {
  return WirelessAudioConfigurationUnicastServerQosPreferences(
    direction_mask: 3,
    unframed_supported: 1,
    preferred_phy_mask: 2,
    preferred_retransmission_number: 2,
    maximum_transport_latency_ms: 20,
    minimum_presentation_delay_us: 10000,
    maximum_presentation_delay_us: 40000,
    preferred_minimum_presentation_delay_us: 20000,
    preferred_maximum_presentation_delay_us: 30000,
  );
}

WirelessAudioConfigurationCapabilities _capabilities() {
  return WirelessAudioConfigurationCapabilities(
    protocol_version: 1,
    supported_section_mask: 0x7,
    supported_command_mask: 0x1f,
    supported_acl_policy_mask: 0xf,
    supported_phy_mask: 0x7,
    minimum_acl_interval_us: 7500,
    maximum_acl_interval_us: 40000,
    acl_interval_resolution_us: 1250,
    maximum_acl_peripheral_latency: 30,
    minimum_acl_supervision_timeout_ms: 100,
    maximum_acl_supervision_timeout_ms: 32000,
    minimum_acl_data_octets: 27,
    maximum_acl_data_octets: 251,
    minimum_acl_data_time_us: 328,
    maximum_acl_data_time_us: 2120,
    supported_audio_direction_mask: 3,
    maximum_preferred_retransmission_number: 15,
    maximum_transport_latency_ms: 4000,
    minimum_presentation_delay_us: 0,
    maximum_presentation_delay_us: 4000000,
    feature_flags: 0x7,
  );
}

WirelessAudioConfigurationRuntimeState _runtimeState({required int sequence}) {
  return WirelessAudioConfigurationRuntimeState(
    sequence: sequence,
    validity_flags: 0x7f,
    connection_id: 3,
    stream_id: 1,
    direction: 0,
    lifecycle_state: 5,
    acl_interval_us: 15000,
    acl_peripheral_latency: 0,
    acl_supervision_timeout_ms: 4000,
    transmit_phy: 2,
    receive_phy: 2,
    transmit_data_octets: 251,
    receive_data_octets: 251,
    lc3_sampling_frequency_hz: 48000,
    lc3_frame_duration_us: 10000,
    lc3_octets_per_frame: 100,
    lc3_frame_blocks_per_sdu: 1,
    lc3_channel_allocation: 1,
    iso_sdu_interval_us: 10000,
    iso_framing: 0,
    iso_phy: 2,
    iso_retransmission_number: 2,
    iso_maximum_sdu_octets: 100,
    iso_maximum_transport_latency_ms: 20,
    presentation_delay_us: 30000,
    audio_underrun_count: 0,
    acl_adjustment_count: 0,
  );
}

class _FakeBleGattManager implements BleGattManager {
  final _streams = <String, StreamController<List<int>>>{};
  final readValues = <String, List<int>>{};
  final subscriptions = <String>[];
  final indicationSubscriptions = <String>[];
  final writes = <_Write>[];

  void Function(_Write write)? onWrite;

  void emit(String characteristicId, List<int> bytes) {
    _controller(characteristicId).add(bytes);
  }

  void emitResponse(
    WirelessAudioConfigurationConfigurationResponse response,
  ) {
    emit(
      WirelessAudioConfigurationBleUuids.responseCharacteristicUuid,
      response.toBytes(),
    );
  }

  @override
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
    bool withoutResponse = false,
  }) async {
    final write = _Write(characteristicId, Uint8List.fromList(byteData));
    writes.add(write);
    onWrite?.call(write);
  }

  @override
  Future<Stream<List<int>>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    bool indications = false,
  }) async {
    subscriptions.add(characteristicId);
    if (indications) {
      indicationSubscriptions.add(characteristicId);
    }
    return _controller(characteristicId).stream;
  }

  StreamController<List<int>> _controller(String characteristicId) {
    return _streams.putIfAbsent(
      characteristicId,
      () => StreamController<List<int>>.broadcast(sync: true),
    );
  }

  @override
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    return readValues[characteristicId] ?? [];
  }

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  }) async {
    return true;
  }

  @override
  Future<bool> hasService({
    required String deviceId,
    required String serviceId,
  }) async {
    return true;
  }

  @override
  bool isConnected(String deviceId) => true;
}

class _Write {
  const _Write(this.characteristicId, this.bytes);

  final String characteristicId;
  final Uint8List bytes;

  int get requestId =>
      WirelessAudioConfigurationConfigurationCommand.fromBytes(bytes)
          .request_id;
}
