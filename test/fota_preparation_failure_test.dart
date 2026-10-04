import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import 'package:open_earable_flutter/src/fota/bloc/update_bloc.dart';
import 'package:open_earable_flutter/src/fota/handlers/firmware_update_handler.dart';
import 'package:open_earable_flutter/src/fota/model/firmware_update_request.dart';

class _Handler extends FirmwareUpdateHandler {
  final Future<FirmwareUpdateManager> Function(FirmwareUpdateCallback?) run;
  _Handler(this.run);
  @override
  Future<FirmwareUpdateManager> handleFirmwareUpdate(
    FirmwareUpdateRequest request,
    FirmwareUpdateCallback? callback,
  ) =>
      run(callback);
}

class _Bloc extends UpdateBloc {
  final FirmwareUpdateHandler handler;
  _Bloc(this.handler) : super(firmwareUpdateRequest: FirmwareUpdateRequest());
  @override
  FirmwareUpdateHandler createFirmwareUpdateHandler() => handler;
}

Future<UpdateFirmwareStateHistory> completed(UpdateBloc bloc) => bloc.stream
    .where((s) => s is UpdateFirmwareStateHistory && s.isComplete)
    .cast<UpdateFirmwareStateHistory>()
    .first
    .timeout(const Duration(seconds: 1));

void main() {
  for (final unpackStarted in [false, true]) {
    test('preparation failure completes (unpack started: $unpackStarted)',
        () async {
      final bloc = _Bloc(_Handler((callback) async {
        if (unpackStarted) callback?.call(FirmwareUnpackStarted());
        throw const FormatException('Invalid firmware manifest');
      }),);
      addTearDown(bloc.close);
      final result = completed(bloc);
      bloc.add(BeginUpdateProcess());
      final state = await result;
      expect(state.currentState, isNull);
      expect(state.history.last, isA<UpdateCompleteFailure>());
      expect((state.history.last as UpdateCompleteFailure).error,
          contains('Invalid firmware manifest'),);
    });
  }

  test('one abort completes before any progress history exists', () async {
    final bloc =
        _Bloc(_Handler((_) => Completer<FirmwareUpdateManager>().future));
    addTearDown(bloc.close);
    final result = completed(bloc);
    bloc.add(AbortUpdate());
    expect((await result).history.last, isA<UpdateCompleteAborted>());
  });

  test('abort during preparation stops the next upload stage', () async {
    final resume = Completer<void>();
    var uploadStarted = false;
    final bloc = _Bloc(_Handler((callback) async {
      callback?.call(FirmwareUnpackStarted());
      await resume.future;
      callback?.call(FirmwareUploadStarted());
      uploadStarted = true;
      throw StateError('Must not start uploading');
    }),);
    addTearDown(bloc.close);
    final unpack =
        bloc.stream.firstWhere((s) => s is UpdateFirmwareStateHistory);
    bloc.add(BeginUpdateProcess());
    await unpack;
    final result = completed(bloc);
    bloc.add(AbortUpdate());
    expect((await result).history.last, isA<UpdateCompleteAborted>());
    resume.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(uploadStarted, isFalse);
    expect((bloc.state as UpdateFirmwareStateHistory).isComplete, isTrue);
    expect((bloc.state as UpdateFirmwareStateHistory).history.last,
        isA<UpdateCompleteAborted>(),);
  });
}
