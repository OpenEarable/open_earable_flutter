# Firmware Updates In Your App

This guide is written for app developers using `open_earable_flutter`. It explains how to list firmware versions, let a user select a device and firmware file, start an update, and render progress in your own UI.

## What The Library Provides

The FOTA API gives you the building blocks for a firmware update flow:

- `FirmwareImageRepository` to load stable firmware releases from GitHub
- `UnifiedFirmwareRepository` to load stable releases and optional beta builds
- `RemoteFirmware` and `LocalFirmware` to represent selectable firmware files
- `SelectedPeripheral` to identify the target device
- `SingleImageFirmwareUpdateRequest` and `MultiImageFirmwareUpdateRequest` to describe the update job
- `UpdateBloc` to execute the update and emit UI-friendly progress states

## Before You Start

Make sure your app can already:

1. Discover and connect to a wearable with `WearableManager`
2. Hold on to the connected `Wearable`
3. Ask the user which firmware they want to install

If you have not connected to a device yet, start there first. A firmware update needs a connected `Wearable` so you can pass its device identifier into `SelectedPeripheral`.

## Step 1: Get The Target Device

Once your app has a connected wearable, convert it into a `SelectedPeripheral`:

```dart
final SelectedPeripheral selectedPeripheral = SelectedPeripheral(
  name: wearable.name,
  identifier: wearable.deviceId,
);
```

The `identifier` is what the underlying update manager uses to talk to the device.

## Step 2: Offer Firmware Choices

You can let the user choose firmware from a remote repository, from a local file, or both.

### Option A: Show Stable Releases

Use `FirmwareImageRepository` if you only want official releases:

```dart
final repository = FirmwareImageRepository();
final List<RemoteFirmware> firmwares = await repository.getFirmwareImages();
```

Each `RemoteFirmware` contains:

- `name`: a UI-friendly label
- `version`: the release version
- `url`: the download URL
- `type`: `FirmwareType.singleImage` or `FirmwareType.multiImage`

You can use that list in any widget:

```dart
ListView.builder(
  itemCount: firmwares.length,
  itemBuilder: (context, index) {
    final firmware = firmwares[index];
    return ListTile(
      title: Text(firmware.name),
      subtitle: Text(firmware.version),
      onTap: () {
        // store the selected firmware in your state
      },
    );
  },
);
```

### Option B: Include Beta Builds

If your app should optionally expose preview firmware:

```dart
final repository = UnifiedFirmwareRepository();
final List<FirmwareEntry> entries = await repository.getAllFirmwares(
  includeBeta: true,
);
```

`FirmwareEntry` tells you whether an item is stable or beta:

```dart
for (final entry in entries) {
  final firmware = entry.firmware;
  final sourceLabel = entry.isBeta ? 'Beta' : 'Stable';
  print('${firmware.name} [$sourceLabel]');
}
```

### Option C: Let The User Pick A Local File

If the user already has a firmware file, create a `LocalFirmware` object from the file bytes. The important part is setting the correct `FirmwareType`.

```dart
final bytes = await file.readAsBytes();

final localFirmware = LocalFirmware(
  name: 'my_firmware.zip',
  data: bytes,
  type: FirmwareType.multiImage,
);
```

Use:

- `FirmwareType.singleImage` for raw single-image files such as `.bin`
- `FirmwareType.multiImage` for archive-based FOTA bundles such as `.zip`

## Step 3: Build The Update Request

The request type depends on the selected firmware format.

### Remote Or Local Multi-Image Firmware

Use `MultiImageFirmwareUpdateRequest` for `.zip`-based updates:

```dart
final request = MultiImageFirmwareUpdateRequest(
  peripheral: selectedPeripheral,
  firmware: selectedFirmware,
);
```

`selectedFirmware` can be either:

- a `RemoteFirmware` with `type == FirmwareType.multiImage`
- a `LocalFirmware` with `type == FirmwareType.multiImage`

### Local Single-Image Firmware

Use `SingleImageFirmwareUpdateRequest` for local `.bin` updates:

```dart
final request = SingleImageFirmwareUpdateRequest(
  peripheral: selectedPeripheral,
  firmware: localFirmware,
);
```

## Step 4: Start The Update With `UpdateBloc`

Create the bloc with the prepared request and dispatch `BeginUpdateProcess`.

```dart
final updateBloc = UpdateBloc(
  firmwareUpdateRequest: request,
);

updateBloc.add(BeginUpdateProcess());
```

In a Flutter screen this is usually done with `BlocProvider`:

```dart
BlocProvider(
  create: (_) => UpdateBloc(firmwareUpdateRequest: request),
  child: const FirmwareUpdateScreen(),
)
```

## Step 5: Render Update Progress

`UpdateBloc` emits `UpdateState` objects you can map directly to your UI.

The most important states are:

- `UpdateInitial`: nothing has started yet
- `UpdateFirmwareStateHistory`: the update is running or has completed
- `UpdateCompleteSuccess`: appears inside the history as the successful end state
- `UpdateCompleteFailure`: appears inside the history as the failed end state

The simplest integration pattern is:

```dart
BlocBuilder<UpdateBloc, UpdateState>(
  builder: (context, state) {
    switch (state) {
      case UpdateInitial():
        return ElevatedButton(
          onPressed: () {
            context.read<UpdateBloc>().add(BeginUpdateProcess());
          },
          child: const Text('Start update'),
        );

      case UpdateFirmwareStateHistory():
        if (state.currentState is UpdateProgressFirmware) {
          final progressState = state.currentState as UpdateProgressFirmware;
          return Text('Uploading ${progressState.progress}%');
        }

        if (state.isComplete) {
          final lastState = state.history.isNotEmpty ? state.history.last : null;
          if (lastState is UpdateCompleteFailure) {
            return Text('Update failed: ${lastState.error}');
          }
          return const Text('Update completed');
        }

        return Text(state.currentState?.stage ?? 'Preparing update');

      default:
        return const Text('Unknown update state');
    }
  },
)
```

## What Happens Internally

You do not need to call the lower-level handler classes directly, but it helps to know what `UpdateBloc` is doing:

1. `FirmwareDownloader` downloads remote firmware files
2. `FirmwareUnpacker` extracts `.zip` bundles and reads `manifest.json`
3. `FirmwareUpdater` sends the prepared image data to the device

This means:

- remote firmware files are downloaded automatically
- multi-image archives are unpacked automatically
- local firmware files skip the download step

## Complete Example

This is the minimal end-to-end shape of a typical integration:

```dart
final repository = FirmwareImageRepository();
final firmwares = await repository.getFirmwareImages();

final selectedFirmware = firmwares.first;

final request = MultiImageFirmwareUpdateRequest(
  peripheral: SelectedPeripheral(
    name: wearable.name,
    identifier: wearable.deviceId,
  ),
  firmware: selectedFirmware,
);

BlocProvider(
  create: (_) => UpdateBloc(firmwareUpdateRequest: request),
  child: BlocBuilder<UpdateBloc, UpdateState>(
    builder: (context, state) {
      if (state is UpdateInitial) {
        return ElevatedButton(
          onPressed: () {
            context.read<UpdateBloc>().add(BeginUpdateProcess());
          },
          child: const Text('Install firmware'),
        );
      }

      if (state is UpdateFirmwareStateHistory) {
        final current = state.currentState;
        if (current is UpdateProgressFirmware) {
          return Text('Uploading ${current.progress}%');
        }

        if (state.isComplete) {
          final last = state.history.isNotEmpty ? state.history.last : null;
          if (last is UpdateCompleteFailure) {
            return Text('Update failed: ${last.error}');
          }
          return const Text('Update complete');
        }

        return Text(current?.stage ?? 'Working...');
      }

      return const SizedBox.shrink();
    },
  ),
);
```

## Optional Helper For Multi-Step UIs

The library also exposes `FirmwareUpdateRequestProvider`. It is a convenience helper used by the example app to collect:

- the selected firmware
- the selected wearable
- the current step in a stepper-style UI

You can use it if it matches your UI, but it is not required. Many apps will prefer their own state management and only use:

- the repository classes
- the request models
- `UpdateBloc`

## Error Handling And User Guidance

Your UI should be prepared for these cases:

- no firmware selected
- no device selected
- network failure while loading remote firmware
- network failure while downloading a remote firmware file
- invalid or unsupported archive contents
- upload failure reported by the device or transport layer

Recommended UX:

1. Disable the update button until both firmware and device are selected
2. Show a clear loading state while releases are being fetched
3. Show the current stage text from `UpdateFirmwareStateHistory.currentState`
4. Show the failure message from `UpdateCompleteFailure.error`
5. Allow the user to retry after a failure

## Notes

- Multi-image `.zip` updates are expected to contain a valid `manifest.json`
- If a manifest contains multiple images, each file entry must define an image index
- `UnifiedFirmwareRepository` caches results for 15 minutes unless you request a refresh
- The current upload path uses `mcumgr_flutter` under the hood

## Related Source Files

If you want to inspect the implementation behind the public APIs, these are the main files:

- `lib/src/fota/model/firmware_update_request.dart`
- `lib/src/fota/repository/firmware_image_repository.dart`
- `lib/src/fota/repository/unified_firmware_image_repository.dart`
- `lib/src/fota/bloc/update_bloc.dart`
- `lib/src/fota/providers/firmware_update_request_provider.dart`
