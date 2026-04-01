/// Firmware-over-the-air (FOTA) support for discovering firmware images and
/// coordinating firmware update requests.
///
/// The exported APIs cover three main concerns:
/// - building a [FirmwareUpdateRequest] that identifies the target peripheral
///   and the selected firmware image,
/// - querying repositories for stable or beta firmware artifacts, and
/// - observing update progress through [UpdateBloc].
library;

export 'bloc/update_bloc.dart';
export 'model/firmware_update_request.dart';
export 'model/firmware_image.dart';
export 'providers/firmware_update_request_provider.dart';
export 'repository/firmware_image_repository.dart';
export 'repository/unified_firmware_image_repository.dart';
