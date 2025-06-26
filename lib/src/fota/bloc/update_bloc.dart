import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import '../handlers/firmware_update_handler.dart';
import '../model/firmware_update_request.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart' as rx;
import 'package:tuple/tuple.dart';

part 'update_event.dart';
part 'update_state.dart';

class UpdateBloc extends Bloc<UpdateEvent, UpdateState> {
  final FirmwareUpdateRequest firmwareUpdateRequest;
  UpdateFirmwareStateHistory? _state;
  FirmwareUpdateManager? _firmwareUpdateManager;

  UpdateBloc({required this.firmwareUpdateRequest}) : super(UpdateInitial()) {
    on<BeginUpdateProcess>((event, emit) async {
      emit(UpdateFirmware('Begin update process'));
      final handler = createFirmwareUpdateHandler();

      _state = null;

      _firmwareUpdateManager = await handler.handleFirmwareUpdate(
        firmwareUpdateRequest,
        (FirmwareUpdateState state) => add(_StateConverter.convert(state)),
      );

      final progressStream = _firmwareUpdateManager!.progressStream
          .map(
            (event) => event.bytesSent.toDouble() / event.imageSize.toDouble(),
          )
          .startWith(0);

      final imageProgressStream = progressStream.scan<Tuple2<int, double>>(
        (accumulated, currentProgress, index) {
          final previousProgress = accumulated.item2;
          var imageNumber = accumulated.item1;

          if (currentProgress < previousProgress) {
            imageNumber += 1;
          }

          return Tuple2(imageNumber, currentProgress);
        },
        Tuple2(0, 0.0),
      );

      final logManager = _firmwareUpdateManager!.logger;

      logManager.logMessageStream.where((log) => log.level.rawValue > 1).listen(
        (log) {
          print(log.message);
        },
        onDone: () {
          print('done');
        },
        onError: (error) {
          print('error: $error');
        },
      );

      rx.CombineLatestStream.combine2(
        imageProgressStream,
        _firmwareUpdateManager!.updateStateStream!,
        (Tuple2<int, double> progressData, FirmwareUpgradeState updateState) {
          final imageNumber = progressData.item1;
          final progress = (progressData.item2 * 100).toInt();

          if (updateState == FirmwareUpgradeState.upload) {
            return UploadProgress(
              progress: progress,
              stage: updateState.toString(),
              imageNumber: imageNumber,
            );
          } else if (updateState == FirmwareUpgradeState.success) {
            return UploadFinished();
          } else {
            return UploadState(updateState.toString());
          }
        },
      ).listen(
        add,
        onError: (error) {
          print(error);
          add(UploadFailed(error.toString()));
        },
      );
    });
    on<DownloadStarted>((event, emit) {
      _state = _updatedState(UpdateFirmware('Download firmware'));
      emit(_state!);
    });
    on<UnpackStarted>((event, emit) {
      _state = _updatedState(UpdateFirmware('Unpack firmware'));
      emit(_state!);
    });
    on<UploadState>((event, emit) {
      if (event is UploadProgress) {
        _state = _updatedState(
          UpdateProgressFirmware(
            event.state,
            event.progress,
            event.imageNumber,
          ),
        );
        emit(_state!);
      } else {
        _state = _updatedState(UpdateFirmware(event.state));
        emit(_state!);
      }
    });
    on<UploadFinished>((event, emit) {
      _state = _updatedState(
        UpdateCompleteSuccess(),
        updateManager: _firmwareUpdateManager,
      );
      emit(_state!);
    });
    on<UploadFailed>((event, emit) {
      _state = _updatedState(
        UpdateCompleteFailure(event.error),
        updateManager: _firmwareUpdateManager,
      );
      emit(_state!);
    });
    on<ResetUpdate>((event, emit) {
      _firmwareUpdateManager?.kill();
    });
  }

  UpdateFirmwareStateHistory _updatedState(
    UpdateFirmware currentState, {
    FirmwareUpdateManager? updateManager,
  }) {
    if (_state == null) {
      return UpdateFirmwareStateHistory(
        currentState,
        const [],
        updateManager: updateManager,
      );
    } else if (_state!.history.isEmpty) {
      return UpdateFirmwareStateHistory(
        currentState,
        [_state!.currentState!],
        updateManager: updateManager,
      );
    } else if (currentState is UpdateProgressFirmware) {
      if (_state!.currentState is UpdateProgressFirmware) {
        return UpdateFirmwareStateHistory(
          currentState,
          _state!.history,
          updateManager: updateManager,
        );
      } else {
        return UpdateFirmwareStateHistory(
          currentState,
          _state!.history + [_state!.currentState!],
          updateManager: updateManager,
        );
      }
    } else if (currentState is UpdateCompleteSuccess ||
        currentState is UpdateCompleteFailure) {
      return UpdateFirmwareStateHistory(
        null,
        _state!.history + [currentState],
        isComplete: true,
        updateManager: updateManager,
      );
    } else {
      return UpdateFirmwareStateHistory(
        currentState,
        _state!.history + [_state!.currentState!],
        updateManager: updateManager,
      );
    }
  }

  FirmwareUpdateHandler createFirmwareUpdateHandler() {
    FirmwareUpdateHandler handler = FirmwareDownloader()
      ..setNextHandler(
        FirmwareUnpacker()
          ..setNextHandler(
            FirmwareUpdater(),
          ),
      );

    return handler;
  }
}

class _StateConverter {
  static UpdateEvent convert(FirmwareUpdateState state) {
    return switch (state) {
      FirmwareDownloadStarted() => DownloadStarted(),
      FirmwareUnpackStarted() => UnpackStarted(),
      FirmwareUploadProgress(progress: var progress) => UploadProgress(
          stage: "Upload firmware",
          progress: progress,
          imageNumber: 0,
        ),
      FirmwareUploadFinished() => UploadFinished(),
      FirmwareUploadStarted() => UploadState("Upload firmware"),
    };
  }
}
