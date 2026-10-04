import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import 'package:open_earable_flutter/src/fota/handlers/firmware_update_handler.dart';
import 'package:open_earable_flutter/src/fota/model/firmware_update_request.dart';

class _Manager implements FirmwareUpdateManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Upload extends FirmwareUpdateHandler {
  int calls = 0;
  @override
  Future<FirmwareUpdateManager> handleFirmwareUpdate(
    FirmwareUpdateRequest request,
    FirmwareUpdateCallback? callback,
  ) async {
    calls++;
    return _Manager();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const archiveChannel = MethodChannel('flutter_archive');
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fota-test-');
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => temp.path);
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(archiveChannel, null);
    await temp.delete(recursive: true);
  });
  for (final kind in [
    'archive',
    'json',
    'manifest',
    'missing image',
    'valid',
  ]) {
    test('unpacker cleans temporary files after $kind', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(archiveChannel,
          (call) async {
        if (kind == 'archive') throw PlatformException(code: 'invalid zip');
        final dir = call.arguments['destinationDir'] as String;
        final manifest = kind == 'json'
            ? '{'
            : kind == 'manifest'
                ? '{"format-version":1,"time":0,"files":"invalid-test-value"}'
                : '{"format-version":1,"time":0,"files":[{"file":"app.bin"}]}';
        await File('$dir/manifest.json').writeAsString(manifest);
        if (kind == 'valid') await File('$dir/app.bin').writeAsBytes([1, 2, 3]);
        return null;
      });
      final upload = _Upload();
      final handler = FirmwareUnpacker()..setNextHandler(upload);
      final request = MultiImageFirmwareUpdateRequest(
        firmware: LocalFirmware(
            name: 'test.zip',
            data: Uint8List(0),
            type: FirmwareType.multiImage,),
        zipFile: Uint8List(0),
      );
      if (kind == 'valid') {
        await handler.handleFirmwareUpdate(request, null);
        expect(upload.calls, 1);
        expect(request.firmwareImages!.single.data, [1, 2, 3]);
      } else {
        await expectLater(
            handler.handleFirmwareUpdate(request, null), throwsA(anything),);
        expect(upload.calls, 0);
      }
      expect(await temp.list().toList(), isEmpty);
    });
  }
}
