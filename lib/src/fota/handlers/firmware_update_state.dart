part of 'firmware_update_handler.dart';

/// Base state emitted by the firmware update handler chain.
sealed class FirmwareUpdateState {}

/// Emitted when a remote firmware artifact starts downloading.
class FirmwareDownloadStarted extends FirmwareUpdateState {}
// class FirmwareDownloadFinished extends FirmwareUpdateState {}

/// Emitted when a multi-image archive starts unpacking.
class FirmwareUnpackStarted extends FirmwareUpdateState {}
// class FirmwareUnpackFinished extends FirmwareUpdateState {}

/// Emitted when the upload step begins.
class FirmwareUploadStarted extends FirmwareUpdateState {}

/// Upload progress emitted by handler implementations that report byte-level
/// progress directly.
class FirmwareUploadProgress extends FirmwareUpdateState {
  final int progress;

  FirmwareUploadProgress(this.progress);
}

/// Emitted when the upload step finishes successfully.
class FirmwareUploadFinished extends FirmwareUpdateState {}
