part of 'update_bloc.dart';

/// Base event processed by [UpdateBloc].
@immutable
sealed class UpdateEvent {}

/// Starts the firmware update flow for the configured request.
class BeginUpdateProcess extends UpdateEvent {}

/// Signals that the download step has started.
class DownloadStarted extends UpdateEvent {}

/// Signals that archive unpacking has started.
class UnpackStarted extends UpdateEvent {}

/// Generic upload-stage event carrying a human-readable state label.
class UploadState extends UpdateEvent {
  final String state;

  UploadState(this.state);
}

/// Upload state that also reports progress for the current image.
class UploadProgress extends UploadState {
  final int progress;
  final int imageNumber;

  UploadProgress({
    required String stage,
    required this.progress,
    required this.imageNumber,
  }) : super(stage);
}

/// Signals that the upload completed successfully.
class UploadFinished extends UpdateEvent {}

/// Signals that the update failed with [error].
class UploadFailed extends UpdateEvent {
  final String error;

  UploadFailed(this.error);
}

/// Records a firmware selection in event-driven integrations.
class FirmwareSelected extends UpdateEvent {
  final SelectedFirmware firmware;

  FirmwareSelected(this.firmware);
}

/// Records a peripheral selection in event-driven integrations.
class PeripheralSelected extends UpdateEvent {
  final SelectedPeripheral peripheral;

  PeripheralSelected(this.peripheral);
}

/// Stops the active update manager and resets any in-flight upload.
class ResetUpdate extends UpdateEvent {}
