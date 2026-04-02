part of 'update_bloc.dart';

/// Base state emitted by [UpdateBloc].
@immutable
sealed class UpdateState extends Equatable {}

/// Initial state before an update has started.
final class UpdateInitial extends UpdateState {
  @override
  List<Object?> get props => [true];
}

/// High-level firmware update stage description.
class UpdateFirmware extends UpdateState {
  final String stage;

  UpdateFirmware(this.stage);

  @override
  List<Object?> get props => [stage];
}

/// Upload stage with progress information for the active image.
final class UpdateProgressFirmware extends UpdateFirmware {
  final int progress;
  final int imageNumber;

  UpdateProgressFirmware(super.state, this.progress, this.imageNumber);

  @override
  List<Object?> get props => [stage, progress];
}

/// Successful completion marker for the update flow.
final class UpdateCompleteSuccess extends UpdateFirmware {
  UpdateCompleteSuccess() : super("Update complete");
}

/// Failure marker for the update flow.
final class UpdateCompleteFailure extends UpdateFirmware {
  final String error;

  UpdateCompleteFailure(this.error) : super("Update failed");

  @override
  List<Object?> get props => [stage, error];
}

/// Aborted marker for the update flow.
final class UpdateCompleteAborted extends UpdateFirmware {
  UpdateCompleteAborted() : super("Update aborted");
}

/// Snapshot of the current stage plus the completed stage history.
class UpdateFirmwareStateHistory extends UpdateState {
  final UpdateFirmware? currentState;
  final List<UpdateFirmware> history;
  final bool isComplete;
  final FirmwareUpdateManager? updateManager;

  UpdateFirmwareStateHistory(
    this.currentState,
    this.history, {
    this.isComplete = false,
    this.updateManager,
  });

  @override
  List<Object?> get props => [currentState, history];
}
