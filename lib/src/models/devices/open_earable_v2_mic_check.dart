import 'dart:async';

import '../../../open_earable_flutter.dart';

const String sealCheckServiceUuid = '12345678-1234-5678-9abc-def123456789';
const String sealCheckStartCharacteristicUuid =
    '12345679-1234-5678-9abc-def123456789';
const String sealCheckResultCharacteristicUuid =
    '1234567A-1234-5678-9abc-def123456789';
const String sealCheckMicSelectCharacteristicUuid =
    '1234567B-1234-5678-9abc-def123456789';

class OpenEarableV2MicrophoneCheckImp implements MicrophoneCheckManager {
  final BleGattManager bleManager;
  final String deviceId;

  bool _running = false;

  OpenEarableV2MicrophoneCheckImp({
    required this.bleManager,
    required this.deviceId,
  });

  @override
  Future<MicrophoneCheckResult> runOuterMicrophoneCheck({
    Duration timeout = const Duration(seconds: 12),
  }) {
    // Firmware maps the left recording channel to the outer microphone path.
    return runMicrophoneCheck(
      leftEnabled: true,
      rightEnabled: false,
      timeout: timeout,
    );
  }

  @override
  Future<MicrophoneCheckResult> runInnerMicrophoneCheck({
    Duration timeout = const Duration(seconds: 12),
  }) {
    // Firmware maps the right recording channel to the inner microphone path.
    return runMicrophoneCheck(
      leftEnabled: false,
      rightEnabled: true,
      timeout: timeout,
    );
  }

  @override
  Future<MicrophoneCheckResult> runMicrophoneCheck({
    required bool leftEnabled,
    required bool rightEnabled,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!bleManager.isConnected(deviceId)) {
      throw StateError('Device is not connected: $deviceId');
    }
    if (!leftEnabled && !rightEnabled) {
      throw ArgumentError(
        'At least one microphone channel must be enabled for mic check.',
      );
    }
    if (_running) {
      throw StateError('Microphone check already running on $deviceId');
    }
    _running = true;

    final completer = Completer<MicrophoneCheckResult>();
    late final StreamSubscription<List<int>> subscription;
    Timer? timer;

    void completeWithError(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) {
        return;
      }
      if (stackTrace != null) {
        completer.completeError(error, stackTrace);
      } else {
        completer.completeError(error);
      }
    }

    subscription = bleManager
        .subscribe(
      deviceId: deviceId,
      serviceId: sealCheckServiceUuid,
      characteristicId: sealCheckResultCharacteristicUuid,
    )
        .listen(
      (payload) {
        if (payload.length < MicrophoneCheckResult.expectedPayloadBytes) {
          logger.w(
            'Ignored short microphone check payload: ${payload.length} bytes',
          );
          return;
        }
        try {
          final parsed = MicrophoneCheckResult.fromBytes(payload);
          if (!completer.isCompleted) {
            completer.complete(parsed);
          }
        } catch (error, stackTrace) {
          completeWithError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        completeWithError(
          StateError('Microphone check notification failed: $error'),
          stackTrace,
        );
      },
    );

    try {
      await bleManager.write(
        deviceId: deviceId,
        serviceId: sealCheckServiceUuid,
        characteristicId: sealCheckMicSelectCharacteristicUuid,
        byteData: <int>[
          leftEnabled ? 0x01 : 0x00,
          rightEnabled ? 0x01 : 0x00,
        ],
      );

      await bleManager.write(
        deviceId: deviceId,
        serviceId: sealCheckServiceUuid,
        characteristicId: sealCheckStartCharacteristicUuid,
        byteData: const <int>[0xFF],
      );

      timer = Timer(timeout, () {
        completeWithError(
          TimeoutException(
            'Timed out waiting for microphone check result.',
            timeout,
          ),
        );
      });

      return await completer.future;
    } finally {
      timer?.cancel();
      await subscription.cancel();
      _running = false;
    }
  }
}
